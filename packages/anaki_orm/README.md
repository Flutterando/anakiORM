# anaki_orm

Core package for Anaki — a Dapper-style database toolkit for Dart.

This package provides `AnakiDb`, the fluent `AnakiQueryBuilder`, and the SQL `Migrator`. It is **pure Dart** with no native dependencies — you pair it with a driver package for your database.

## Install

```yaml
dependencies:
  anaki_orm: ^0.1.0
  anaki_sqlite: ^0.1.0  # or anaki_postgres, anaki_mysql, anaki_mssql
```

## Quick Start

```dart
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_sqlite/anaki_sqlite.dart';

void main() async {
  final db = AnakiDb(SqliteDriver(':memory:'));
  await db.open();

  await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT
    )
  ''');

  // Insert
  await db.execute(
    'INSERT INTO users (name, email) VALUES (@name, @email)',
    {'name': 'Ana', 'email': 'ana@example.com'},
  );

  // Query with mapping
  final users = await db.query(
    'SELECT * FROM users',
    null,
    UserDTO.fromJson,
  );

  // Scalar
  final count = await db.scalar<int>('SELECT COUNT(*) FROM users');

  // Transaction
  await db.transaction((tx) async {
    await tx.execute(
      'UPDATE users SET name = @name WHERE id = @id',
      {'name': 'Ana Maria', 'id': 1},
    );
  });

  await db.close();
}
```

## AnakiDb API

The core class for all database operations. SQL-first, no magic.

| Method | Returns | Description |
|--------|---------|-------------|
| `open()` | `Future<void>` | Open connection |
| `close()` | `Future<void>` | Close connection |
| `ping()` | `Future<bool>` | Check if alive |
| `query(sql, params?, map?)` | `Future<List<T>>` | Query rows, optionally map to `T` |
| `queryFirst(sql, params?, map?)` | `Future<T?>` | First row or `null` |
| `execute(sql, params?)` | `Future<int>` | Non-query, returns rows affected |
| `executeBatch(sql, paramsList)` | `Future<int>` | Batch execute, returns total affected |
| `scalar<T>(sql, params?)` | `Future<T?>` | Single scalar value |
| `queryPaged(sql, ...)` | `Future<PagedResult<T>>` | Paginated query with total count |
| `transaction(fn)` | `Future<void>` | Execute within transaction (auto commit/rollback) |

### Named Parameters

All SQL uses named parameters with `@` prefix:

```dart
await db.execute(
  'INSERT INTO users (name, age) VALUES (@name, @age)',
  {'name': 'Ana', 'age': 28},
);
```

### Pagination

```dart
final page = await db.queryPaged<UserDTO>(
  'SELECT * FROM users WHERE active = @active ORDER BY name',
  params: {'active': true},
  page: 2,
  pageSize: 20,
  map: UserDTO.fromJson,
);

print(page.data);          // List<UserDTO>
print(page.total);         // total across all pages
print(page.totalPages);    // computed
print(page.hasNextPage);   // bool
```

Pagination is dialect-aware — uses `LIMIT/OFFSET` for SQLite/PostgreSQL/MySQL and `OFFSET/FETCH` for SQL Server.

## Query Builder

For fluent query building without writing raw SQL. Requires a `RowAdapter` for automatic mapping.

### RowAdapter

A simple class that holds two functions — `fromJson` and `toJson` — with generics on the method:

```dart
class RowAdapter {
  final T Function<T>(Map<String, dynamic> row) fromJson;
  final Map<String, dynamic> Function<T>(T entity) toJson;
  RowAdapter(this.fromJson, this.toJson);
}
```

**With Vaden** (DSON already has the exact same signature):

```dart
@Bean()
RowAdapter rowAdapter(DSON dson) => RowAdapter(dson.fromJson, dson.toJson);
```

**Without Vaden** (manual registry or any custom logic):

```dart
final fromMap = <Type, Function>{
  UserDTO: (Map<String, dynamic> row) => UserDTO.fromJson(row),
  OrderDTO: (Map<String, dynamic> row) => OrderDTO.fromJson(row),
};
final toMap = <Type, Function>{
  UserDTO: (UserDTO e) => e.toJson(),
  OrderDTO: (OrderDTO e) => e.toJson(),
};

final adapter = RowAdapter(
  <T>(row) => (fromMap[T]!(row)) as T,
  <T>(entity) => (toMap[T]!(entity)) as Map<String, dynamic>,
);
```

### AnakiQueryBuilder

Create one instance and reuse it for all tables. The table name and generic type are specified on each operation:

```dart
final qb = AnakiQueryBuilder(db, adapter);
```

### SELECT

```dart
// List all
final all = await qb.select<UserDTO>('users').list();

// With filters
final active = await qb
    .select<UserDTO>('users')
    .columns(['id', 'name', 'email'])
    .where('active = @active', {'active': true})
    .orderBy('name')
    .limit(10)
    .list();

// First or null
final user = await qb
    .select<UserDTO>('users')
    .where('id = @id', {'id': 1})
    .first();

// Count
final count = await qb
    .select<UserDTO>('users')
    .where('active = @active', {'active': true})
    .count();

// Pagination
final page = await qb
    .select<UserDTO>('users')
    .orderBy('name')
    .paged(page: 1, pageSize: 20);
```

**SelectBuilder methods:**

| Method | Description |
|--------|-------------|
| `.columns(List<String>)` | Columns to select (default: `*`) |
| `.column(String)` | Add a single column |
| `.where(clause, params?)` | WHERE (multiple = AND) |
| `.orWhere(clause, params?)` | OR condition |
| `.orderBy(col, {desc})` | ORDER BY |
| `.groupBy(col)` | GROUP BY |
| `.having(clause, params?)` | HAVING |
| `.limit(n)` | LIMIT |
| `.offset(n)` | OFFSET |
| `.join(table, on)` | INNER JOIN |
| `.leftJoin(table, on)` | LEFT JOIN |
| `.distinct()` | DISTINCT |
| `.build()` | Returns `(String sql, Map params)` without executing |
| `.list()` | Execute and return `List<T>` |
| `.first()` | Execute and return `T?` |
| `.scalar<V>()` | Execute and return scalar |
| `.count()` | Execute COUNT(*) |
| `.paged(page, pageSize)` | Execute with pagination |

### INSERT

```dart
// From map
await qb.insert<UserDTO>('users')
    .values({'name': 'Ana', 'email': 'ana@example.com'})
    .run();

// From entity (uses adapter.toJson)
await qb.insert<UserDTO>('users')
    .entity(UserDTO(name: 'Ana', email: 'ana@example.com'))
    .run();
```

### UPDATE

```dart
await qb.update('users')
    .set({'email': 'new@example.com'})
    .where('id = @id', {'id': 1})
    .run();
```

### DELETE

```dart
await qb.delete('users')
    .where('id = @id', {'id': 1})
    .run();
```

### Inspecting SQL

Every builder has `.build()` to see the generated SQL without executing:

```dart
final (sql, params) = qb
    .select<UserDTO>('users')
    .where('active = @active', {'active': true})
    .orderBy('name')
    .build();

print(sql);    // SELECT * FROM users WHERE active = @active ORDER BY name
print(params); // {active: true}
```

## Migrations

SQL-first schema migrations with automatic tracking.

```dart
await db.open();
final executed = await Migrator(db).run('migrations/');
print('Applied: $executed');
```

Create `.sql` files with numeric prefixes:

```
migrations/
  001_create_users.sql
  002_add_email_index.sql
  003_create_orders.sql
```

The `Migrator`:
- Creates a `_anaki_migrations` tracking table automatically
- Reads `.sql` files in alphabetical order
- Skips already-applied migrations
- Returns the list of newly executed file names
- DDL is dialect-aware (MSSQL vs generic)

```dart
// Check what's been applied
final applied = await Migrator(db).getAppliedMigrations();
```

## Seeds

SQL-first data seeding with automatic tracking.

```dart
await db.open();
final seeded = await Seeder(db).run('seeds/');
print('Seeded: $seeded');
```

Create `.sql` files with numeric prefixes:

```
seeds/
  001_seed_users.sql
  002_seed_products.sql
```

The `Seeder`:
- Creates a `_anaki_seeds` tracking table automatically
- Reads `.sql` files in alphabetical order
- Skips already-applied seeds
- Returns the list of newly executed file names
- DDL is dialect-aware (SQLite, PostgreSQL/MySQL, MSSQL)

```dart
// Check what's been applied
final applied = await Seeder(db).getAppliedSeeds();
```

## Available Drivers

| Package | Database | Install |
|---------|----------|---------|
| [`anaki_sqlite`](../anaki_sqlite/) | SQLite | `anaki_sqlite: ^0.1.0` |
| [`anaki_postgres`](../anaki_postgres/) | PostgreSQL | `anaki_postgres: ^0.1.0` |
| [`anaki_mysql`](../anaki_mysql/) | MySQL | `anaki_mysql: ^0.1.0` |
| [`anaki_mssql`](../anaki_mssql/) | SQL Server | `anaki_mssql: ^0.1.0` |

## Implementing a Custom Driver

Implement the `AnakiDriver` interface:

```dart
class MyDriver implements AnakiDriver {
  @override
  SqlDialect get dialect => SqlDialect.generic;

  @override
  Future<void> rawOpen() async { /* ... */ }

  @override
  Future<void> rawClose() async { /* ... */ }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, Map<String, dynamic>? params) async { /* ... */ }

  @override
  Future<int> rawExecute(String sql, Map<String, dynamic>? params) async { /* ... */ }

  @override
  Future<int> rawExecuteBatch(
    String sql, List<Map<String, dynamic>> paramsList) async { /* ... */ }

  @override
  Future<void> rawBeginTransaction() async { /* ... */ }

  @override
  Future<void> rawCommit() async { /* ... */ }

  @override
  Future<void> rawRollback() async { /* ... */ }

  @override
  Future<bool> rawPing() async { /* ... */ }
}
```

## License

MIT
