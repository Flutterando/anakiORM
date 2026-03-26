/// AnakiORM — A Dapper-style ORM for Dart.
///
/// SQL-first, simple mapping, native database connectors via Rust FFI.
///
/// ```dart
/// import 'package:anaki_orm/anaki_orm.dart';
/// import 'package:anaki_sqlite/anaki_sqlite.dart';
///
/// final db = AnakiDb(SqliteDriver('path/to/db.sqlite'));
/// await db.open();
///
/// final users = await db.query(
///   'SELECT * FROM users WHERE active = @active',
///   {'active': true},
///   UserDTO.fromJson,
/// );
///
/// await db.close();
/// ```
library anaki_orm;

export 'src/db.dart';
export 'src/driver.dart';
export 'src/exceptions.dart';
export 'src/paged_result.dart';
export 'src/pool_config.dart';
export 'src/query_builder/row_adapter.dart';
export 'src/query_builder/anaki_query_builder.dart';
export 'src/query_builder/select_builder.dart';
export 'src/query_builder/insert_builder.dart';
export 'src/query_builder/update_builder.dart';
export 'src/query_builder/delete_builder.dart';
export 'src/migrator.dart';
export 'src/seeder.dart';
