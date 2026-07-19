# Handoff — bug de tipos no Anaki: TIMESTAMPTZ (pg) e DECIMAL (mysql) voltam NULL

> **STATUS 2026-07-18 (mais tarde): RESOLVIDO.** Reteste via Cockpit retornou
> `created_at` = `"2026-07-19T01:42:34.280557+00:00"` (TEXT) no pg e
> `price` = `"1299.00"` (TEXT) no mysql — consistente com o commit
> `b43acec` "Decode temporal, decimal and uuid column types natively"
> (o Cockpit passou a carregar as dylibs atualizadas). O texto abaixo fica
> como registro histórico.

**Data:** 2026-07-18 · **Origem:** teste do Cockpit DB usando o ambiente `dbtest/`

## Sintoma

Consultas via camada nativa do Anaki retornam `null` (e `type: ""` no metadata
de coluna) para:

- **Postgres:** colunas `timestamptz` (ex.: `created_at`)
- **MySQL:** colunas `decimal` (ex.: `price DECIMAL(10,2)`)

Os demais tipos (TEXT, BOOL, INTEGER) vêm corretos.

## Reprodução

1. `cd dbtest && docker compose up -d` (pg em 5434, mysql em 3307 — seeds automáticos)
2. `cockpit db run dbtest/queries/postgres.dbq` → `created_at` = `null`
3. `cockpit db run dbtest/queries/mysql.dbq` → `price` = `null`

Saída real observada (pg):

```json
{"columns":[{"name":"created_at","type":""},...],"rows":[[null,"Alice",true,"Hello Postgres"],...]}
```

## Causa raiz

O sqlx está sem as features de tipos temporais/decimais:

- `rust/Cargo.toml:26` — `sqlx = { version = "0.8", features = ["runtime-tokio"], ... }`
  (não habilita `chrono`/`time` nem `rust_decimal`/`bigdecimal`)
- `rust/src/postgres.rs:181-185` — para `TIMESTAMP|TIMESTAMPTZ|DATE|TIME|TIMETZ`
  faz `row.try_get::<Option<String>>()`. O sqlx **não** decodifica timestamptz
  como `String` (não há impl `Decode` de texto para esses OIDs sem feature de
  tempo), então o `try_get` erra e o `_ =>` engole o erro virando `Null`.
- `rust/src/mysql.rs:129-139` — mesmo padrão para `DECIMAL|NUMERIC`: tenta
  `f64`, depois `String`; ambos falham sem a feature decimal e caem em `Null`.

O padrão `_ => Null` silencia o erro de decode — por isso o bug passa como
"valor nulo" em vez de erro visível.

## Correção sugerida

1. Habilitar features no sqlx: `"chrono"` (ou `"time"`) e `"rust_decimal"`
   (ou `"bigdecimal"`).
2. Decodificar como tipo nativo e serializar:
   - `TIMESTAMPTZ` → `chrono::DateTime<Utc>` → RFC3339 string
   - `DECIMAL` → `rust_decimal::Decimal` → string (preserva precisão; não usar f64)
3. Opcional, mas recomendado: nos braços de fallback, logar/propagar o erro de
   decode em vez de retornar `Null` silencioso.
4. Verificar os mesmos caminhos em `sqlite.rs` e `mssql.rs` (tiberius tem seu
   próprio mapeamento, mas vale conferir datas/decimais).

## Teste de regressão

Depois do fix, as duas queries acima devem retornar `created_at` como string
RFC3339 e `price` como `"199.90"`-like, com `type` preenchido no metadata.
Casos de seed já existem em `dbtest/init/*/init.sql`.
