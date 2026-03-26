// Integration test for Migrator with SQLite.
//
// PREREQUISITES:
// 1. Build the Rust native library:
//    ./scripts/build_native.sh sqlite --local
//
// Run with:
//    dart test test/migrator_integration_test.dart

import 'dart:io';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_sqlite/anaki_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late AnakiDb db;
  late String testDbPath;
  late Directory migrationsDir;

  setUp(() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    testDbPath = '${Directory.systemTemp.path}/anaki_migrator_test_$ts.db';
    db = AnakiDb(SqliteDriver(testDbPath));
    await db.open();

    // Create temp migrations directory
    migrationsDir = Directory('${Directory.systemTemp.path}/anaki_migrations_$ts');
    migrationsDir.createSync(recursive: true);
  });

  tearDown(() async {
    await db.close();
    File(testDbPath).deleteSync();
    if (migrationsDir.existsSync()) {
      migrationsDir.deleteSync(recursive: true);
    }
  });

  test('run() creates tracking table and applies migrations', () async {
    // Write migration files
    File('${migrationsDir.path}/001_create_users.sql').writeAsStringSync('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    File('${migrationsDir.path}/002_add_email.sql').writeAsStringSync('''
      ALTER TABLE users ADD COLUMN email TEXT
    ''');

    final migrator = Migrator(db);
    final executed = await migrator.run(migrationsDir.path);

    expect(executed, hasLength(2));
    expect(executed[0], equals('001_create_users.sql'));
    expect(executed[1], equals('002_add_email.sql'));

    // Verify tables were created
    await db.execute(
      'INSERT INTO users (name, email) VALUES (@name, @email)',
      {'name': 'Ana', 'email': 'ana@test.com'},
    );
    final rows = await db.query<Map<String, dynamic>>('SELECT * FROM users');
    expect(rows, hasLength(1));
    expect(rows.first['email'], equals('ana@test.com'));
  });

  test('run() skips already applied migrations', () async {
    File('${migrationsDir.path}/001_create_items.sql').writeAsStringSync('''
      CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)
    ''');

    final migrator = Migrator(db);

    // First run
    final first = await migrator.run(migrationsDir.path);
    expect(first, hasLength(1));

    // Add a second migration
    File('${migrationsDir.path}/002_add_price.sql').writeAsStringSync('''
      ALTER TABLE items ADD COLUMN price REAL
    ''');

    // Second run — should only apply the new one
    final second = await migrator.run(migrationsDir.path);
    expect(second, hasLength(1));
    expect(second.first, equals('002_add_price.sql'));
  });

  test('run() returns empty list when no pending migrations', () async {
    File('${migrationsDir.path}/001_create_things.sql').writeAsStringSync('''
      CREATE TABLE things (id INTEGER PRIMARY KEY)
    ''');

    final migrator = Migrator(db);
    await migrator.run(migrationsDir.path);

    // Run again — nothing to apply
    final result = await migrator.run(migrationsDir.path);
    expect(result, isEmpty);
  });

  test('getAppliedMigrations() returns list of applied names', () async {
    File('${migrationsDir.path}/001_first.sql').writeAsStringSync('''
      CREATE TABLE first_table (id INTEGER PRIMARY KEY)
    ''');
    File('${migrationsDir.path}/002_second.sql').writeAsStringSync('''
      CREATE TABLE second_table (id INTEGER PRIMARY KEY)
    ''');

    final migrator = Migrator(db);
    await migrator.run(migrationsDir.path);

    final applied = await migrator.getAppliedMigrations();
    expect(applied, hasLength(2));
    expect(applied, contains('001_first.sql'));
    expect(applied, contains('002_second.sql'));
  });

  test('run() throws on missing directory', () async {
    final migrator = Migrator(db);
    expect(
      () => migrator.run('/nonexistent/path'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('migrations execute in alphabetical order', () async {
    // Create files intentionally out of order
    File('${migrationsDir.path}/003_third.sql').writeAsStringSync('''
      CREATE TABLE third (id INTEGER PRIMARY KEY)
    ''');
    File('${migrationsDir.path}/001_first.sql').writeAsStringSync('''
      CREATE TABLE first (id INTEGER PRIMARY KEY)
    ''');
    File('${migrationsDir.path}/002_second.sql').writeAsStringSync('''
      CREATE TABLE second (id INTEGER PRIMARY KEY)
    ''');

    final migrator = Migrator(db);
    final executed = await migrator.run(migrationsDir.path);

    expect(executed[0], equals('001_first.sql'));
    expect(executed[1], equals('002_second.sql'));
    expect(executed[2], equals('003_third.sql'));
  });
}
