# Anaki ORM — API Reference

> Complete documentation of the Anaki ORM public API

---

## 1. AnakiDb

Main class for database operations.

### 1.1 Constructor

```dart
AnakiDb(AnakiDriver driver)
```

**Parameters:**
- `driver` — Driver instance (SqliteDriver, PostgresDriver, etc.)

**Example:**
```dart
final db = AnakiDb(SqliteDriver(':memory:'));
```

---

### 1.2 Properties

| Property | Type | Description |
|----------|------|-------------|
| `isOpen` | `bool` | Indicates if the connection is open |
| `dialect` | `SqlDialect` | SQL dialect of the driver (generic, sqlite, mssql) |

---

### 1.3 Methods

#### `open()`

Opens the database connection.

```dart
Future<void> open()
```

**Exceptions:**
- `ConnectionException` — Connection failure

**Example:**
```dart
await db.open();
```

---

#### `close()`

Closes the database connection.

```dart
Future<void> close()
```

**Example:**
```dart
await db.close();
```

---

#### `ping()`

Checks if the connection is active.

```dart
Future<bool> ping()
```

**Returns:** `true` if the connection is active

**Exceptions:**
- `NotConnectedException` — Connection not open

**Example:**
```dart
final alive = await db.ping();
```

---

#### `query<T>()`

Executes a SQL query and returns the results.

```dart
Future<List<T>> query<T>(
  String sql, [
  Map<String, dynamic>? params,
  T Function(Map<String, dynamic>)? map,
])
```

**Parameters:**
- `sql` — SQL query with named parameters (`@param`)
- `params` — Parameters map (optional)
- `map` — Mapping function row → object (optional)

**Returns:** 
- Without `map`: `List<Map<String, dynamic>>`
- With `map`: `List<T>`

**Exceptions:**
- `NotConnectedException` — Connection not open
- `QueryException` — Query execution error

**Examples:**
```dart
// Without mapping — returns List<Map<String, dynamic>>
final rows = await db.query('SELECT * FROM users');

// With parameters
final rows = await db.query(
  'SELECT * FROM users WHERE active = @active',
  {'active': true},
);

// With mapping — returns List<UserDTO>
final users = await db.query(
  'SELECT * FROM users WHERE active = @active',
  {'active': true},
  UserDTO.fromJson,
);
```

---

#### `queryFirst<T>()`

Executes a query and returns only the first result.

```dart
Future<T?> queryFirst<T>(
  String sql, [
  Map<String, dynamic>? params,
  T Function(Map<String, dynamic>)? map,
])
```

**Parameters:** Same as `query()`

**Returns:** First item or `null` if empty

**Example:**
```dart
final user = await db.queryFirst(
  'SELECT * FROM users WHERE id = @id',
  {'id': 1},
  UserDTO.fromJson,
);
```

---

#### `execute()`

Executes a SQL statement (INSERT, UPDATE, DELETE).

```dart
Future<int> execute(String sql, [Map<String, dynamic>? params])
```

**Parameters:**
- `sql` — SQL statement
- `params` — Parameters map (optional)

**Returns:** Number of affected rows

**Exceptions:**
- `NotConnectedException` — Connection not open
- `QueryException` — Execution error

**Examples:**
```dart
// INSERT
final affected = await db.execute(
  'INSERT INTO users (name, email) VALUES (@name, @email)',
  {'name': 'Ana', 'email': 'ana@example.com'},
);

// UPDATE
final affected = await db.execute(
  'UPDATE users SET active = @active WHERE id = @id',
  {'active': false, 'id': 1},
);

// DELETE
final affected = await db.execute(
  'DELETE FROM users WHERE id = @id',
  {'id': 1},
);
```

---

#### `executeBatch()`

Executes a statement multiple times with different parameters.

```dart
Future<int> executeBatch(
  String sql,
  List<Map<String, dynamic>> paramsList,
)
```

**Parameters:**
- `sql` — SQL statement
- `paramsList` — List of parameter maps

**Returns:** Total affected rows

**Example:**
```dart
final affected = await db.executeBatch(
  'INSERT INTO users (name) VALUES (@name)',
  [
    {'name': 'Ana'},
    {'name': 'Bob'},
    {'name': 'Carol'},
  ],
);
// affected = 3
```

---

#### `scalar<T>()`

Executes a query and returns a single scalar value.

```dart
Future<T?> scalar<T>(String sql, [Map<String, dynamic>? params])
```

**Parameters:**
- `sql` — SQL query that returns a single value
- `params` — Parameters map (optional)

**Returns:** Value of the first column of the first row, or `null`

**Example:**
```dart
final count = await db.scalar<int>('SELECT COUNT(*) FROM users');
final name = await db.scalar<String>(
  'SELECT name FROM users WHERE id = @id',
  {'id': 1},
);
```

---

#### `queryPaged<T>()`

Executes a query with automatic pagination.

```dart
Future<PagedResult<T>> queryPaged<T>(
  String sql, {
  Map<String, dynamic>? params,
  required int page,
  required int pageSize,
  T Function(Map<String, dynamic>)? map,
})
```

**Parameters:**
- `sql` — SQL query (without LIMIT/OFFSET)
- `params` — Parameters map (optional)
- `page` — Page number (1-indexed)
- `pageSize` — Items per page
- `map` — Mapping function (optional)

**Returns:** `PagedResult<T>` with data and pagination metadata

**Note:** The method automatically adds `LIMIT/OFFSET` (or `OFFSET/FETCH` for MSSQL)

**Example:**
```dart
final page = await db.queryPaged(
  'SELECT * FROM users WHERE active = @active ORDER BY name',
  params: {'active': true},
  page: 2,
  pageSize: 20,
  map: UserDTO.fromJson,
);

print('Total: ${page.total}');
print('Pages: ${page.totalPages}');
print('Has next: ${page.hasNextPage}');
```

---

#### `transaction()`

Executes operations within a transaction.

```dart
Future<void> transaction(Future<void> Function(AnakiDb tx) action)
```

**Parameters:**
- `action` — Async function that receives the transaction context

**Behavior:**
- Success: Automatic `COMMIT`
- Exception: Automatic `ROLLBACK`, exception is rethrown

**Exceptions:**
- `NotConnectedException` — Connection not open
- `TransactionException` — Rollback error

**Example:**
```dart
await db.transaction((tx) async {
  await tx.execute(
    'UPDATE accounts SET balance = balance - @amount WHERE id = @from',
    {'amount': 100, 'from': 1},
  );
  await tx.execute(
    'UPDATE accounts SET balance = balance + @amount WHERE id = @to',
    {'amount': 100, 'to': 2},
  );
});
```

---

## 2. PagedResult<T>

Result of a paginated query.

### 2.1 Properties

| Property | Type | Description |
|----------|------|-------------|
| `data` | `List<T>` | Items of the current page |
| `total` | `int` | Total items across all pages |
| `page` | `int` | Current page number (1-indexed) |
| `pageSize` | `int` | Items per page |
| `totalPages` | `int` | Total pages (calculated) |
| `hasNextPage` | `bool` | Whether next page exists |
| `hasPreviousPage` | `bool` | Whether previous page exists |

---

## 3. AnakiQueryBuilder

Fluent query builder for database operations.

### 3.1 Constructor

```dart
AnakiQueryBuilder(AnakiDb db, RowAdapter adapter)
```

**Parameters:**
- `db` — AnakiDb instance
- `adapter` — Adapter for row ↔ object conversion

**Example:**
```dart
final adapter = RowAdapter(dson.fromJson, dson.toJson);
final qb = AnakiQueryBuilder(db, adapter);
```

---

### 3.2 Methods

#### `select<T>()`

Starts a SELECT builder.

```dart
SelectBuilder<T> select<T>(String table)
```

**Example:**
```dart
final users = await qb.select<UserDTO>('users')
    .where('active = @active', {'active': true})
    .orderBy('name')
    .limit(10)
    .list();
```

---

#### `insert<T>()`

Starts an INSERT builder.

```dart
InsertBuilder<T> insert<T>(String table)
```

**Example:**
```dart
// Via Map
await qb.insert<UserDTO>('users')
    .values({'name': 'Ana', 'email': 'ana@example.com'})
    .run();

// Via entity (uses adapter.toJson)
await qb.insert<UserDTO>('users')
    .entity(user)
    .run();
```

---

#### `update()`

Starts an UPDATE builder.

```dart
UpdateBuilder update(String table)
```

**Example:**
```dart
// Via Map
await qb.update('users')
    .set({'email': 'new@example.com'})
    .where('id = @id', {'id': 1})
    .run();

// Via entity (excludes nulls automatically)
await qb.update('users')
    .setEntity<UpdateUserDTO>(partialUser)
    .where('id = @id', {'id': 1})
    .run();
```

---

#### `delete()`

Starts a DELETE builder.

```dart
DeleteBuilder delete(String table)
```

**Example:**
```dart
await qb.delete('users')
    .where('id = @id', {'id': 1})
    .run();
```

---

## 4. SelectBuilder<T>

Builder for SELECT queries.

### 4.1 Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `columns(List<String>)` | `SelectBuilder<T>` | Sets specific columns |
| `where(String, Map?)` | `SelectBuilder<T>` | Adds WHERE condition |
| `orderBy(String)` | `SelectBuilder<T>` | Adds ORDER BY |
| `limit(int)` | `SelectBuilder<T>` | Sets LIMIT |
| `offset(int)` | `SelectBuilder<T>` | Sets OFFSET |
| `build()` | `String` | Returns generated SQL (debug) |
| `list()` | `Future<List<T>>` | Executes and returns list |
| `first()` | `Future<T?>` | Executes and returns first |
| `paged(int page, int pageSize)` | `Future<PagedResult<T>>` | Executes with pagination |

**Complete example:**
```dart
final users = await qb.select<UserDTO>('users')
    .columns(['id', 'name', 'email'])
    .where('active = @active', {'active': true})
    .where('created_at > @date', {'date': '2024-01-01'})
    .orderBy('name ASC')
    .limit(50)
    .offset(100)
    .list();
```

---

## 5. InsertBuilder<T>

Builder for INSERT statements.

### 5.1 Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `values(Map<String, dynamic>)` | `InsertBuilder<T>` | Sets values via Map |
| `entity(T)` | `InsertBuilder<T>` | Sets values via object |
| `build()` | `String` | Returns generated SQL |
| `run()` | `Future<int>` | Executes and returns rows affected |

**Example:**
```dart
// Via Map
await qb.insert<UserDTO>('users')
    .values({'name': 'Ana', 'email': 'ana@example.com', 'active': true})
    .run();

// Via entity
final user = UserDTO(name: 'Ana', email: 'ana@example.com', active: true);
await qb.insert<UserDTO>('users').entity(user).run();
```

---

## 6. UpdateBuilder

Builder for UPDATE statements.

### 6.1 Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `set(Map<String, dynamic>)` | `UpdateBuilder` | Sets values via Map |
| `setEntity<T>(T)` | `UpdateBuilder` | Sets values via object (excludes nulls) |
| `where(String, Map?)` | `UpdateBuilder` | Adds WHERE condition |
| `build()` | `String` | Returns generated SQL |
| `run()` | `Future<int>` | Executes and returns rows affected |

**Example:**
```dart
// Partial update via Map
await qb.update('users')
    .set({'email': 'new@example.com'})
    .where('id = @id', {'id': 1})
    .run();

// Partial update via DTO (nulls are ignored)
final partial = UpdateUserDTO(email: 'new@example.com'); // name = null
await qb.update('users')
    .setEntity<UpdateUserDTO>(partial)
    .where('id = @id', {'id': 1})
    .run();
// Generates: UPDATE users SET email = @email WHERE id = @id
```

---

## 7. DeleteBuilder

Builder for DELETE statements.

### 7.1 Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `where(String, Map?)` | `DeleteBuilder` | Adds WHERE condition |
| `build()` | `String` | Returns generated SQL |
| `run()` | `Future<int>` | Executes and returns rows affected |

**Example:**
```dart
await qb.delete('users')
    .where('id = @id', {'id': 1})
    .run();

// Multiple conditions
await qb.delete('sessions')
    .where('user_id = @userId', {'userId': 1})
    .where('expired_at < @now', {'now': DateTime.now().toIso8601String()})
    .run();
```

---

## 8. RowAdapter

Adapter for conversion between Map and typed objects.

### 8.1 Constructor

```dart
RowAdapter(
  T Function<T>(Map<String, dynamic> row) fromJson,
  Map<String, dynamic> Function<T>(T entity) toJson,
)
```

**Integration with Vaden/DSON:**
```dart
@Bean()
RowAdapter rowAdapter(DSON dson) => RowAdapter(dson.fromJson, dson.toJson);
```

---

## 9. Migrator

SQL migrations executor.

### 9.1 Constructor

```dart
Migrator(AnakiDb db)
```

### 9.2 Methods

#### `run()`

Executes all pending migrations.

```dart
Future<List<String>> run(String migrationsDir)
```

**Parameters:**
- `migrationsDir` — Path to folder with `.sql` files

**Returns:** List of executed migration names

**Behavior:**
1. Creates `_anaki_migrations` table if not exists
2. Lists `.sql` files in alphabetical order
3. Filters already applied files
4. Executes each pending file
5. Records in tracking table

**Example:**
```dart
final executed = await Migrator(db).run('migrations/');
print('Executed migrations: $executed');
```

#### `getAppliedMigrations()`

Returns list of already applied migrations.

```dart
Future<List<String>> getAppliedMigrations()
```

---

## 10. Seeder

SQL seeds executor.

### 10.1 Constructor

```dart
Seeder(AnakiDb db)
```

### 10.2 Methods

#### `run()`

Executes all pending seeds.

```dart
Future<List<String>> run(String seedsDir)
```

**Parameters:**
- `seedsDir` — Path to folder with `.sql` files

**Returns:** List of executed seed names

**Example:**
```dart
final executed = await Seeder(db).run('seeds/');
```

---

## 11. Exceptions

### 11.1 Hierarchy

```
AnakiException
├── ConnectionException
├── QueryException
├── TransactionException
└── NotConnectedException
```

### 11.2 AnakiException

Base for all Anaki exceptions.

```dart
class AnakiException implements Exception {
  final String message;
  final String? details;
}
```

### 11.3 ConnectionException

Database connection error.

```dart
class ConnectionException extends AnakiException {
  const ConnectionException(String message, {String? details});
}
```

### 11.4 QueryException

Query/statement execution error.

```dart
class QueryException extends AnakiException {
  final String? sql;
  const QueryException(String message, {this.sql, String? details});
}
```

### 11.5 TransactionException

Transaction operation error.

```dart
class TransactionException extends AnakiException {
  const TransactionException(String message, {String? details});
}
```

### 11.6 NotConnectedException

Operation attempted without open connection.

```dart
class NotConnectedException extends AnakiException {
  const NotConnectedException();
}
```

---

## 12. SqlDialect

Enum of supported SQL dialects.

```dart
enum SqlDialect {
  generic,  // PostgreSQL, MySQL
  sqlite,   // SQLite
  mssql,    // SQL Server
}
```

**Usage:** Each driver declares its dialect. Affects:
- Pagination: `LIMIT/OFFSET` vs `OFFSET/FETCH`
- Migration DDL: `SERIAL` vs `IDENTITY`
- Subqueries: ORDER BY removal in COUNT (MSSQL)

---

## 13. PoolConfig

Connection pool configuration.

```dart
class PoolConfig {
  final int minConnections;
  final int maxConnections;
  
  const PoolConfig({
    this.minConnections = 1,
    this.maxConnections = 10,
  });
}
```

**Usage:**
```dart
final driver = SqliteDriver(
  'database.db',
  poolConfig: PoolConfig(minConnections: 2, maxConnections: 20),
);
```

---

## 14. References

- [Specification (SDD)](./spec.md)
- [Architecture](./architecture.md)
- [Drivers Guide](./drivers.md)
