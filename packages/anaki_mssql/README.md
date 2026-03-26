# anaki_mssql

SQL Server driver for [Anaki ORM](https://github.com/Flutterando/anakiORM) — native performance via Rust FFI.

This package provides the Microsoft SQL Server database driver for Anaki ORM, enabling high-performance database operations through native Rust bindings (tiberius).

## Documentation

For complete documentation, installation guides, API reference, and examples, please visit the main repository:

👉 **[https://github.com/Flutterando/anakiORM](https://github.com/Flutterando/anakiORM)**

## Quick Start

```yaml
dependencies:
  anaki_orm: ^0.1.0
  anaki_mssql: ^0.1.0
```

```dart
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_mssql/anaki_mssql.dart';

void main() async {
  final db = AnakiDb(MssqlDriver(
    host: 'localhost',
    port: 1433,
    database: 'myapp',
    username: 'sa',
    password: 'YourStrong@Password',
  ));
  await db.open();
  // ... your code
  await db.close();
}
```

## License

MIT
