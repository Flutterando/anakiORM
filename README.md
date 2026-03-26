# Anaki

> ⚠️ **ALPHA** — This project is in early development. APIs may change. Use in production at your own risk.

A Dapper-style database toolkit for Dart — SQL-first, simple mapping, native performance via Rust FFI.

## Why Anaki?

- **SQL-first** — Write real SQL. No DSL to learn, no magic strings.
- **Simple mapping** — `fromJson`/`toJson` conventions, compatible with Vaden DTOs.
- **Native performance** — Rust connectors via FFI. No pure-Dart protocol parsing.
- **Pick your database** — One package per driver. Only import what you use.
- **Query builder included** — Optional fluent API when you don't want raw SQL.
- **Migrations** — Plain `.sql` files, automatic tracking.

## Packages

| Package | Database | Status |
|---------|----------|--------|
| [`anaki_orm`](packages/anaki_orm/) | Core (pure Dart) | ✅ Ready |
| [`anaki_sqlite`](packages/anaki_sqlite/) | SQLite | ✅ Ready |
| [`anaki_postgres`](packages/anaki_postgres/) | PostgreSQL | ✅ Ready |
| [`anaki_mysql`](packages/anaki_mysql/) | MySQL | ✅ Ready |
| [`anaki_mssql`](packages/anaki_mssql/) | SQL Server | ✅ Ready |
| `anaki_oracle` | Oracle | 🔜 Deferred |

## Get Started

```yaml
# pubspec.yaml
dependencies:
  anaki_orm: ^0.1.0
  anaki_sqlite: ^0.1.0  # or anaki_postgres, anaki_mysql, anaki_mssql
```

```dart
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_sqlite/anaki_sqlite.dart';

void main() async {
  final db = AnakiDb(SqliteDriver(':memory:'));
  await db.open();

  // Raw SQL — always available
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

  // Or use the query builder
  final qb = AnakiQueryBuilder(db, adapter);
  final active = await qb.select<UserDTO>('users')
      .where('active = @active', {'active': true})
      .orderBy('name')
      .list();

  await db.close();
}
```

📖 **Full API docs** → [`packages/anaki_orm/README.md`](packages/anaki_orm/README.md)

## Quick Overview

### Raw SQL (AnakiDb)

```dart
final rows   = await db.query('SELECT * FROM users');
final first  = await db.queryFirst('SELECT * FROM users WHERE id = @id', {'id': 1});
final count  = await db.scalar<int>('SELECT COUNT(*) FROM users');
final affected = await db.execute('DELETE FROM users WHERE active = 0');

await db.transaction((tx) async {
  await tx.execute('UPDATE accounts SET balance = balance - 100 WHERE id = @from', {'from': 1});
  await tx.execute('UPDATE accounts SET balance = balance + 100 WHERE id = @to', {'to': 2});
});
```

### Query Builder

```dart
final qb = AnakiQueryBuilder(db, adapter);

await qb.select<UserDTO>('users').where('active = @a', {'a': true}).list();
await qb.insert<UserDTO>('users').entity(user).run();
await qb.update('users').set({'email': 'new@x.com'}).where('id = @id', {'id': 1}).run();
await qb.delete('users').where('id = @id', {'id': 1}).run();
```

### Migrations

```dart
await Migrator(db).run('migrations/');
// Reads 001_create_users.sql, 002_add_index.sql, ... in order
```

### Seeds

```dart
await Seeder(db).run('seeds/');
// Reads 001_seed_users.sql, 002_seed_products.sql, ... in order
```

## Docker / AOT Deployment

Anaki uses native libraries (`.so`, `.dylib`, `.dll`) that must be available at runtime. For Docker or AOT-compiled applications, you need to include the native library in your container.

### Building for Docker (Linux x64)

```bash
# 1. Build the native library for Linux
./scripts/build_native.sh sqlite  # or postgres, mysql, mssql, all

# 2. Copy the library to your Docker build context
cp packages/anaki_sqlite/native_libs/libanaki_sqlite-linux-x64.so ./docker/
```

### Dockerfile Example

```dockerfile
FROM dart:stable AS build

WORKDIR /app
COPY . .
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server

# Copy the native library
COPY --from=build /app/docker/libanaki_sqlite-linux-x64.so /app/bin/

WORKDIR /app/bin
CMD ["./server"]
```

### Important Notes

- The native library must be in the same directory as the executable, or in a system library path
- For Linux containers, use the `-linux-x64.so` variant
- See [docs/build.md](docs/build.md) for complete build instructions

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for project structure, how to build native libraries, run tests, and add new drivers.

## License

MIT
