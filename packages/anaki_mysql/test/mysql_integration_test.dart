// Integration test for anaki_mysql.
//
// PREREQUISITES:
// 1. Start MySQL (e.g. docker compose up from example/shelf_mysql_example)
// 2. Build the Rust native library:
//    ./scripts/build_native.sh mysql --local
//
// Run with:
//    dart test test/mysql_integration_test.dart

import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_mysql/anaki_mysql.dart';
import 'package:test/test.dart';

void main() {
  late AnakiDb db;

  setUpAll(() async {
    db = AnakiDb(MysqlDriver(
      host: 'localhost',
      port: 3306,
      username: 'anaki',
      password: 'anaki',
      database: 'anaki_test',
    ));
    await db.open();

    // Drop and create test table
    await db.execute('DROP TABLE IF EXISTS users');
    await db.execute('''
      CREATE TABLE users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        email VARCHAR(255),
        age INT,
        active TINYINT(1) DEFAULT 1
      )
    ''');
  });

  tearDownAll(() async {
    await db.execute('DROP TABLE IF EXISTS users');
    await db.close();
  });

  group('Connection', () {
    test('ping returns true', () async {
      final alive = await db.ping();
      expect(alive, isTrue);
    });
  });

  group('CRUD operations', () {
    test('INSERT and SELECT', () async {
      await db.execute(
        'INSERT INTO users (name, email, age) VALUES (@name, @email, @age)',
        {'name': 'Ana', 'email': 'ana@example.com', 'age': 28},
      );

      final rows = await db.query<Map<String, dynamic>>(
        'SELECT * FROM users WHERE name = @name',
        {'name': 'Ana'},
      );

      expect(rows, hasLength(1));
      expect(rows.first['name'], equals('Ana'));
      expect(rows.first['email'], equals('ana@example.com'));
      expect(rows.first['age'], equals(28));
    });

    test('UPDATE', () async {
      final affected = await db.execute(
        'UPDATE users SET email = @email WHERE name = @name',
        {'email': 'ana.new@example.com', 'name': 'Ana'},
      );
      expect(affected, equals(1));

      final row = await db.queryFirst<Map<String, dynamic>>(
        'SELECT email FROM users WHERE name = @name',
        {'name': 'Ana'},
      );
      expect(row!['email'], equals('ana.new@example.com'));
    });

    test('DELETE', () async {
      await db.execute(
        'INSERT INTO users (name) VALUES (@name)',
        {'name': 'ToDelete'},
      );

      final affected = await db.execute(
        'DELETE FROM users WHERE name = @name',
        {'name': 'ToDelete'},
      );
      expect(affected, equals(1));

      final row = await db.queryFirst<Map<String, dynamic>>(
        'SELECT * FROM users WHERE name = @name',
        {'name': 'ToDelete'},
      );
      expect(row, isNull);
    });
  });

  group('Scalar', () {
    test('returns single value', () async {
      final count = await db.scalar<int>('SELECT COUNT(*) FROM users');
      expect(count, isA<int>());
      expect(count, greaterThanOrEqualTo(1));
    });
  });

  group('Batch execute', () {
    test('inserts multiple rows', () async {
      final affected = await db.executeBatch(
        'INSERT INTO users (name, email) VALUES (@name, @email)',
        [
          {'name': 'Bob', 'email': 'bob@example.com'},
          {'name': 'Carol', 'email': 'carol@example.com'},
          {'name': 'Dave', 'email': 'dave@example.com'},
        ],
      );
      expect(affected, equals(3));
    });
  });

  group('Pagination', () {
    test('returns paged results', () async {
      final page = await db.queryPaged<Map<String, dynamic>>(
        'SELECT * FROM users ORDER BY id',
        page: 1,
        pageSize: 2,
      );

      expect(page.data, hasLength(2));
      expect(page.page, equals(1));
      expect(page.pageSize, equals(2));
      expect(page.total, greaterThanOrEqualTo(4));
      expect(page.hasNextPage, isTrue);
    });

    test('second page returns different rows', () async {
      final page1 = await db.queryPaged<Map<String, dynamic>>(
        'SELECT * FROM users ORDER BY id',
        page: 1,
        pageSize: 2,
      );
      final page2 = await db.queryPaged<Map<String, dynamic>>(
        'SELECT * FROM users ORDER BY id',
        page: 2,
        pageSize: 2,
      );

      expect(page1.data.first['id'], isNot(equals(page2.data.first['id'])));
    });
  });

  group('Transaction', () {
    test('commit persists data', () async {
      await db.transaction((tx) async {
        await tx.execute(
          'INSERT INTO users (name) VALUES (@name)',
          {'name': 'TxCommit'},
        );
      });

      final row = await db.queryFirst<Map<String, dynamic>>(
        'SELECT * FROM users WHERE name = @name',
        {'name': 'TxCommit'},
      );
      expect(row, isNotNull);
    });

    test('rollback reverts data', () async {
      try {
        await db.transaction((tx) async {
          await tx.execute(
            'INSERT INTO users (name) VALUES (@name)',
            {'name': 'TxRollback'},
          );
          throw Exception('Force rollback');
        });
      } catch (_) {}

      final row = await db.queryFirst<Map<String, dynamic>>(
        'SELECT * FROM users WHERE name = @name',
        {'name': 'TxRollback'},
      );
      expect(row, isNull);
    });
  });

  group('MySQL-specific types', () {
    test('TINYINT(1) is returned as bool', () async {
      final rows = await db.query<Map<String, dynamic>>(
        'SELECT * FROM users WHERE name = @name',
        {'name': 'Ana'},
      );
      expect(rows.first['active'], isA<bool>());
      expect(rows.first['active'], isTrue);
    });
  });

  group('Mapping with fromJson', () {
    test('maps rows to typed objects', () async {
      final users = await db.query(
        'SELECT * FROM users WHERE name = @name',
        {'name': 'Ana'},
        _UserDTO.fromJson,
      );

      expect(users, hasLength(1));
      expect(users.first, isA<_UserDTO>());
      expect(users.first.name, equals('Ana'));
    });
  });
}

/// Simple DTO for testing mapping.
class _UserDTO {
  final int id;
  final String name;
  final String? email;
  final int? age;

  _UserDTO({
    required this.id,
    required this.name,
    this.email,
    this.age,
  });

  factory _UserDTO.fromJson(Map<String, dynamic> json) => _UserDTO(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String?,
        age: json['age'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'age': age,
      };
}
