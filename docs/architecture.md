# Anaki ORM — Architecture

> Technical document describing the system architecture

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Dart Application                                │
│                           (Shelf, Vaden, CLI)                               │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              anaki_orm                                       │
│  ┌─────────────┐  ┌─────────────────┐  ┌──────────┐  ┌─────────┐           │
│  │   AnakiDb   │  │ AnakiQueryBuilder│  │ Migrator │  │ Seeder  │           │
│  └──────┬──────┘  └────────┬────────┘  └────┬─────┘  └────┬────┘           │
│         │                  │                │             │                 │
│         └──────────────────┴────────────────┴─────────────┘                 │
│                                      │                                       │
│                              AnakiDriver (interface)                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              ▼                       ▼                       ▼
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│   anaki_sqlite      │  │   anaki_postgres    │  │   anaki_mysql       │
│   SqliteDriver      │  │   PostgresDriver    │  │   MysqlDriver       │
│   (FFI bindings)    │  │   (FFI bindings)    │  │   (FFI bindings)    │
└──────────┬──────────┘  └──────────┬──────────┘  └──────────┬──────────┘
           │                        │                        │
           └────────────────────────┼────────────────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Rust Native Library                                  │
│                         (anaki_native crate)                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    DatabaseConnector trait                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│         │              │              │              │                      │
│  ┌──────┴─────┐ ┌──────┴─────┐ ┌──────┴─────┐ ┌──────┴─────┐              │
│  │  sqlite.rs │ │ postgres.rs│ │  mysql.rs  │ │  mssql.rs  │              │
│  │   (sqlx)   │ │   (sqlx)   │ │   (sqlx)   │ │ (tiberius) │              │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘              │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Database                                        │
│         SQLite │ PostgreSQL │ MySQL │ SQL Server │ Oracle                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Components

### 2.1 Dart Layer — `anaki_orm`

Pure Dart package (no native dependencies) containing:

| Component | Responsibility |
|-----------|----------------|
| `AnakiDb` | Main API for database operations |
| `AnakiDriver` | Abstract interface that drivers implement |
| `AnakiQueryBuilder` | Optional fluent query builder |
| `Migrator` | SQL migrations executor |
| `Seeder` | SQL seeds executor |
| `RowAdapter` | Generic adapter for row ↔ object mapping |
| `SqlDialect` | SQL dialects enum |
| `Exceptions` | Typed exceptions hierarchy |

### 2.2 Dart Layer — Driver Packages

Each driver is a separate package:

| Package | Driver Class | Dialect | Rust Feature |
|---------|--------------|---------|--------------|
| `anaki_sqlite` | `SqliteDriver` | `sqlite` | `sqlite` |
| `anaki_postgres` | `PostgresDriver` | `generic` | `postgres` |
| `anaki_mysql` | `MysqlDriver` | `generic` | `mysql` |
| `anaki_mssql` | `MssqlDriver` | `mssql` | `mssql` |
| `anaki_oracle` | `OracleDriver` | — | `oracle` (deferred) |

**Structure of each driver package:**

```
anaki_<driver>/
├── lib/
│   ├── anaki_<driver>.dart      # Library exports
│   └── src/
│       ├── <driver>_driver.dart # AnakiDriver implementation
│       └── bindings.dart        # FFI bindings (@Native)
├── native_libs/                 # Pre-built binaries
│   ├── libanaki_<driver>-darwin-arm64.dylib
│   ├── libanaki_<driver>-darwin-x64.dylib
│   ├── libanaki_<driver>-linux-x64.so
│   └── anaki_<driver>-windows-x64.dll
├── test/
└── pubspec.yaml
```

### 2.3 Rust Layer — `anaki_native`

Single crate with feature flags for each driver:

```toml
[features]
sqlite = ["sqlx/sqlite"]
postgres = ["sqlx/postgres"]
mysql = ["sqlx/mysql"]
mssql = ["dep:tiberius", "dep:tokio-util"]
oracle = ["dep:sibyl"]
```

**Modules:**

| Module | Responsibility |
|--------|----------------|
| `lib.rs` | FFI exports, dispatch to correct connector |
| `connector.rs` | `DatabaseConnector` trait |
| `error.rs` | `AnakiError` and JSON conversion |
| `types.rs` | `FfiResponse`, `QueryResult`, etc. |
| `sqlite.rs` | SQLite implementation (sqlx) |
| `postgres.rs` | PostgreSQL implementation (sqlx) |
| `mysql.rs` | MySQL implementation (sqlx) |
| `mssql.rs` | SQL Server implementation (tiberius) |

---

## 3. FFI Protocol

### 3.1 Communication Format

All Dart ↔ Rust communication uses **JSON strings**:

```
Dart                              Rust
  │                                 │
  │  ──── config_json ────────────▶ │  open()
  │  ◀─── response_json ─────────── │
  │                                 │
  │  ──── sql, params_json ───────▶ │  query()
  │  ◀─── response_json ─────────── │
```

### 3.2 Response Structure

**Success:**
```json
{
  "ok": {
    "rows": [
      {"id": 1, "name": "Ana"},
      {"id": 2, "name": "Bob"}
    ]
  }
}
```

**Error:**
```json
{
  "error": {
    "code": "QUERY_ERROR",
    "message": "table users does not exist",
    "details": "..."
  }
}
```

### 3.3 Error Codes

| Code | Dart Exception |
|--------|--------------|
| `CONNECTION_ERROR` | `ConnectionException` |
| `QUERY_ERROR` | `QueryException` |
| `TRANSACTION_ERROR` | `TransactionException` |
| `UNKNOWN` | `AnakiException` |

### 3.4 Named Parameters

SQL uses `@param` syntax:

```dart
await db.query(
  'SELECT * FROM users WHERE id = @id AND active = @active',
  {'id': 1, 'active': true},
);
```

The Rust driver converts to the database's native syntax:
- SQLite/PostgreSQL: `$1, $2, ...`
- MySQL: `?, ?, ...`
- MSSQL: `@P1, @P2, ...`

---

## 4. Data Flow

### 4.1 Query with Mapping

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. App calls db.query('SELECT...', params, UserDTO.fromJson)                │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. AnakiDb validates connection, delegates to driver.rawQuery(sql, params)  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. Driver serializes params to JSON, calls FFI                              │
│    _bindings.query(sqlPtr, paramsPtr)                                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. Rust: parse params, convert @name to $N, execute query                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 5. Rust: serialize rows to JSON, return via FFI                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 6. Driver: parse JSON response, check errors, return List<Map>              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 7. AnakiDb: apply fromJson to each row, return List<UserDTO>                │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Transaction

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. App calls db.transaction((tx) async { ... })                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. AnakiDb calls driver.rawBeginTransaction()                               │
│    → Rust executes BEGIN TRANSACTION                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. App executes operations via tx (same AnakiDb)                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│ 4a. Success                   │   │ 4b. Exception                 │
│     driver.rawCommit()        │   │     driver.rawRollback()      │
│     → COMMIT                  │   │     → ROLLBACK                │
└───────────────────────────────┘   │     rethrow                   │
                                    └───────────────────────────────┘
```

---

## 5. Design Decisions

### 5.1 Why Rust?

| Alternative | Problem |
|-------------|----------|
| Pure Dart | Slow protocol parsing, no native connection pooling |
| C/C++ | Manual memory management, less safe |
| Go | Heavy runtime, more complex FFI |

**Rust offers:**
- Zero runtime overhead
- Simple native FFI
- Mature DB ecosystem (sqlx, tiberius)
- Guaranteed memory safety

### 5.2 Why a Single Crate?

| Alternative | Problem |
|-------------|----------|
| One crate per driver | Code duplication, more complex build |

**Single crate with features:**
- Shared code (trait, error, types)
- Simple build script: `--features sqlite`
- Smaller binaries (only compiles what's needed)

### 5.3 Why JSON in FFI?

| Alternative | Problem |
|-------------|----------|
| C Structs | Marshalling complexity, limited types |
| Protobuf | Additional dependency, schema overhead |
| MessagePack | Less readable for debugging |

**JSON offers:**
- Trivial serialization on both sides
- Easy debugging (readable strings)
- Native support for Dart types (Map, List)
- Acceptable overhead for DB operations

### 5.4 Why SQL-first (Dapper-style)?

| Alternative | Problem |
|-------------|----------|
| Full ORM (Hibernate-style) | Heavy abstraction, inefficient queries, learning curve |
| Query builder only | Loses flexibility for complex SQL |

**SQL-first offers:**
- Full control over queries
- No performance surprises
- Compatible with existing SQL
- Query builder as opt-in

---

## 6. Directory Structure

```
anakiORM/
├── rust/                          # Single Rust crate
│   ├── Cargo.toml                 # Features: sqlite, postgres, mysql, mssql
│   └── src/
│       ├── lib.rs                 # FFI exports
│       ├── connector.rs           # DatabaseConnector trait
│       ├── error.rs               # AnakiError
│       ├── types.rs               # FfiResponse, QueryResult
│       ├── sqlite.rs              # SQLite (sqlx)
│       ├── postgres.rs            # PostgreSQL (sqlx)
│       ├── mysql.rs               # MySQL (sqlx)
│       └── mssql.rs               # SQL Server (tiberius)
│
├── packages/
│   ├── anaki_orm/                 # Core Dart (pure, no FFI)
│   │   └── lib/src/
│   │       ├── db.dart            # AnakiDb
│   │       ├── driver.dart        # AnakiDriver interface, SqlDialect
│   │       ├── exceptions.dart    # Exceptions hierarchy
│   │       ├── migrator.dart      # Migrator
│   │       ├── seeder.dart        # Seeder
│   │       ├── paged_result.dart  # PagedResult<T>
│   │       └── query_builder/     # Fluent query builder
│   │
│   ├── anaki_sqlite/              # Driver SQLite
│   ├── anaki_postgres/            # Driver PostgreSQL
│   ├── anaki_mysql/               # Driver MySQL
│   ├── anaki_mssql/               # Driver SQL Server
│   └── anaki_oracle/              # Oracle driver (deferred)
│
├── example/                       # Usage examples
├── scripts/
│   └── build_native.sh            # Cross-platform build script
└── docs/                          # Documentation
```

---

## 7. References

- [Specification (SDD)](./spec.md)
- [API Reference](./api.md)
- [Drivers Guide](./drivers.md)
- [Docker AOT Deployment](./docker-aot.md)
