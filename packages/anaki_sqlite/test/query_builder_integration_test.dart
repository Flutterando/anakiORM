// Integration test for AnakiQueryBuilder with SQLite.
//
// PREREQUISITES:
// 1. Build the Rust native library:
//    ./scripts/build_native.sh sqlite --local
// 2. Copy or symlink the built library to this package's native_libs/ directory.
//
// Run with:
//    dart test test/query_builder_integration_test.dart

import 'dart:io';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_sqlite/anaki_sqlite.dart';
import 'package:test/test.dart';

/// Simple DTO for testing.
class UserDTO {
  final int? id;
  final String name;
  final String? email;
  final int? age;
  final int active;

  UserDTO({this.id, required this.name, this.email, this.age, this.active = 1});

  factory UserDTO.fromJson(Map<String, dynamic> json) => UserDTO(
    id: json['id'] as int?,
    name: json['name'] as String,
    email: json['email'] as String?,
    age: json['age'] as int?,
    active: json['active'] as int? ?? 1,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'email': email,
    'age': age,
    'active': active,
  };
}

/// Test RowAdapter using a type registry.
RowAdapter _createAdapter() {
  final fromMap = <Type, Function>{
    UserDTO: (Map<String, dynamic> row) => UserDTO.fromJson(row),
  };
  final toMap = <Type, Function>{UserDTO: (UserDTO entity) => entity.toJson()};

  return RowAdapter(
    <T>(Map<String, dynamic> row) {
      final fn = fromMap[T];
      if (fn == null) throw ArgumentError('No fromJson for $T');
      return fn(row) as T;
    },
    <T>(T entity) {
      final fn = toMap[T];
      if (fn == null) throw ArgumentError('No toJson for $T');
      return fn(entity) as Map<String, dynamic>;
    },
  );
}

void main() {
  late AnakiDb db;
  late RowAdapter adapter;
  late AnakiQueryBuilder users;

  final testDbPath =
      '${Directory.systemTemp.path}/anaki_qb_test_${DateTime.now().millisecondsSinceEpoch}.db';

  setUpAll(() async {
    db = AnakiDb(SqliteDriver(testDbPath));
    await db.open();

    adapter = _createAdapter();
    users = AnakiQueryBuilder(db, adapter);

    // Create test table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT,
        age INTEGER,
        active INTEGER DEFAULT 1
      )
    ''');

    // Seed data
    await db.executeBatch(
      'INSERT INTO users (name, email, age, active) VALUES (@name, @email, @age, @active)',
      [
        {'name': 'Ana', 'email': 'ana@test.com', 'age': 28, 'active': 1},
        {'name': 'Bob', 'email': 'bob@test.com', 'age': 35, 'active': 1},
        {'name': 'Carol', 'email': 'carol@test.com', 'age': 22, 'active': 0},
        {'name': 'Dave', 'email': 'dave@test.com', 'age': 40, 'active': 1},
        {'name': 'Eve', 'email': 'eve@test.com', 'age': 30, 'active': 0},
      ],
    );
  });

  tearDownAll(() async {
    await db.close();
    final file = File(testDbPath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  });

  group('SelectBuilder', () {
    test('list() returns all users', () async {
      final result = await users.select<UserDTO>('users').list();
      expect(result, hasLength(5));
    });

    test('list() with where clause', () async {
      final result = await users.select<UserDTO>('users').where(
        'active = @active',
        {'active': 1},
      ).list();
      expect(result, hasLength(3));
      expect(result.every((u) => u.active == 1), isTrue);
    });

    test('list() with columns', () async {
      final result = await users
          .select<UserDTO>('users')
          .columns(['name', 'email'])
          .where('name = @name', {'name': 'Ana'})
          .list();
      expect(result, hasLength(1));
      expect(result.first.name, equals('Ana'));
    });

    test('list() with orderBy', () async {
      final result = await users.select<UserDTO>('users').orderBy('age').list();
      final ages = result.map((u) => u.age).toList();
      expect(ages, orderedEquals([22, 28, 30, 35, 40]));
    });

    test('list() with orderBy desc', () async {
      final result = await users
          .select<UserDTO>('users')
          .orderBy('age', desc: true)
          .list();
      final ages = result.map((u) => u.age).toList();
      expect(ages, orderedEquals([40, 35, 30, 28, 22]));
    });

    test('list() with limit', () async {
      final result = await users
          .select<UserDTO>('users')
          .orderBy('id')
          .limit(3)
          .list();
      expect(result, hasLength(3));
    });

    test('list() with limit and offset', () async {
      final all = await users.select<UserDTO>('users').orderBy('id').list();
      final page2 = await users
          .select<UserDTO>('users')
          .orderBy('id')
          .limit(2)
          .offset(2)
          .list();
      expect(page2, hasLength(2));
      expect(page2.first.name, equals(all[2].name));
    });

    test('first() returns single user', () async {
      final result = await users.select<UserDTO>('users').where(
        'name = @name',
        {'name': 'Bob'},
      ).first();
      expect(result, isNotNull);
      expect(result!.name, equals('Bob'));
      expect(result.age, equals(35));
    });

    test('first() returns null when no match', () async {
      final result = await users.select<UserDTO>('users').where(
        'name = @name',
        {'name': 'NonExistent'},
      ).first();
      expect(result, isNull);
    });

    test('count()', () async {
      final total = await users.select<UserDTO>('users').count();
      expect(total, equals(5));
    });

    test('count() with where', () async {
      final active = await users.select<UserDTO>('users').where(
        'active = @active',
        {'active': 1},
      ).count();
      expect(active, equals(3));
    });

    test('paged()', () async {
      final page = await users
          .select<UserDTO>('users')
          .orderBy('id')
          .paged(page: 1, pageSize: 2);
      expect(page.data, hasLength(2));
      expect(page.total, equals(5));
      expect(page.page, equals(1));
      expect(page.pageSize, equals(2));
      expect(page.totalPages, equals(3));
      expect(page.hasNextPage, isTrue);
    });

    test('paged() page 2', () async {
      final page1 = await users
          .select<UserDTO>('users')
          .orderBy('id')
          .paged(page: 1, pageSize: 2);
      final page2 = await users
          .select<UserDTO>('users')
          .orderBy('id')
          .paged(page: 2, pageSize: 2);
      expect(page2.data.first.name, isNot(equals(page1.data.first.name)));
      expect(page2.hasPreviousPage, isTrue);
    });
  });

  group('InsertBuilder', () {
    test('insert with values', () async {
      final affected = await users.insert<UserDTO>('users').values({
        'name': 'Frank',
        'email': 'frank@test.com',
        'age': 25,
        'active': 1,
      }).run();
      expect(affected, equals(1));

      final frank = await users.select<UserDTO>('users').where('name = @name', {
        'name': 'Frank',
      }).first();
      expect(frank, isNotNull);
      expect(frank!.email, equals('frank@test.com'));
    });

    test('insert with entity', () async {
      final user = UserDTO(name: 'Grace', email: 'grace@test.com', age: 33);
      final affected = await users.insert<UserDTO>('users').entity(user).run();
      expect(affected, equals(1));

      final grace = await users.select<UserDTO>('users').where('name = @name', {
        'name': 'Grace',
      }).first();
      expect(grace, isNotNull);
      expect(grace!.age, equals(33));
    });
  });

  group('UpdateBuilder', () {
    test('update with set and where', () async {
      final affected = await users
          .update('users')
          .set({'email': 'ana.updated@test.com'})
          .where('name = @name', {'name': 'Ana'})
          .run();
      expect(affected, equals(1));

      final ana = await users.select<UserDTO>('users').where('name = @name', {
        'name': 'Ana',
      }).first();
      expect(ana!.email, equals('ana.updated@test.com'));
    });
  });

  group('DeleteBuilder', () {
    test('delete with where', () async {
      // Insert a temp user to delete
      await users.insert<UserDTO>('users').values({
        'name': 'ToDelete',
        'active': 0,
      }).run();

      final affected = await users.delete('users').where('name = @name', {
        'name': 'ToDelete',
      }).run();
      expect(affected, equals(1));

      final deleted = await users.select<UserDTO>('users').where(
        'name = @name',
        {'name': 'ToDelete'},
      ).first();
      expect(deleted, isNull);
    });
  });
}
