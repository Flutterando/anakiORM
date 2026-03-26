import 'driver.dart';
import 'exceptions.dart';
import 'paged_result.dart';

/// Main entry point for AnakiORM database operations.
///
/// Wraps an [AnakiDriver] and provides a clean, Dapper-style API
/// for executing SQL queries and commands.
///
/// Example:
/// ```dart
/// final db = AnakiDb(SqliteDriver('path/to/db.sqlite'));
/// await db.open();
///
/// final users = await db.query(
///   'SELECT * FROM users WHERE active = @active',
///   {'active': true},
///   map: (row) => UserDTO.fromJson(row),
/// );
///
/// await db.close();
/// ```
class AnakiDb {
  final AnakiDriver _driver;
  bool _isOpen = false;

  AnakiDb(this._driver);

  /// Whether the connection is currently open.
  bool get isOpen => _isOpen;

  /// The SQL dialect of the underlying driver.
  SqlDialect get dialect => _driver.dialect;

  /// Opens the database connection.
  Future<void> open() async {
    await _driver.rawOpen();
    _isOpen = true;
  }

  /// Closes the database connection.
  Future<void> close() async {
    await _driver.rawClose();
    _isOpen = false;
  }

  /// Checks if the connection is alive.
  Future<bool> ping() async {
    _ensureOpen();
    return _driver.rawPing();
  }

  /// Executes a SQL query and returns raw rows as maps.
  ///
  /// If [map] is provided, each row is transformed using it.
  ///
  /// ```dart
  /// // Raw maps
  /// final rows = await db.query('SELECT * FROM users');
  ///
  /// // Mapped to DTOs
  /// final users = await db.query(
  ///   'SELECT * FROM users',
  ///   null,
  ///   map: UserDTO.fromJson,
  /// );
  /// ```
  Future<List<T>> query<T>(
    String sql, [
    Map<String, dynamic>? params,
    T Function(Map<String, dynamic>)? map,
  ]) async {
    _ensureOpen();
    final rows = await _driver.rawQuery(sql, params);
    if (map != null) {
      return rows.map(map).toList();
    }
    return rows as List<T>;
  }

  /// Executes a SQL query and returns the first row, or `null` if empty.
  ///
  /// ```dart
  /// final user = await db.queryFirst(
  ///   'SELECT * FROM users WHERE id = @id',
  ///   {'id': 1},
  ///   UserDTO.fromJson,
  /// );
  /// ```
  Future<T?> queryFirst<T>(
    String sql, [
    Map<String, dynamic>? params,
    T Function(Map<String, dynamic>)? map,
  ]) async {
    _ensureOpen();
    final rows = await _driver.rawQuery(sql, params);
    if (rows.isEmpty) return null;
    if (map != null) return map(rows.first);
    return rows.first as T;
  }

  /// Executes a non-query SQL statement and returns the number of affected rows.
  ///
  /// ```dart
  /// final affected = await db.execute(
  ///   'INSERT INTO users (name, email) VALUES (@name, @email)',
  ///   {'name': 'Ana', 'email': 'ana@example.com'},
  /// );
  /// ```
  Future<int> execute(String sql, [Map<String, dynamic>? params]) async {
    _ensureOpen();
    return _driver.rawExecute(sql, params);
  }

  /// Executes a batch of statements with different parameter sets.
  ///
  /// Returns the total number of affected rows.
  ///
  /// ```dart
  /// final affected = await db.executeBatch(
  ///   'INSERT INTO users (name) VALUES (@name)',
  ///   [
  ///     {'name': 'Ana'},
  ///     {'name': 'Bob'},
  ///     {'name': 'Carol'},
  ///   ],
  /// );
  /// ```
  Future<int> executeBatch(
    String sql,
    List<Map<String, dynamic>> paramsList,
  ) async {
    _ensureOpen();
    return _driver.rawExecuteBatch(sql, paramsList);
  }

  /// Executes a query and returns a single scalar value.
  ///
  /// ```dart
  /// final count = await db.scalar<int>('SELECT COUNT(*) FROM users');
  /// ```
  Future<T?> scalar<T>(String sql, [Map<String, dynamic>? params]) async {
    _ensureOpen();
    final rows = await _driver.rawQuery(sql, params);
    if (rows.isEmpty) return null;
    final firstRow = rows.first;
    if (firstRow.isEmpty) return null;
    final value = firstRow.values.first;
    if (value == null) return null;
    return value as T;
  }

  /// Executes a query with pagination support.
  ///
  /// The method appends `LIMIT` and `OFFSET` to your SQL.
  /// It also runs a `COUNT(*)` query to get the total.
  ///
  /// ```dart
  /// final page = await db.queryPaged(
  ///   'SELECT * FROM users WHERE active = @active',
  ///   {'active': true},
  ///   page: 2,
  ///   pageSize: 20,
  ///   map: UserDTO.fromJson,
  /// );
  /// ```
  Future<PagedResult<T>> queryPaged<T>(
    String sql, {
    Map<String, dynamic>? params,
    required int page,
    required int pageSize,
    T Function(Map<String, dynamic>)? map,
  }) async {
    _ensureOpen();

    // Get total count
    // For MSSQL, ORDER BY in subqueries requires TOP/OFFSET, so strip it for counting.
    final countInnerSql = _driver.dialect == SqlDialect.mssql
        ? _stripOrderBy(sql)
        : sql;
    final countSql =
        'SELECT COUNT(*) as _anaki_count FROM ($countInnerSql) _anaki_sub';
    final countRows = await _driver.rawQuery(countSql, params);
    final rawCount = countRows.isNotEmpty ? countRows.first['_anaki_count'] : 0;
    final total = (rawCount is int) ? rawCount : int.tryParse('$rawCount') ?? 0;

    // Get page data
    final offset = (page - 1) * pageSize;
    final String pagedSql;
    if (_driver.dialect == SqlDialect.mssql) {
      // T-SQL: requires ORDER BY before OFFSET/FETCH
      pagedSql = '$sql OFFSET $offset ROWS FETCH NEXT $pageSize ROWS ONLY';
    } else {
      pagedSql = '$sql LIMIT $pageSize OFFSET $offset';
    }
    final rows = await _driver.rawQuery(pagedSql, params);

    final data = map != null ? rows.map(map).toList() : rows as List<T>;

    return PagedResult<T>(
      data: data,
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }

  /// Executes operations within a transaction.
  ///
  /// If the callback completes successfully, the transaction is committed.
  /// If an exception is thrown, the transaction is rolled back and the
  /// exception is rethrown.
  ///
  /// ```dart
  /// await db.transaction((tx) async {
  ///   await tx.execute('UPDATE accounts SET balance = balance - 100 WHERE id = @id', {'id': 1});
  ///   await tx.execute('UPDATE accounts SET balance = balance + 100 WHERE id = @id', {'id': 2});
  /// });
  /// ```
  Future<void> transaction(Future<void> Function(AnakiDb tx) action) async {
    _ensureOpen();
    await _driver.rawBeginTransaction();
    try {
      await action(this);
      await _driver.rawCommit();
    } catch (e) {
      try {
        await _driver.rawRollback();
      } catch (rollbackError) {
        throw TransactionException(
          'Transaction rollback failed',
          details: 'Original error: $e\nRollback error: $rollbackError',
        );
      }
      rethrow;
    }
  }

  void _ensureOpen() {
    if (!_isOpen) {
      throw const NotConnectedException();
    }
  }

  /// Strips ORDER BY clause from SQL for use in COUNT subqueries (MSSQL).
  static String _stripOrderBy(String sql) {
    final regex = RegExp(r'\bORDER\s+BY\b.*$', caseSensitive: false);
    return sql.replaceAll(regex, '').trim();
  }
}
