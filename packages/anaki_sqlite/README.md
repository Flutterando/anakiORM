# anaki_sqlite

SQLite driver for [Anaki ORM](https://github.com/Flutterando/anakiORM) — native performance via Rust FFI.

This package provides the SQLite database driver for Anaki ORM, enabling high-performance database operations through native Rust bindings.

## Documentation

For complete documentation, installation guides, API reference, and examples, please visit the main repository:

👉 **[https://github.com/Flutterando/anakiORM](https://github.com/Flutterando/anakiORM)**

## Quick Start

```yaml
dependencies:
  anaki_orm: ^0.1.0
  anaki_sqlite: ^0.1.0
```

```dart
import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_sqlite/anaki_sqlite.dart';

void main() async {
  final db = AnakiDb(SqliteDriver(':memory:'));
  await db.open();
  // ... your code
  await db.close();
}
```

## License

MIT
