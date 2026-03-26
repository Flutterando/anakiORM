import 'package:anaki_orm/anaki_orm.dart';
import 'package:test/test.dart';

/// Simple DTO for testing.
class UserDTO {
  final int? id;
  final String name;
  final String? email;
  final bool active;

  UserDTO({this.id, required this.name, this.email, this.active = true});

  factory UserDTO.fromJson(Map<String, dynamic> json) => UserDTO(
    id: json['id'] as int?,
    name: json['name'] as String,
    email: json['email'] as String?,
    active: json['active'] == 1 || json['active'] == true,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'email': email,
    'active': active ? 1 : 0,
  };
}

/// Mock driver that stores data in memory for testing.
class MockDriver implements AnakiDriver {
  List<Map<String, dynamic>> mockRows = [];
  int executeResult = 1;
  bool _isOpen = false;
  var inTransaction = false;
  final List<String> callLog = [];
  final SqlDialect _dialect;

  MockDriver({
    this.mockRows = const [],
    SqlDialect dialect = SqlDialect.generic,
  }) : _dialect = dialect;

  @override
  SqlDialect get dialect => _dialect;

  @override
  Future<void> rawOpen() async {
    _isOpen = true;
  }

  @override
  Future<void> rawClose() async {
    _isOpen = false;
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql,
    Map<String, dynamic>? params,
  ) async {
    callLog.add('rawQuery:$sql');
    return List.from(mockRows);
  }

  @override
  Future<int> rawExecute(String sql, Map<String, dynamic>? params) async {
    callLog.add('rawExecute:$sql');
    return executeResult;
  }

  @override
  Future<int> rawExecuteBatch(
    String sql,
    List<Map<String, dynamic>> paramsList,
  ) async {
    callLog.add('rawExecuteBatch:$sql:${paramsList.length}');
    return executeResult * paramsList.length;
  }

  @override
  Future<void> rawBeginTransaction() async {
    inTransaction = true;
  }

  @override
  Future<void> rawCommit() async {
    inTransaction = false;
  }

  @override
  Future<void> rawRollback() async {
    inTransaction = false;
  }

  @override
  Future<bool> rawPing() async => _isOpen;
}

/// Test RowAdapter using a type registry.
RowAdapter _createTestAdapter() {
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
  late MockDriver driver;
  late AnakiDb db;
  late RowAdapter adapter;
  late AnakiQueryBuilder users;

  setUp(() async {
    driver = MockDriver();
    db = AnakiDb(driver);
    adapter = _createTestAdapter();
    users = AnakiQueryBuilder(db, adapter);
    await db.open();
  });

  group('RowAdapter', () {
    test('fromJson converts Map to typed object', () {
      final user = adapter.fromJson<UserDTO>({
        'id': 1,
        'name': 'Ana',
        'active': 1,
      });
      expect(user, isA<UserDTO>());
      expect(user.name, equals('Ana'));
      expect(user.id, equals(1));
    });

    test('toJson converts typed object to Map', () {
      final map = adapter.toJson<UserDTO>(UserDTO(name: 'Ana', email: 'a@b.c'));
      expect(map['name'], equals('Ana'));
      expect(map['email'], equals('a@b.c'));
    });

    test('throws on unregistered type', () {
      expect(
        () => adapter.fromJson<String>({'key': 'value'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SelectBuilder.build()', () {
    test('basic select *', () {
      final (sql, params) = users.select<UserDTO>('users').build();
      expect(sql, equals('SELECT * FROM users'));
      expect(params, isEmpty);
    });

    test('select with columns', () {
      final (sql, _) = users.select<UserDTO>('users').columns([
        'id',
        'name',
      ]).build();
      expect(sql, equals('SELECT id, name FROM users'));
    });

    test('select with single column', () {
      final (sql, _) = users.select<UserDTO>('users').column('name').build();
      expect(sql, equals('SELECT name FROM users'));
    });

    test('select distinct', () {
      final (sql, _) = users
          .select<UserDTO>('users')
          .distinct()
          .column('name')
          .build();
      expect(sql, equals('SELECT DISTINCT name FROM users'));
    });

    test('where clause', () {
      final (sql, params) = users.select<UserDTO>('users').where(
        'active = @active',
        {'active': true},
      ).build();
      expect(sql, equals('SELECT * FROM users WHERE active = @active'));
      expect(params['active'], isTrue);
    });

    test('multiple where clauses (AND)', () {
      final (sql, params) = users
          .select<UserDTO>('users')
          .where('active = @active', {'active': true})
          .where('name = @name', {'name': 'Ana'})
          .build();
      expect(
        sql,
        equals('SELECT * FROM users WHERE active = @active AND name = @name'),
      );
      expect(params['active'], isTrue);
      expect(params['name'], equals('Ana'));
    });

    test('orWhere clause', () {
      final (sql, _) = users
          .select<UserDTO>('users')
          .where('active = @active', {'active': true})
          .orWhere('role = @role', {'role': 'admin'})
          .build();
      expect(
        sql,
        equals('SELECT * FROM users WHERE (active = @active OR role = @role)'),
      );
    });

    test('orderBy', () {
      final (sql, _) = users.select<UserDTO>('users').orderBy('name').build();
      expect(sql, equals('SELECT * FROM users ORDER BY name'));
    });

    test('orderBy desc', () {
      final (sql, _) = users
          .select<UserDTO>('users')
          .orderBy('created_at', desc: true)
          .build();
      expect(sql, equals('SELECT * FROM users ORDER BY created_at DESC'));
    });

    test('multiple orderBy', () {
      final (sql, _) = users
          .select<UserDTO>('users')
          .orderBy('name')
          .orderBy('id', desc: true)
          .build();
      expect(sql, equals('SELECT * FROM users ORDER BY name, id DESC'));
    });

    test('groupBy', () {
      final (sql, _) = users
          .select<UserDTO>('users')
          .column('active')
          .groupBy('active')
          .build();
      expect(sql, equals('SELECT active FROM users GROUP BY active'));
    });

    test('having', () {
      final (sql, params) = users
          .select<UserDTO>('users')
          .column('active')
          .column('COUNT(*)')
          .groupBy('active')
          .having('COUNT(*) > @min', {'min': 5})
          .build();
      expect(
        sql,
        equals(
          'SELECT active, COUNT(*) FROM users GROUP BY active HAVING COUNT(*) > @min',
        ),
      );
      expect(params['min'], equals(5));
    });

    test('limit', () {
      final (sql, _) = users.select<UserDTO>('users').limit(10).build();
      expect(sql, equals('SELECT * FROM users LIMIT 10'));
    });

    test('limit and offset', () {
      final (sql, _) = users
          .select<UserDTO>('users')
          .limit(10)
          .offset(20)
          .build();
      expect(sql, equals('SELECT * FROM users LIMIT 10 OFFSET 20'));
    });

    test('join', () {
      final (sql, _) = users
          .select<UserDTO>('users')
          .join('orders', 'orders.user_id = users.id')
          .build();
      expect(
        sql,
        equals(
          'SELECT * FROM users INNER JOIN orders ON orders.user_id = users.id',
        ),
      );
    });

    test('leftJoin', () {
      final (sql, _) = users
          .select<UserDTO>('users')
          .leftJoin('orders', 'orders.user_id = users.id')
          .build();
      expect(
        sql,
        equals(
          'SELECT * FROM users LEFT JOIN orders ON orders.user_id = users.id',
        ),
      );
    });

    test('complex query', () {
      final (sql, params) = users
          .select<UserDTO>('users')
          .columns(['u.id', 'u.name', 'COUNT(o.id) as order_count'])
          .join('orders o', 'o.user_id = u.id')
          .where('u.active = @active', {'active': true})
          .groupBy('u.id')
          .groupBy('u.name')
          .having('COUNT(o.id) > @min', {'min': 3})
          .orderBy('order_count', desc: true)
          .limit(10)
          .build();
      expect(sql, contains('INNER JOIN orders o ON o.user_id = u.id'));
      expect(sql, contains('WHERE u.active = @active'));
      expect(sql, contains('GROUP BY u.id, u.name'));
      expect(sql, contains('HAVING COUNT(o.id) > @min'));
      expect(sql, contains('ORDER BY order_count DESC'));
      expect(sql, contains('LIMIT 10'));
      expect(params['active'], isTrue);
      expect(params['min'], equals(3));
    });
  });

  group('SelectBuilder MSSQL dialect', () {
    late AnakiQueryBuilder mssqlUsers;

    setUp(() async {
      final mssqlDriver = MockDriver(dialect: SqlDialect.mssql);
      final mssqlDb = AnakiDb(mssqlDriver);
      await mssqlDb.open();
      mssqlUsers = AnakiQueryBuilder(mssqlDb, adapter);
    });

    test('limit uses OFFSET/FETCH', () {
      final (sql, _) = mssqlUsers.select<UserDTO>('users').limit(10).build();
      expect(sql, contains('OFFSET 0 ROWS'));
      expect(sql, contains('FETCH NEXT 10 ROWS ONLY'));
    });

    test('limit and offset uses OFFSET/FETCH', () {
      final (sql, _) = mssqlUsers
          .select<UserDTO>('users')
          .limit(10)
          .offset(20)
          .build();
      expect(sql, contains('OFFSET 20 ROWS'));
      expect(sql, contains('FETCH NEXT 10 ROWS ONLY'));
    });
  });

  group('SelectBuilder execution', () {
    setUp(() {
      driver.mockRows = [
        {'id': 1, 'name': 'Ana', 'email': 'ana@test.com', 'active': 1},
        {'id': 2, 'name': 'Bob', 'email': 'bob@test.com', 'active': 1},
      ];
    });

    test('list() returns mapped objects', () async {
      final result = await users.select<UserDTO>('users').list();
      expect(result, hasLength(2));
      expect(result[0], isA<UserDTO>());
      expect(result[0].name, equals('Ana'));
      expect(result[1].name, equals('Bob'));
    });

    test('first() returns first mapped object', () async {
      final result = await users.select<UserDTO>('users').first();
      expect(result, isNotNull);
      expect(result!.name, equals('Ana'));
    });

    test('first() returns null when empty', () async {
      driver.mockRows = [];
      final result = await users.select<UserDTO>('users').first();
      expect(result, isNull);
    });

    test('scalar() returns single value', () async {
      driver.mockRows = [
        {'count': 42},
      ];
      final count = await users
          .select<UserDTO>('users')
          .column('COUNT(*)')
          .scalar<int>();
      expect(count, equals(42));
    });

    test('count() returns count', () async {
      driver.mockRows = [
        {'COUNT(*)': 42},
      ];
      final count = await users.select<UserDTO>('users').count();
      expect(count, equals(42));
    });

    test('list() sends correct SQL to driver', () async {
      await users
          .select<UserDTO>('users')
          .columns(['id', 'name'])
          .where('active = @active', {'active': true})
          .orderBy('name')
          .limit(5)
          .list();
      expect(
        driver.callLog.last,
        equals(
          'rawQuery:SELECT id, name FROM users WHERE active = @active ORDER BY name LIMIT 5',
        ),
      );
    });
  });

  group('InsertBuilder', () {
    test('build() with values', () {
      final (sql, params) = users.insert<UserDTO>('users').values({
        'name': 'Ana',
        'email': 'ana@test.com',
      }).build();
      expect(
        sql,
        equals('INSERT INTO users (name, email) VALUES (@name, @email)'),
      );
      expect(params['name'], equals('Ana'));
      expect(params['email'], equals('ana@test.com'));
    });

    test('build() with entity', () {
      final user = UserDTO(name: 'Ana', email: 'ana@test.com');
      final (sql, params) = users.insert<UserDTO>('users').entity(user).build();
      expect(sql, contains('INSERT INTO users'));
      expect(params['name'], equals('Ana'));
      expect(params['email'], equals('ana@test.com'));
    });

    test('build() throws without values', () {
      expect(
        () => users.insert<UserDTO>('users').build(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('run() executes and returns affected', () async {
      driver.executeResult = 1;
      final affected = await users.insert<UserDTO>('users').values({
        'name': 'Ana',
        'email': 'ana@test.com',
      }).run();
      expect(affected, equals(1));
      expect(driver.callLog.last, contains('rawExecute:INSERT INTO users'));
    });
  });

  group('UpdateBuilder', () {
    test('build() with set and where', () {
      final (sql, params) = users
          .update('users')
          .set({'email': 'new@test.com'})
          .where('id = @id', {'id': 1})
          .build();
      expect(sql, equals('UPDATE users SET email = @email WHERE id = @id'));
      expect(params['email'], equals('new@test.com'));
      expect(params['id'], equals(1));
    });

    test('build() with multiple set values', () {
      final (sql, params) = users
          .update('users')
          .set({'name': 'Ana Maria', 'email': 'new@test.com'})
          .where('id = @id', {'id': 1})
          .build();
      expect(sql, contains('name = @name'));
      expect(sql, contains('email = @email'));
      expect(params['name'], equals('Ana Maria'));
    });

    test('build() throws without set values', () {
      expect(
        () => users.update('users').where('id = @id', {'id': 1}).build(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('build() without where (update all)', () {
      final (sql, _) = users.update('users').set({'active': 0}).build();
      expect(sql, equals('UPDATE users SET active = @active'));
    });

    test('run() executes and returns affected', () async {
      driver.executeResult = 1;
      final affected = await users
          .update('users')
          .set({'name': 'New Name'})
          .where('id = @id', {'id': 1})
          .run();
      expect(affected, equals(1));
      expect(driver.callLog.last, contains('rawExecute:UPDATE users'));
    });
  });

  group('DeleteBuilder', () {
    test('build() with where', () {
      final (sql, params) = users.delete('users').where('id = @id', {
        'id': 1,
      }).build();
      expect(sql, equals('DELETE FROM users WHERE id = @id'));
      expect(params['id'], equals(1));
    });

    test('build() without where (delete all)', () {
      final (sql, params) = users.delete('users').build();
      expect(sql, equals('DELETE FROM users'));
      expect(params, isEmpty);
    });

    test('multiple where clauses', () {
      final (sql, _) = users
          .delete('users')
          .where('active = @active', {'active': false})
          .where('created_at < @date', {'date': '2024-01-01'})
          .build();
      expect(
        sql,
        equals(
          'DELETE FROM users WHERE active = @active AND created_at < @date',
        ),
      );
    });

    test('run() executes and returns affected', () async {
      driver.executeResult = 5;
      final affected = await users.delete('users').where('active = @active', {
        'active': false,
      }).run();
      expect(affected, equals(5));
      expect(driver.callLog.last, contains('rawExecute:DELETE FROM users'));
    });
  });

  group('AnakiQueryBuilder reuse', () {
    test('same adapter works for multiple builders', () {
      final orders = AnakiQueryBuilder(db, adapter);
      final (userSql, _) = users.select<UserDTO>('users').build();
      final (orderSql, _) = orders.select<UserDTO>('orders').build();
      expect(userSql, contains('FROM users'));
      expect(orderSql, contains('FROM orders'));
    });

    test('builders are independent', () {
      final s1 = users.select<UserDTO>('users').where('id = @id', {'id': 1});
      final s2 = users.select<UserDTO>('users').where('name = @name', {
        'name': 'Ana',
      });
      final (sql1, _) = s1.build();
      final (sql2, _) = s2.build();
      expect(sql1, contains('id = @id'));
      expect(sql1, isNot(contains('name = @name')));
      expect(sql2, contains('name = @name'));
      expect(sql2, isNot(contains('id = @id')));
    });
  });
}
