# Anaki ORM — Drivers Guide

> Detailed documentation about database drivers

---

## 1. Overview

Each driver is a separate Dart package that implements the `AnakiDriver` interface and communicates with the database via FFI to a native Rust library.

| Package | Database | Dialect | Status |
|---------|----------|---------|--------|
| `anaki_sqlite` | SQLite | `sqlite` | ✅ Ready |
| `anaki_postgres` | PostgreSQL | `generic` | ✅ Ready |
| `anaki_mysql` | MySQL | `generic` | ✅ Ready |
| `anaki_mssql` | SQL Server | `mssql` | ✅ Ready |
| `anaki_oracle` | Oracle | — | 🔜 Deferred |

---

## 2. SQLite

### 2.1 Installation

```yaml
dependencies:
  anaki_orm: ^0.1.0
  anaki_sqlite: ^0.1.0
```

### 2.2 Usage

```dart
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_sqlite/anaki_sqlite.dart';

void main() async {
  // File database
  final db = AnakiDb(SqliteDriver('database.db'));
  
  // Or in-memory database
  final memDb = AnakiDb(SqliteDriver(':memory:'));
  
  await db.open();
  // ... operations
  await db.close();
}
```

### 2.3 Configuration

```dart
final driver = SqliteDriver(
  'database.db',
  poolConfig: PoolConfig(
    minConnections: 1,
    maxConnections: 10,
  ),
);
```

### 2.4 Features

| Feature | Value |
|---------|-------|
| Dialect | `SqlDialect.sqlite` |
| Auto-increment | `INTEGER PRIMARY KEY AUTOINCREMENT` |
| Pagination | `LIMIT/OFFSET` |
| Parameters | `@name` → `$1, $2, ...` |
| Rust crate | sqlx (feature `sqlite`) |

### 2.5 Use Cases

- Local development
- Integration tests
- Embedded applications
- Rapid prototyping

---

## 3. PostgreSQL

### 3.1 Installation

```yaml
dependencies:
  anaki_orm: ^0.1.0
  anaki_postgres: ^0.1.0
```

### 3.2 Usage

```dart
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_postgres/anaki_postgres.dart';

void main() async {
  final db = AnakiDb(PostgresDriver(
    host: 'localhost',
    port: 5432,
    database: 'myapp',
    username: 'postgres',
    password: 'secret',
  ));
  
  await db.open();
  // ... operations
  await db.close();
}
```

### 3.3 Configuration

```dart
final driver = PostgresDriver(
  host: 'localhost',
  port: 5432,
  database: 'myapp',
  username: 'postgres',
  password: 'secret',
  poolConfig: PoolConfig(
    minConnections: 2,
    maxConnections: 20,
  ),
  ssl: false, // or true for SSL connections
);
```

### 3.4 Features

| Feature | Value |
|---------|-------|
| Dialect | `SqlDialect.generic` |
| Auto-increment | `SERIAL` / `BIGSERIAL` |
| Pagination | `LIMIT/OFFSET` |
| Parameters | `@name` → `$1, $2, ...` |
| Rust crate | sqlx (feature `postgres`) |

### 3.5 Docker for Development

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: secret
      POSTGRES_DB: myapp
    ports:
      - "5432:5432"
```

```bash
docker compose up -d
```

---

## 4. MySQL

### 4.1 Installation

```yaml
dependencies:
  anaki_orm: ^0.1.0
  anaki_mysql: ^0.1.0
```

### 4.2 Usage

```dart
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_mysql/anaki_mysql.dart';

void main() async {
  final db = AnakiDb(MysqlDriver(
    host: 'localhost',
    port: 3306,
    database: 'myapp',
    username: 'root',
    password: 'secret',
  ));
  
  await db.open();
  // ... operations
  await db.close();
}
```

### 4.3 Configuration

```dart
final driver = MysqlDriver(
  host: 'localhost',
  port: 3306,
  database: 'myapp',
  username: 'root',
  password: 'secret',
  poolConfig: PoolConfig(
    minConnections: 2,
    maxConnections: 20,
  ),
);
```

### 4.4 Features

| Feature | Value |
|---------|-------|
| Dialect | `SqlDialect.generic` |
| Auto-increment | `AUTO_INCREMENT` |
| Pagination | `LIMIT/OFFSET` |
| Parameters | `@name` → `?, ?, ...` |
| Rust crate | sqlx (feature `mysql`) |

### 4.5 Docker for Development

```yaml
# docker-compose.yml
services:
  mysql:
    image: mysql:8
    environment:
      MYSQL_ROOT_PASSWORD: secret
      MYSQL_DATABASE: myapp
    ports:
      - "3306:3306"
```

---

## 5. SQL Server (MSSQL)

### 5.1 Installation

```yaml
dependencies:
  anaki_orm: ^0.1.0
  anaki_mssql: ^0.1.0
```

### 5.2 Usage

```dart
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_mssql/anaki_mssql.dart';

void main() async {
  final db = AnakiDb(MssqlDriver(
    host: 'localhost',
    port: 1433,
    database: 'myapp',
    username: 'sa',
    password: 'Anaki@Strong1',
  ));
  
  await db.open();
  // ... operations
  await db.close();
}
```

### 5.3 Configuration

```dart
final driver = MssqlDriver(
  host: 'localhost',
  port: 1433,
  database: 'myapp',
  username: 'sa',
  password: 'Anaki@Strong1',
  trustServerCertificate: true, // for development
);
```

### 5.4 Features

| Feature | Value |
|---------|-------|
| Dialect | `SqlDialect.mssql` |
| Auto-increment | `INT IDENTITY(1,1)` |
| Pagination | `OFFSET M ROWS FETCH NEXT N ROWS ONLY` |
| Parameters | `@name` → `@P1, @P2, ...` |
| Boolean | `BIT` (0/1) |
| Rust crate | tiberius 0.12 |

### 5.5 Important Differences

**Pagination requires ORDER BY:**
```dart
// ✅ Correct
final page = await db.queryPaged(
  'SELECT * FROM users ORDER BY id',
  page: 1,
  pageSize: 20,
);

// ❌ Error — MSSQL requires ORDER BY for OFFSET/FETCH
final page = await db.queryPaged(
  'SELECT * FROM users',
  page: 1,
  pageSize: 20,
);
```

**Database must be created manually:**
```sql
-- Execute in SQL Server before connecting
CREATE DATABASE myapp;
```

### 5.6 Docker for Development

```yaml
# docker-compose.yml
services:
  mssql:
    image: mcr.microsoft.com/mssql/server:2022-latest
    platform: linux/amd64  # Required for Mac ARM
    environment:
      ACCEPT_EULA: Y
      SA_PASSWORD: Anaki@Strong1
    ports:
      - "1433:1433"
```

**Note:** On ARM Macs, the container runs via Rosetta (x64 emulation).

---

## 6. Oracle (Deferred)

The Oracle driver is planned but deferred due to the complexity of Oracle Instant Client (OCI).

### 6.1 Status

- Rust: Structure prepared with `sibyl` crate
- Dart: `anaki_oracle` package created (stub)
- Blocker: Requires OCI installed on the system

### 6.2 Future Requirements

- Oracle Instant Client installed
- Environment variables configured
- Oracle licensing

---

## 7. AnakiDriver Interface

All drivers implement this interface:

```dart
abstract class AnakiDriver {
  SqlDialect get dialect => SqlDialect.generic;
  
  Future<void> rawOpen();
  Future<void> rawClose();
  Future<List<Map<String, dynamic>>> rawQuery(String sql, Map<String, dynamic>? params);
  Future<int> rawExecute(String sql, Map<String, dynamic>? params);
  Future<int> rawExecuteBatch(String sql, List<Map<String, dynamic>> paramsList);
  Future<void> rawBeginTransaction();
  Future<void> rawCommit();
  Future<void> rawRollback();
  Future<bool> rawPing();
}
```

---

## 8. Creating a New Driver

### 8.1 Checklist

- [ ] Implement `DatabaseConnector` trait in Rust
- [ ] Add feature flag in `Cargo.toml`
- [ ] Register in `lib.rs` with `#[cfg(feature = "...")]`
- [ ] Create Dart package `anaki_<driver>/`
- [ ] Implement `AnakiDriver` in Dart
- [ ] Create FFI bindings
- [ ] Add to build script
- [ ] Write integration tests
- [ ] Compile binaries for all platforms

### 8.2 Rust Structure

```rust
// rust/src/newdb.rs
use crate::connector::DatabaseConnector;
use crate::error::AnakiError;

pub struct NewDbConnector {
    // ...
}

#[async_trait::async_trait]
impl DatabaseConnector for NewDbConnector {
    async fn open(config_json: &str) -> Result<Self, AnakiError> { ... }
    async fn close(&self) -> Result<(), AnakiError> { ... }
    async fn query(&self, sql: &str, params_json: &str) -> Result<Vec<...>, AnakiError> { ... }
    async fn execute(&self, sql: &str, params_json: &str) -> Result<u64, AnakiError> { ... }
    async fn execute_batch(&self, sql: &str, params_list_json: &str) -> Result<u64, AnakiError> { ... }
    async fn begin_transaction(&self) -> Result<(), AnakiError> { ... }
    async fn commit(&self) -> Result<(), AnakiError> { ... }
    async fn rollback(&self) -> Result<(), AnakiError> { ... }
    async fn ping(&self) -> Result<bool, AnakiError> { ... }
}
```

### 8.3 Dart Structure

```dart
// packages/anaki_newdb/lib/src/newdb_driver.dart
class NewDbDriver implements AnakiDriver {
  @override
  SqlDialect get dialect => SqlDialect.generic;  // ... or specific
  
  @override
  Future<void> rawOpen() async { ... }
  
  @override
  Future<void> rawClose() async { ... }
  
  // ... other methods
}
```

---

## 9. Native Binaries

### 9.1 Location

Each driver package contains pre-compiled binaries in `native_libs/`:

```
anaki_sqlite/native_libs/
├── libanaki_sqlite-darwin-arm64.dylib  # macOS ARM
├── libanaki_sqlite-darwin-x64.dylib    # macOS Intel
├── libanaki_sqlite-linux-x64.so        # Linux x64
└── anaki_sqlite-windows-x64.dll        # Windows x64
```

### 9.2 Compilation

```bash
# Specific driver (local)
./scripts/build_native.sh sqlite --local

# Specific driver (all platforms)
./scripts/build_native.sh sqlite

# All drivers
./scripts/build_native.sh all
```

### 9.3 Loading

The driver attempts to load the native library from multiple locations:

1. Next to the executable
2. Current directory
3. `native_libs/` (platform-specific name)
4. `native_libs/` (generic name)
5. Package path (for `path:` dependencies)
6. System default

---

## 10. Dialect Comparison

| Feature | SQLite | PostgreSQL | MySQL | MSSQL |
|---------|--------|------------|-------|-------|
| Auto-increment | `INTEGER PRIMARY KEY AUTOINCREMENT` | `SERIAL` | `AUTO_INCREMENT` | `IDENTITY(1,1)` |
| Pagination | `LIMIT/OFFSET` | `LIMIT/OFFSET` | `LIMIT/OFFSET` | `OFFSET/FETCH` |
| Boolean | `INTEGER` (0/1) | `BOOLEAN` | `TINYINT(1)` | `BIT` |
| String concat | `\|\|` | `\|\|` | `CONCAT()` | `+` |
| Current time | `CURRENT_TIMESTAMP` | `NOW()` | `NOW()` | `GETDATE()` |
| IF NOT EXISTS | ✅ | ✅ | ✅ | ❌ (use `IF NOT EXISTS (SELECT...)`) |

---

## 11. Troubleshooting

### 11.1 Library not found

```
ConnectionException: Failed to load native library: libanaki_sqlite.dylib
```

**Solutions:**
1. Check if the binary exists in `native_libs/`
2. Run `./scripts/build_native.sh sqlite --local`
3. For AOT, copy the binary next to the executable

### 11.2 Connection refused

```
ConnectionException: Connection refused
```

**Solutions:**
1. Check if the database is running
2. Confirm host/port
3. Check firewall/network

### 11.3 MSSQL: ORDER BY mandatory

```
QueryException: ORDER BY is mandatory for OFFSET/FETCH
```

**Solution:** Add `ORDER BY` to paginated queries for MSSQL.

### 11.4 MSSQL: Database does not exist

```
ConnectionException: Cannot open database "myapp"
```

**Solution:** Create the database manually before connecting:
```sql
CREATE DATABASE myapp;
```

---

## 12. References

- [Specification (SDD)](./spec.md)
- [Architecture](./architecture.md)
- [API Reference](./api.md)
- [Docker AOT Deployment](./docker-aot.md)
