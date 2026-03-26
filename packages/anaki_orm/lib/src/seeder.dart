import 'dart:io';

import 'db.dart';
import 'driver.dart';

/// SQL-first seed runner for AnakiORM.
///
/// Reads `.sql` files from a directory and executes them in order.
/// Tracks applied seeds in a `_anaki_seeds` table so each file runs only once.
///
/// ```dart
/// await db.open();
/// await Seeder(db).run('seeds/');
/// ```
///
/// Seed files should be named with a numeric prefix:
/// ```
/// seeds/
///   001_seed_users.sql
///   002_seed_products.sql
/// ```
class Seeder {
  final AnakiDb _db;

  /// Creates a seeder bound to the given [AnakiDb] instance.
  Seeder(this._db);

  /// Runs all pending seed files from [seedsDir].
  ///
  /// Creates the tracking table if it doesn't exist, then executes
  /// each `.sql` file that hasn't been applied yet, in alphabetical order.
  Future<List<String>> run(String seedsDir) async {
    await _ensureTrackingTable();

    final applied = await _getAppliedSeeds();
    final files = _listSeedFiles(seedsDir);
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
      await _recordSeed(file.name);
      executed.add(file.name);
    }

    return executed;
  }

  /// Returns the list of already-applied seed names.
  Future<List<String>> getAppliedSeeds() async {
    await _ensureTrackingTable();
    return _getAppliedSeeds();
  }

  Future<void> _ensureTrackingTable() async {
    final String ddl;
    switch (_db.dialect) {
      case SqlDialect.mssql:
        ddl = '''
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = '_anaki_seeds')
CREATE TABLE _anaki_seeds (
  id INT IDENTITY(1,1) PRIMARY KEY,
  name NVARCHAR(255) NOT NULL UNIQUE,
  applied_at DATETIME2 DEFAULT GETDATE()
)''';
      case SqlDialect.sqlite:
        ddl = '''
CREATE TABLE IF NOT EXISTS _anaki_seeds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)''';
      case SqlDialect.generic:
        ddl = '''
CREATE TABLE IF NOT EXISTS _anaki_seeds (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL UNIQUE,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)''';
    }
    await _db.execute(ddl);
  }

  Future<List<String>> _getAppliedSeeds() async {
    final rows = await _db.query<Map<String, dynamic>>(
      'SELECT name FROM _anaki_seeds ORDER BY name',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> _recordSeed(String name) async {
    await _db.execute('INSERT INTO _anaki_seeds (name) VALUES (@name)', {
      'name': name,
    });
  }

  List<File> _listSeedFiles(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      throw ArgumentError('Seeds directory not found: $dirPath');
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
