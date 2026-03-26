/// AnakiORM SQLite driver.
///
/// Provides a native SQLite connector via Rust FFI.
///
/// ```dart
/// import 'package:anaki_orm/anaki_orm.dart';
/// import 'package:anaki_sqlite/anaki_sqlite.dart';
///
/// final db = AnakiDb(SqliteDriver(':memory:'));
/// await db.open();
///
/// await db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');
/// await db.execute('INSERT INTO users (name) VALUES (@name)', {'name': 'Ana'});
///
/// final users = await db.query('SELECT * FROM users');
/// print(users); // [{id: 1, name: Ana}]
///
/// await db.close();
/// ```
library anaki_sqlite;

export 'src/sqlite_driver.dart';
