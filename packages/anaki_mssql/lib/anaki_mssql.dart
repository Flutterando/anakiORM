/// AnakiORM SQL Server driver.
///
/// Provides a native SQL Server connector via Rust FFI (tiberius).
///
/// ```dart
/// import 'package:anaki_orm/anaki_orm.dart';
/// import 'package:anaki_mssql/anaki_mssql.dart';
///
/// final driver = MssqlDriver(
///   host: 'localhost',
///   database: 'mydb',
///   username: 'sa',
///   password: 'YourStrong!Passw0rd',
///   trustCert: true,
/// );
/// final db = AnakiDb(driver);
/// await db.open();
/// ```
library anaki_mssql;

export 'src/mssql_driver.dart';
