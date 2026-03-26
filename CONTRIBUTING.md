# Contributing to Anaki

Thanks for your interest in contributing! This guide covers the project structure, how to build native libraries, run tests, and add new drivers.

## Prerequisites

- **Dart SDK** ≥ 3.10
- **Rust** ≥ 1.83 (for compiling native connectors)
- **Docker** (for running database integration tests)

## Project Structure

```
anakiORM/
├── rust/                      # Single Rust crate — all drivers via feature flags
│   ├── Cargo.toml             # [features] sqlite, postgres, mysql, mssql, oracle
│   └── src/
│       ├── lib.rs             # FFI exports + generic connector dispatch
│       ├── connector.rs       # DatabaseConnector trait (shared)
│       ├── error.rs           # AnakiError (shared)
│       ├── types.rs           # FfiResponse, QueryResult, etc. (shared)
│       ├── sqlite.rs          # SQLite impl (cfg feature = "sqlite")
│       ├── postgres.rs        # PostgreSQL impl (cfg feature = "postgres")
│       ├── mysql.rs           # MySQL impl (cfg feature = "mysql")
│       └── mssql.rs           # SQL Server impl (cfg feature = "mssql")
├── packages/
│   ├── anaki_orm/             # Core Dart package (AnakiDb, QueryBuilder, Migrator)
│   ├── anaki_sqlite/          # SQLite driver (FFI bindings + native_libs/)
│   ├── anaki_postgres/        # PostgreSQL driver
│   ├── anaki_mysql/           # MySQL driver
│   ├── anaki_mssql/           # SQL Server driver
│   └── anaki_oracle/          # Oracle driver (deferred — requires OCI)
├── example/
│   └── shelf_sqlite_example/  # Example REST API with Shelf + SQLite
├── scripts/
│   └── build_native.sh        # Cross-compilation script
└── docs/
    └── docker-aot.md          # Docker AOT deployment guide
```

## Architecture

```
┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Dart App   │────▶│   anaki_orm     │────▶│  AnakiDriver │
│ (Shelf/Vaden)│     │  (AnakiDb API)  │     │  (interface)  │
└──────────────┘     └─────────────────┘     └──────┬───────┘
                                                     │ implements
                                               ┌─────┴─────┐
                                               │            │
                                    ┌──────────┴──┐  ┌──────┴────────┐
                                    │ SqliteDriver │  │ PostgresDriver │ ...
                                    │  (FFI→Rust)  │  │   (FFI→Rust)   │
                                    └──────────────┘  └────────────────┘
                                           │                  │
                                    ┌──────┴──────────────────┴──────┐
                                    │    Single Rust crate (rust/)    │
                                    │  compiled with --features flag  │
                                    │  sqlite │ postgres │ mysql │ …  │
                                    └─────────────────────────────────┘
```

**Key design decisions:**

- **One Rust crate** with feature flags, not one crate per driver
- **FFI protocol**: Rust returns JSON string → Dart decodes to `Map<String, dynamic>`
- **One Dart package per driver** — each contains FFI bindings and pre-built native libraries
- **`anaki_orm`** is pure Dart — no native dependencies, no FFI

## Building Native Libraries

All drivers share the Rust crate in `rust/`. The build script compiles with the correct feature flag and copies the output to the right package.

```bash
# Build a single driver (local platform only)
./scripts/build_native.sh sqlite --local

# Build a single driver (all platforms)
./scripts/build_native.sh sqlite

# Build all drivers
./scripts/build_native.sh all
```

Under the hood:

```bash
cargo build --release --features sqlite   # → libanaki_sqlite-darwin-arm64.dylib
cargo build --release --features postgres # → libanaki_postgres-linux-x64.so
```

The output goes to `packages/anaki_<driver>/native_libs/`.

## Running Tests

### Core package (no native deps)

```bash
cd packages/anaki_orm
dart test
```

### Driver integration tests (requires native lib)

```bash
# Build the native lib first
./scripts/build_native.sh sqlite --local

# Then run tests
cd packages/anaki_sqlite
dart test
```

### Database tests requiring Docker

For PostgreSQL, MySQL, and MSSQL, start the containers first:

```bash
docker compose up -d

# Then run tests
cd packages/anaki_postgres
dart test

cd packages/anaki_mssql
dart test
```

## Adding a New Driver

1. **Rust side** — Add a new module in `rust/src/` (e.g., `newdb.rs`):
   - Implement the `DatabaseConnector` trait
   - Add a feature flag in `Cargo.toml`
   - Register it in `lib.rs` under `create_connector()` with `#[cfg(feature = "newdb")]`

2. **Dart side** — Create `packages/anaki_newdb/`:
   - `lib/src/newdb_driver.dart` — implements `AnakiDriver`
   - `lib/src/bindings.dart` — FFI bindings using `@Native`
   - `lib/anaki_newdb.dart` — library exports
   - `pubspec.yaml` — depends on `anaki_orm`
   - `native_libs/` — will hold compiled binaries

3. **Build script** — Add the driver name to `scripts/build_native.sh`

4. **Tests** — Add integration tests in `test/`

### Driver checklist

- [ ] Implements all `AnakiDriver` methods
- [ ] Sets correct `SqlDialect` (`.generic` or `.mssql`)
- [ ] Named parameters use `@name` syntax
- [ ] FFI bindings load correct platform-specific library
- [ ] Integration tests cover: connect, CRUD, scalar, batch, pagination, transactions
- [ ] Native libraries built for: linux-x64, darwin-arm64, darwin-x64, windows-x64

## SQL Dialect

Drivers that need dialect-specific SQL generation override the `dialect` getter:

```dart
@override
SqlDialect get dialect => SqlDialect.mssql;
```

Currently affects:
- **Pagination**: `LIMIT/OFFSET` (generic) vs `OFFSET/FETCH` (MSSQL)
- **Migrator DDL**: `AUTOINCREMENT` (generic) vs `IDENTITY` (MSSQL)
- **COUNT subqueries**: ORDER BY stripping for MSSQL

## Docker AOT Deployment

See [docs/docker-aot.md](docs/docker-aot.md) for production deployment with `dart compile exe`.

## Code Style

- Follow Dart conventions (`dart format`, `dart analyze`)
- Keep `AnakiDb` SQL-first — no ORM-like abstractions in the core class
- The `AnakiQueryBuilder` is opt-in and standalone — it doesn't modify `AnakiDb`
- Tests: unit tests in `anaki_orm/test/`, integration tests in each driver package

## License

MIT
