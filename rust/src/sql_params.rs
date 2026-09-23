//! Named-parameter rewriter shared by the SQL drivers.
//!
//! Turns `@name` placeholders into the driver's positional form (`$1`, `?`,
//! `@P1`) and returns the values in the order they must be bound.
//!
//! It is a minimal lexer, not a byte scan: `@name` is only recognised OUTSIDE
//! string literals, quoted identifiers, comments and (Postgres) dollar-quoted
//! blocks. A byte scan rewrote `'thalya@gmail.com'` into `'thalya$1.com'` and
//! corrupted stored data; this module must never touch anything quoted.
//!
//! Slicing is always done at ASCII positions (`@` and the end of an ASCII
//! identifier run), so multibyte UTF-8 text is copied verbatim and never
//! split (the "byte index N is not a char boundary" panic).

use serde_json::{Map, Value};

// Each driver is built as its own cdylib with one feature, so only one
// variant is constructed per build.
#[allow(dead_code)]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Dialect {
    Sqlite,
    Postgres,
    Mysql,
    Mssql,
}

impl Dialect {
    fn placeholder(self, n: u32) -> String {
        match self {
            Dialect::Sqlite | Dialect::Mysql => "?".to_string(),
            Dialect::Postgres => format!("${}", n),
            Dialect::Mssql => format!("@P{}", n),
        }
    }

    /// `\'` (and `\\`) escape inside `'...'` / `"..."`: MySQL default
    /// sql_mode (no NO_BACKSLASH_ESCAPES). Postgres standard strings and the
    /// others treat backslash literally; Postgres `E'...'` is handled apart.
    fn backslash_escapes(self) -> bool {
        matches!(self, Dialect::Mysql)
    }
    fn hash_comments(self) -> bool {
        matches!(self, Dialect::Mysql)
    }
    fn backtick_ident(self) -> bool {
        matches!(self, Dialect::Mysql | Dialect::Sqlite)
    }
    fn bracket_ident(self) -> bool {
        matches!(self, Dialect::Mssql | Dialect::Sqlite)
    }
    fn dollar_quoting(self) -> bool {
        matches!(self, Dialect::Postgres)
    }
    fn nested_block_comments(self) -> bool {
        matches!(self, Dialect::Postgres)
    }
    fn e_strings(self) -> bool {
        matches!(self, Dialect::Postgres)
    }
}

fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// Rewrites `@name` placeholders in `sql` for `dialect`.
///
/// Every occurrence gets its own placeholder number and its own bound value
/// (a name used twice is bound twice). Unknown names bind `NULL`.
pub fn rewrite(sql: &str, params: &Map<String, Value>, dialect: Dialect) -> (String, Vec<Value>) {
    let bytes = sql.as_bytes();
    let n = bytes.len();
    let mut out = String::with_capacity(sql.len() + 8);
    let mut values = Vec::new();
    let mut index = 0u32;
    // Start of the pending slice of `sql` not yet copied to `out`.
    let mut copied = 0usize;
    let mut i = 0usize;

    while i < n {
        let b = bytes[i];
        match b {
            b'\'' => {
                // Postgres E'...' (escape string): backslash escapes apply.
                // The `E` must be a standalone prefix (not the tail of a word).
                let e_string = dialect.e_strings()
                    && i > 0
                    && (bytes[i - 1] == b'E' || bytes[i - 1] == b'e')
                    && (i < 2 || !is_word(bytes[i - 2]));
                i = skip_quoted(bytes, i + 1, b'\'', dialect.backslash_escapes() || e_string);
            }
            b'"' => {
                i = skip_quoted(bytes, i + 1, b'"', dialect.backslash_escapes());
            }
            b'`' if dialect.backtick_ident() => {
                i = skip_quoted(bytes, i + 1, b'`', false);
            }
            b'[' if dialect.bracket_ident() => {
                i = skip_bracket(bytes, i + 1, dialect == Dialect::Mssql);
            }
            b'-' if i + 1 < n && bytes[i + 1] == b'-' => {
                // MySQL only treats `--` as a comment when followed by
                // whitespace or end of input (`1--1` is arithmetic there).
                let is_comment = dialect != Dialect::Mysql
                    || i + 2 >= n
                    || bytes[i + 2].is_ascii_whitespace();
                if is_comment {
                    i = skip_line(bytes, i + 2);
                } else {
                    i += 2;
                }
            }
            b'#' if dialect.hash_comments() => {
                i = skip_line(bytes, i + 1);
            }
            b'/' if i + 1 < n && bytes[i + 1] == b'*' => {
                i = skip_block_comment(bytes, i + 2, dialect.nested_block_comments());
            }
            // `$$ ... $$` / `$tag$ ... $tag$`. A `$` glued to a word is part of
            // an identifier (`foo$bar`), not a quote opener.
            b'$' if dialect.dollar_quoting() && (i == 0 || !is_word(bytes[i - 1])) => {
                i = skip_dollar_quoted(bytes, i).unwrap_or(i + 1);
            }
            b'@' => {
                // `@@name`: system variable (MySQL/MSSQL) or operator
                // (Postgres `@@`). Never a parameter; leave intact.
                if i + 1 < n && bytes[i + 1] == b'@' {
                    i += 2;
                    while i < n && is_word(bytes[i]) {
                        i += 1;
                    }
                    continue;
                }
                // `foo@bar` glued to a word is not a placeholder either.
                if i > 0 && is_word(bytes[i - 1]) {
                    i += 1;
                    continue;
                }
                let name_start = i + 1;
                let mut j = name_start;
                while j < n && is_word(bytes[j]) {
                    j += 1;
                }
                if j == name_start {
                    i += 1;
                    continue;
                }
                let name = &sql[name_start..j];
                // tiberius positional params (`@P1`) pass through untouched.
                if dialect == Dialect::Mssql && is_mssql_positional(name) {
                    i = j;
                    continue;
                }
                out.push_str(&sql[copied..i]);
                index += 1;
                out.push_str(&dialect.placeholder(index));
                values.push(params.get(name).cloned().unwrap_or(Value::Null));
                copied = j;
                i = j;
            }
            _ => i += 1,
        }
    }
    out.push_str(&sql[copied..]);
    (out, values)
}

fn is_mssql_positional(name: &str) -> bool {
    name.starts_with('P') && name[1..].parse::<u32>().is_ok()
}

/// Skips a quoted region opened just before `start` and closed by `quote`.
/// A doubled quote (`''`, `""`, ``` `` ```) is an escape in every dialect;
/// `backslash` additionally makes `\x` skip the next byte. Returns the index
/// right after the closing quote, or `len` if unterminated.
fn skip_quoted(bytes: &[u8], start: usize, quote: u8, backslash: bool) -> usize {
    let n = bytes.len();
    let mut i = start;
    while i < n {
        let b = bytes[i];
        if backslash && b == b'\\' {
            i += 2;
            continue;
        }
        if b == quote {
            if i + 1 < n && bytes[i + 1] == quote {
                i += 2;
                continue;
            }
            return i + 1;
        }
        i += 1;
    }
    n
}

/// `[identifier]`; MSSQL escapes `]` as `]]`.
fn skip_bracket(bytes: &[u8], start: usize, double_escape: bool) -> usize {
    let n = bytes.len();
    let mut i = start;
    while i < n {
        if bytes[i] == b']' {
            if double_escape && i + 1 < n && bytes[i + 1] == b']' {
                i += 2;
                continue;
            }
            return i + 1;
        }
        i += 1;
    }
    n
}

/// Skips to the end of the line (the newline itself is left to the caller).
fn skip_line(bytes: &[u8], start: usize) -> usize {
    let mut i = start;
    while i < bytes.len() && bytes[i] != b'\n' {
        i += 1;
    }
    i
}

/// `/* ... */`, nested when `nested` (Postgres). Unterminated: to the end.
fn skip_block_comment(bytes: &[u8], start: usize, nested: bool) -> usize {
    let n = bytes.len();
    let mut depth = 1usize;
    let mut i = start;
    while i + 1 < n {
        if nested && bytes[i] == b'/' && bytes[i + 1] == b'*' {
            depth += 1;
            i += 2;
        } else if bytes[i] == b'*' && bytes[i + 1] == b'/' {
            depth -= 1;
            i += 2;
            if depth == 0 {
                return i;
            }
        } else {
            i += 1;
        }
    }
    n
}

/// `$$...$$` or `$tag$...$tag$` (tag: unquoted-identifier rules, no `$`).
/// `start` points at the opening `$`. Returns `None` when this `$` does not
/// open a dollar quote (e.g. a `$1` positional). Unterminated: to the end.
fn skip_dollar_quoted(bytes: &[u8], start: usize) -> Option<usize> {
    let n = bytes.len();
    let mut k = start + 1;
    if k < n && (bytes[k].is_ascii_alphabetic() || bytes[k] == b'_') {
        while k < n && is_word(bytes[k]) {
            k += 1;
        }
    }
    if k >= n || bytes[k] != b'$' {
        return None;
    }
    let tag = &bytes[start..=k];
    let body_start = k + 1;
    let end = bytes[body_start..]
        .windows(tag.len())
        .position(|w| w == tag)
        .map(|p| body_start + p + tag.len())
        .unwrap_or(n);
    Some(end)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const ALL: [Dialect; 4] = [Dialect::Sqlite, Dialect::Postgres, Dialect::Mysql, Dialect::Mssql];

    fn params() -> Map<String, Value> {
        let mut m = Map::new();
        m.insert("p".into(), json!("v"));
        m.insert("nome".into(), json!("João"));
        m.insert("idade".into(), json!(30));
        m
    }

    fn ph(d: Dialect, n: u32) -> String {
        d.placeholder(n)
    }

    /// The exact production incident: an e-mail inside a literal was rewritten.
    #[test]
    fn email_in_literal_is_untouched() {
        for d in ALL {
            let sql = "INSERT INTO users (email) VALUES ('thalya@gmail.com')";
            let (out, values) = rewrite(sql, &params(), d);
            assert_eq!(out, sql, "{:?}", d);
            assert!(values.is_empty(), "{:?}", d);

            let sql = "SELECT * FROM users WHERE email LIKE '%@gmail.com'";
            let (out, values) = rewrite(sql, &params(), d);
            assert_eq!(out, sql, "{:?}", d);
            assert!(values.is_empty(), "{:?}", d);
        }
    }

    #[test]
    fn many_emails_in_one_insert() {
        let sql = "INSERT INTO u (e) VALUES ('a@x.com'), ('b@y.org'), ('c@z.io')";
        for d in ALL {
            assert_eq!(rewrite(sql, &params(), d).0, sql, "{:?}", d);
        }
    }

    #[test]
    fn escaped_single_quote_then_param_text() {
        // `''` is an escaped quote: the literal is `it's @x` and stays intact.
        let sql = "SELECT 'it''s @x' AS s";
        for d in ALL {
            assert_eq!(rewrite(sql, &params(), d).0, sql, "{:?}", d);
        }
        // ...and after the literal really closes, `@p` is a parameter again.
        let sql = "SELECT 'it''s' , @p";
        for d in ALL {
            let (out, values) = rewrite(sql, &params(), d);
            assert_eq!(out, format!("SELECT 'it''s' , {}", ph(d, 1)), "{:?}", d);
            assert_eq!(values, vec![json!("v")]);
        }
    }

    #[test]
    fn params_in_comments_are_untouched() {
        for d in ALL {
            let sql = "SELECT 1 -- @x here\n, @p";
            let (out, values) = rewrite(sql, &params(), d);
            assert_eq!(out, format!("SELECT 1 -- @x here\n, {}", ph(d, 1)), "{:?}", d);
            assert_eq!(values, vec![json!("v")]);

            let sql = "SELECT /* @x */ @p /* trailing @y */";
            let (out, values) = rewrite(sql, &params(), d);
            assert_eq!(out, format!("SELECT /* @x */ {} /* trailing @y */", ph(d, 1)), "{:?}", d);
            assert_eq!(values, vec![json!("v")]);
        }
    }

    #[test]
    fn double_quoted_identifier_is_untouched() {
        for d in ALL {
            let sql = r#"SELECT "@col", "a""@b" FROM t WHERE x = @p"#;
            let (out, values) = rewrite(sql, &params(), d);
            assert_eq!(out, format!(r#"SELECT "@col", "a""@b" FROM t WHERE x = {}"#, ph(d, 1)), "{:?}", d);
            assert_eq!(values, vec![json!("v")]);
        }
    }

    #[test]
    fn mixed_param_outside_and_literal_inside() {
        for d in ALL {
            let sql = "UPDATE u SET email = 'x@y.com', name = @nome WHERE id = @idade";
            let (out, values) = rewrite(sql, &params(), d);
            assert_eq!(
                out,
                format!("UPDATE u SET email = 'x@y.com', name = {} WHERE id = {}", ph(d, 1), ph(d, 2)),
                "{:?}",
                d
            );
            assert_eq!(values, vec![json!("João"), json!(30)]);
        }
    }

    #[test]
    fn unknown_param_binds_null_and_repeats_rebind() {
        let (out, values) = rewrite("SELECT @p, @zz, @p", &params(), Dialect::Postgres);
        assert_eq!(out, "SELECT $1, $2, $3");
        assert_eq!(values, vec![json!("v"), Value::Null, json!("v")]);
    }

    #[test]
    fn multibyte_text_is_copied_verbatim() {
        for d in ALL {
            for sql in ["select 'coração' as x", "東京", "select '😀' where a = @p and 'ã' = 'ã'"] {
                let (out, _) = rewrite(sql, &params(), d);
                assert_eq!(out, sql.replace("@p", &ph(d, 1)), "{:?}", d);
            }
        }
    }

    // ---- Postgres ----

    #[test]
    fn postgres_dollar_quoting() {
        let p = params();
        let sql = "CREATE FUNCTION f() RETURNS text AS $$ SELECT '@x' || @y $$ LANGUAGE sql";
        assert_eq!(rewrite(sql, &p, Dialect::Postgres).0, sql);

        let sql = "DO $fn$ BEGIN PERFORM @x; END $fn$; SELECT @p";
        let (out, values) = rewrite(sql, &p, Dialect::Postgres);
        assert_eq!(out, "DO $fn$ BEGIN PERFORM @x; END $fn$; SELECT $1");
        assert_eq!(values, vec![json!("v")]);

        // `$1` and `foo$bar` are not dollar quotes.
        let (out, _) = rewrite("SELECT foo$bar, $1, @p", &p, Dialect::Postgres);
        assert_eq!(out, "SELECT foo$bar, $1, $1");
    }

    #[test]
    fn postgres_escape_string_and_nested_comment() {
        let p = params();
        let sql = r"SELECT E'it\'s @x', @p";
        let (out, values) = rewrite(sql, &p, Dialect::Postgres);
        assert_eq!(out, r"SELECT E'it\'s @x', $1");
        assert_eq!(values, vec![json!("v")]);

        // Standard string: backslash is literal, the quote closes the string.
        let (out, _) = rewrite(r"SELECT 'C:\', @p", &p, Dialect::Postgres);
        assert_eq!(out, r"SELECT 'C:\', $1");

        let (out, _) = rewrite("SELECT /* a /* @x */ @y */ @p", &p, Dialect::Postgres);
        assert_eq!(out, "SELECT /* a /* @x */ @y */ $1");

        // `@@` operator stays.
        let (out, _) = rewrite("SELECT v @@ q, @p", &p, Dialect::Postgres);
        assert_eq!(out, "SELECT v @@ q, $1");
    }

    // ---- MySQL ----

    #[test]
    fn mysql_backslash_hash_backtick_and_sysvars() {
        let p = params();
        let (out, values) = rewrite(r"SELECT 'it\'s @x', `@col`, @p # @z", &p, Dialect::Mysql);
        assert_eq!(out, r"SELECT 'it\'s @x', `@col`, ? # @z");
        assert_eq!(values, vec![json!("v")]);

        // Double quotes are strings in MySQL, with backslash escapes.
        let (out, _) = rewrite(r#"SELECT "a\"@b", @p"#, &p, Dialect::Mysql);
        assert_eq!(out, r#"SELECT "a\"@b", ?"#);

        // `@@version` is a system variable; `1--1` is arithmetic.
        let (out, values) = rewrite("SELECT @@version, @@global.x, 1--1, @p", &p, Dialect::Mysql);
        assert_eq!(out, "SELECT @@version, @@global.x, 1--1, ?");
        assert_eq!(values, vec![json!("v")]);

        // `-- ` with a space is a comment.
        let (out, _) = rewrite("SELECT 1 -- @x\n, @p", &p, Dialect::Mysql);
        assert_eq!(out, "SELECT 1 -- @x\n, ?");
    }

    // ---- MSSQL ----

    #[test]
    fn mssql_brackets_nstrings_and_positional() {
        let p = params();
        let (out, values) = rewrite(
            "SELECT [@col], [a]]@b], N'x@y.com', @p FROM t WHERE q = @P1 AND r = @nome",
            &p,
            Dialect::Mssql,
        );
        assert_eq!(out, "SELECT [@col], [a]]@b], N'x@y.com', @P1 FROM t WHERE q = @P1 AND r = @P2");
        assert_eq!(values, vec![json!("v"), json!("João")]);

        // `@@ROWCOUNT` stays; `DECLARE @x` keeps being rewritten (unchanged behaviour).
        let (out, _) = rewrite("SELECT @@ROWCOUNT, @p", &p, Dialect::Mssql);
        assert_eq!(out, "SELECT @@ROWCOUNT, @P1");
    }

    // ---- SQLite ----

    #[test]
    fn sqlite_brackets_and_backticks() {
        let p = params();
        let (out, values) = rewrite("SELECT [@a], `@b`, '@c', @p", &p, Dialect::Sqlite);
        assert_eq!(out, "SELECT [@a], `@b`, '@c', ?");
        assert_eq!(values, vec![json!("v")]);
    }

    #[test]
    fn unterminated_quote_never_panics() {
        for d in ALL {
            for sql in ["SELECT 'abc", "SELECT \"abc", "SELECT /* abc", "SELECT $$ abc", "SELECT [abc", "x\\"] {
                let _ = rewrite(sql, &params(), d);
            }
        }
    }
}
