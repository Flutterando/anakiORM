/// AnakiORM MySQL driver.
///
/// Provides a native MySQL connector via Rust FFI.
///
/// ```dart
/// import 'package:anaki_orm/anaki_orm.dart';
/// import 'package:anaki_mysql/anaki_mysql.dart';
///
/// final driver = MysqlDriver(
///   host: 'localhost',
///   database: 'mydb',
///   username: 'root',
///   password: 'secret',
/// );
/// final db = AnakiDb(driver);
/// await db.open();
/// ```
library anaki_mysql;

export 'src/mysql_driver.dart';
