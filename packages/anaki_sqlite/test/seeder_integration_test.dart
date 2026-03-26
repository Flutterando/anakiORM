// Integration test for Seeder with SQLite.
//
// PREREQUISITES:
// 1. Build the Rust native library:
//    ./scripts/build_native.sh sqlite --local
//
// Run with:
//    dart test test/seeder_integration_test.dart

import 'dart:io';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_sqlite/anaki_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late AnakiDb db;
  late String testDbPath;
  late Directory seedsDir;

  setUp(() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    testDbPath = '${Directory.systemTemp.path}/anaki_seeder_test_$ts.db';
    db = AnakiDb(SqliteDriver(testDbPath));
    await db.open();

    // Create the table that seeds will populate
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT
      )
    ''');

    // Create temp seeds directory
    seedsDir = Directory('${Directory.systemTemp.path}/anaki_seeds_$ts');
    seedsDir.createSync(recursive: true);
  });

  tearDown(() async {
    await db.close();
    File(testDbPath).deleteSync();
    if (seedsDir.existsSync()) {
      seedsDir.deleteSync(recursive: true);
    }
  });

  test('run() creates tracking table and applies seeds', () async {
    File('${seedsDir.path}/001_seed_users.sql').writeAsStringSync('''
      INSERT INTO users (name, email) VALUES ('Ana', 'ana@test.com');
      INSERT INTO users (name, email) VALUES ('Bob', 'bob@test.com');
    ''');

    final seeder = Seeder(db);
    final executed = await seeder.run(seedsDir.path);

    expect(executed, hasLength(1));
    expect(executed[0], equals('001_seed_users.sql'));

    final rows = await db.query<Map<String, dynamic>>('SELECT * FROM users');
    expect(rows, hasLength(2));
    expect(rows[0]['name'], equals('Ana'));
    expect(rows[1]['name'], equals('Bob'));
  });

  test('run() skips already applied seeds', () async {
    File('${seedsDir.path}/001_seed_users.sql').writeAsStringSync('''
      INSERT INTO users (name, email) VALUES ('Ana', 'ana@test.com');
    ''');

    final seeder = Seeder(db);

    // First run
    final first = await seeder.run(seedsDir.path);
    expect(first, hasLength(1));

    // Add a second seed
    File('${seedsDir.path}/002_seed_admins.sql').writeAsStringSync('''
      INSERT INTO users (name, email) VALUES ('Admin', 'admin@test.com');
    ''');

    // Second run — should only apply the new one
    final second = await seeder.run(seedsDir.path);
    expect(second, hasLength(1));
    expect(second.first, equals('002_seed_admins.sql'));

    final rows = await db.query<Map<String, dynamic>>('SELECT * FROM users ORDER BY id');
    expect(rows, hasLength(2));
  });

  test('run() returns empty list when no pending seeds', () async {
    File('${seedsDir.path}/001_seed_data.sql').writeAsStringSync('''
      INSERT INTO users (name) VALUES ('Test');
    ''');

    final seeder = Seeder(db);
    await seeder.run(seedsDir.path);

    // Run again — nothing to apply
    final result = await seeder.run(seedsDir.path);
    expect(result, isEmpty);
  });

  test('getAppliedSeeds() returns list of applied names', () async {
    File('${seedsDir.path}/001_first.sql').writeAsStringSync('''
      INSERT INTO users (name) VALUES ('First');
    ''');
    File('${seedsDir.path}/002_second.sql').writeAsStringSync('''
      INSERT INTO users (name) VALUES ('Second');
    ''');

    final seeder = Seeder(db);
    await seeder.run(seedsDir.path);

    final applied = await seeder.getAppliedSeeds();
    expect(applied, hasLength(2));
    expect(applied, contains('001_first.sql'));
    expect(applied, contains('002_second.sql'));
  });

  test('run() throws on missing directory', () async {
    final seeder = Seeder(db);
    expect(
      () => seeder.run('/nonexistent/path'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('seeds execute in alphabetical order', () async {
    // Create files intentionally out of order
    File('${seedsDir.path}/003_third.sql').writeAsStringSync('''
      INSERT INTO users (name) VALUES ('Third');
    ''');
    File('${seedsDir.path}/001_first.sql').writeAsStringSync('''
      INSERT INTO users (name) VALUES ('First');
    ''');
    File('${seedsDir.path}/002_second.sql').writeAsStringSync('''
      INSERT INTO users (name) VALUES ('Second');
    ''');

    final seeder = Seeder(db);
    final executed = await seeder.run(seedsDir.path);

    expect(executed[0], equals('001_first.sql'));
    expect(executed[1], equals('002_second.sql'));
    expect(executed[2], equals('003_third.sql'));

    final rows = await db.query<Map<String, dynamic>>(
      'SELECT name FROM users ORDER BY id',
    );
    expect(rows[0]['name'], equals('First'));
    expect(rows[1]['name'], equals('Second'));
    expect(rows[2]['name'], equals('Third'));
  });
}
