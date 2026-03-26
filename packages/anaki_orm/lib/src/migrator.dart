import 'dart:io';

import 'db.dart';
import 'driver.dart';

/// SQL-first migration runner for AnakiORM.
///
/// Reads `.sql` files from a directory and executes them in order.
/// Tracks applied migrations in a `_anaki_migrations` table.
///
/// ```dart
/// await db.open();
/// await Migrator(db).run('migrations/');
/// ```
///
/// Migration files should be named with a numeric prefix:
/// ```
/// migrations/
///   001_create_users.sql
///   002_add_email_index.sql
///   003_create_orders.sql
/// ```
class Migrator {
  final AnakiDb _db;

  /// Creates a migrator bound to the given [AnakiDb] instance.
  Migrator(this._db);

  /// Runs all pending migrations from [migrationsDir].
  ///
  /// Creates the tracking table if it doesn't exist, then executes
  /// each `.sql` file that hasn't been applied yet, in alphabetical order.
  Future<List<String>> run(String migrationsDir) async {
    await _ensureTrackingTable();

    final applied = await _getAppliedMigrations();
    final files = _listMigrationFiles(migrationsDir);
    final pending = files.where((f) => !applied.contains(f.name)).toList();

    final executed = <String>[];
    for (final file in pending) {
      final content = await file.readAsString();
      final statements = content
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty);
      for (final sql in statements) {
        await _db.execute(sql);
      }
      await _recordMigration(file.name);
      executed.add(file.name);
    }

    return executed;
  }

  /// Returns the list of already-applied migration names.
  Future<List<String>> getAppliedMigrations() async {
    await _ensureTrackingTable();
    return _getAppliedMigrations();
  }

  Future<void> _ensureTrackingTable() async {
    final String ddl;
    switch (_db.dialect) {
      case SqlDialect.mssql:
        ddl = '''
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '_anaki_migrations')
CREATE TABLE _anaki_migrations (
  id INT IDENTITY(1,1) PRIMARY KEY,
  name NVARCHAR(255) NOT NULL UNIQUE,
  applied_at DATETIME2 DEFAULT GETDATE()
)''';
      case SqlDialect.sqlite:
        ddl = '''
CREATE TABLE IF NOT EXISTS _anaki_migrations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)''';
      case SqlDialect.generic:
        ddl = '''
CREATE TABLE IF NOT EXISTS _anaki_migrations (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)''';
    }
    await _db.execute(ddl);
  }

  Future<List<String>> _getAppliedMigrations() async {
    final rows = await _db.query<Map<String, dynamic>>(
      'SELECT name FROM _anaki_migrations ORDER BY name',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> _recordMigration(String name) async {
    await _db.execute('INSERT INTO _anaki_migrations (name) VALUES (@name)', {
      'name': name,
    });
  }

  List<File> _listMigrationFiles(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      throw ArgumentError('Migrations directory not found: $dirPath');
    }

    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort(
            (a, b) =>
                a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last),
          );

    return files;
  }
}

extension on File {
  String get name => uri.pathSegments.last;
}
