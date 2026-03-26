# Anaki ORM — Software Design Specification (SDD)

> **Version**: 0.1.0  
> **Status**: In development  
> **Last updated**: March 2026

---

## 1. Overview

**Anaki** is a Dapper-style database toolkit for Dart — SQL-first, simple mapping, native performance via Rust FFI.

### 1.1 Goals

| Goal | Description |
|------|-------------|
| **SQL-first** | Real SQL, no proprietary DSL, no magic strings |
| **Simple mapping** | `fromJson`/`toJson` convention, compatible with Vaden DTOs |
| **Native performance** | Rust connectors via FFI, no pure-Dart protocol parsing |
| **Modular** | One package per driver, import only what you use |
| **Optional Query Builder** | Fluent API when you don't want raw SQL |
| **Migrations** | Simple `.sql` files, automatic tracking |

### 1.2 Target Audience

- Server-side Dart developers (Shelf, Vaden)
- Projects that need direct SQL access
- Applications requiring native performance for database operations

### 1.3 Supported Platforms

| Platform | Architecture | Status |
|----------|--------------|--------|
| Linux | x64 | ✅ Production |
| macOS | ARM64 | ✅ Development |
| macOS | x64 | ✅ Development |
| Windows | x64 | ✅ Development |

---

## 2. Functional Requirements

### 2.1 Core (FR-CORE)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-CORE-01 | Execute SQL queries with named parameters (`@param`) | High |
| FR-CORE-02 | Return results as `List<Map<String, dynamic>>` | High |
| FR-CORE-03 | Map results to DTOs via `fromJson` function | High |
| FR-CORE-04 | Execute statements (INSERT/UPDATE/DELETE) returning rows affected | High |
| FR-CORE-05 | Execute batch statements with multiple parameter sets | High |
| FR-CORE-06 | Return scalar value from queries | High |
| FR-CORE-07 | Support automatic pagination with total count | High |
| FR-CORE-08 | Manage transactions with automatic commit/rollback | High |
| FR-CORE-09 | Verify connection via ping | Medium |

### 2.2 Query Builder (FR-QB)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-QB-01 | Fluent SELECT with where, orderBy, limit, offset | High |
| FR-QB-02 | Fluent INSERT with values (Map) or entity (DTO) | High |
| FR-QB-03 | Fluent UPDATE with set, setEntity, where | High |
| FR-QB-04 | Fluent DELETE with where | High |
| FR-QB-05 | Support SQL dialects (generic, sqlite, mssql) | High |
| FR-QB-06 | Expose generated SQL via `.build()` for debugging | Medium |

### 2.3 Migrations (FR-MIG)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-MIG-01 | Execute `.sql` files in alphabetical order | High |
| FR-MIG-02 | Track applied migrations in `_anaki_migrations` table | High |
| FR-MIG-03 | Skip already applied migrations | High |
| FR-MIG-04 | Support dialect-specific DDL (SERIAL vs IDENTITY) | High |

### 2.4 Seeds (FR-SEED)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-SEED-01 | Execute seed `.sql` files in order | Medium |
| FR-SEED-02 | Track applied seeds in `_anaki_seeds` table | Medium |

### 2.5 Drivers (FR-DRV)

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-DRV-01 | Functional SQLite driver | High |
| FR-DRV-02 | Functional PostgreSQL driver | High |
| FR-DRV-03 | Functional MySQL driver | High |
| FR-DRV-04 | Functional SQL Server driver | High |
| FR-DRV-05 | Functional Oracle driver | Low (Deferred) |
| FR-DRV-06 | Each driver must declare its `SqlDialect` | High |

---

## 3. Non-Functional Requirements

### 3.1 Performance (NFR-PERF)

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-PERF-01 | Simple query latency | < 1ms overhead over native driver |
| NFR-PERF-02 | JSON FFI serialization | < 0.1ms for 100 rows |
| NFR-PERF-03 | Connection pooling | Supported via configuration |

### 3.2 Reliability (NFR-REL)

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-REL-01 | Error handling | Typed exceptions (Connection, Query, Transaction) |
| NFR-REL-02 | Automatic rollback | On exception within transaction |
| NFR-REL-03 | Connection verification | `ping()` method available |

### 3.3 Maintainability (NFR-MAINT)

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-MAINT-01 | Unit test coverage | > 80% in core package |
| NFR-MAINT-02 | Integration tests | Per driver, with Docker |
| NFR-MAINT-03 | API documentation | Complete Dartdoc |

### 3.4 Portability (NFR-PORT)

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-PORT-01 | Pre-compiled binaries | Included in pub.dev package |
| NFR-PORT-02 | Automatic platform detection | Via FFI loader |
| NFR-PORT-03 | AOT compilation support | Compatible with `dart compile exe` |

---

## 4. Use Cases

### UC-01: Simple Query

```
Actor: Developer
Precondition: Connection open
Flow:
  1. Developer calls db.query('SELECT * FROM users')
  2. System executes query via FFI
  3. Rust returns JSON with rows
  4. Dart deserializes to List<Map>
  5. System returns result
Postcondition: List of maps returned
```

### UC-02: Query with Mapping

```
Actor: Developer
Precondition: Connection open, DTO with fromJson
Flow:
  1. Developer calls db.query('SELECT...', params, UserDTO.fromJson)
  2. System executes query
  3. System applies fromJson to each row
  4. System returns List<UserDTO>
Postcondition: Typed list returned
```

### UC-03: Transaction

```
Actor: Developer
Precondition: Connection open
Flow:
  1. Developer calls db.transaction((tx) async { ... })
  2. System initiates BEGIN TRANSACTION
  3. Developer executes operations via tx
  4a. Success: System executes COMMIT
  4b. Exception: System executes ROLLBACK, rethrow
Postcondition: Transaction finalized (commit or rollback)
```

### UC-04: Migration

```
Actor: Developer
Precondition: Connection open, migrations/ folder with .sql files
Flow:
  1. Developer calls Migrator(db).run('migrations/')
  2. System creates _anaki_migrations table if not exists
  3. System lists .sql files sorted
  4. System filters unapplied files
  5. For each pending file:
     a. Execute SQL
     b. Record in tracking table
  6. Return list of executed migrations
Postcondition: Schema updated, migrations recorded
```

### UC-05: Query Builder SELECT

```
Actor: Developer
Precondition: Connection open, QueryBuilder configured
Flow:
  1. Developer calls qb.select<User>('users').where('active = @a', {'a': true}).list()
  2. System generates SQL: SELECT * FROM users WHERE active = @a
  3. System executes query
  4. System maps rows via adapter.fromJson<User>
  5. Returns List<User>
Postcondition: Typed list returned
```

---

## 5. Glossary

| Term | Definition |
|------|------------|
| **AnakiDb** | Main class that wraps a driver and exposes the high-level API |
| **AnakiDriver** | Interface that each database driver implements |
| **RowAdapter** | Generic adapter for row ↔ object conversion |
| **SqlDialect** | Enum indicating SQL dialect (generic, sqlite, mssql) |
| **FFI** | Foreign Function Interface — mechanism to call native code |
| **DTO** | Data Transfer Object — simple class with fromJson/toJson |
| **Dapper-style** | ORM style that prioritizes explicit SQL over abstractions |

---

## 6. References

- [Architecture Documentation](./architecture.md)
- [API Reference](./api.md)
- [Drivers Guide](./drivers.md)
- [Docker AOT Deployment Guide](./docker-aot.md)
- [CONTRIBUTING.md](../CONTRIBUTING.md)
