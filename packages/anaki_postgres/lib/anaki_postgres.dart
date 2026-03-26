/// AnakiORM PostgreSQL driver.
///
/// Provides a native PostgreSQL connector via Rust FFI.
///
/// ```dart
/// import 'package:anaki_orm/anaki_orm.dart';
/// import 'package:anaki_postgres/anaki_postgres.dart';
///
/// final driver = PostgresDriver(
///   host: 'localhost',
///   database: 'mydb',
///   username: 'postgres',
///   password: 'secret',
/// );
/// final db = AnakiDb(driver);
/// await db.open();
/// ```
library anaki_postgres;

export 'src/postgres_driver.dart';
