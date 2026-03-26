import 'package:anaki_orm/anaki_orm.dart';
import 'package:test/test.dart';

/// Mock driver that stores data in memory for testing AnakiDb.
class MockDriver implements AnakiDriver {
  final List<Map<String, dynamic>> _mockRows;
  int _executeResult;
  bool _isOpen = false;
  // ignore: unused_field
  bool _inTransaction = false;
  final List<String> callLog = [];

  @override
  SqlDialect get dialect => SqlDialect.generic;

  MockDriver({List<Map<String, dynamic>>? mockRows, int executeResult = 1})
    : _mockRows = mockRows ?? [],
      _executeResult = executeResult;

  set mockRows(List<Map<String, dynamic>> rows) => _mockRows
    ..clear()
    ..addAll(rows);

  set executeResult(int value) => _executeResult = value;

  @override
  Future<void> rawOpen() async {
    callLog.add('rawOpen');
    _isOpen = true;
  }

  @override
  Future<void> rawClose() async {
    callLog.add('rawClose');
    _isOpen = false;
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql,
    Map<String, dynamic>? params,
  ) async {
    callLog.add('rawQuery:$sql');
    return List.from(_mockRows);
  }

  @override
  Future<int> rawExecute(String sql, Map<String, dynamic>? params) async {
    callLog.add('rawExecute:$sql');
    return _executeResult;
  }

  @override
  Future<int> rawExecuteBatch(
    String sql,
    List<Map<String, dynamic>> paramsList,
  ) async {
    callLog.add('rawExecuteBatch:$sql:${paramsList.length}');
    return _executeResult * paramsList.length;
  }

  @override
  Future<void> rawBeginTransaction() async {
    callLog.add('rawBeginTransaction');
    _inTransaction = true;
  }

  @override
  Future<void> rawCommit() async {
    callLog.add('rawCommit');
    _inTransaction = false;
  }

  @override
  Future<void> rawRollback() async {
    callLog.add('rawRollback');
    _inTransaction = false;
  }

  @override
  Future<bool> rawPing() async {
    callLog.add('rawPing');
    return _isOpen;
  }
}

void main() {
  late MockDriver driver;
  late AnakiDb db;

  setUp(() {
    driver = MockDriver();
    db = AnakiDb(driver);
  });

  group('Connection lifecycle', () {
    test('open sets isOpen to true', () async {
      expect(db.isOpen, isFalse);
      await db.open();
      expect(db.isOpen, isTrue);
      expect(driver.callLog, contains('rawOpen'));
    });

    test('close sets isOpen to false', () async {
      await db.open();
      await db.close();
      expect(db.isOpen, isFalse);
      expect(driver.callLog, contains('rawClose'));
    });

    test('operations throw NotConnectedException when not open', () async {
      expect(() => db.query('SELECT 1'), throwsA(isA<NotConnectedException>()));
      expect(
        () => db.execute('INSERT INTO x VALUES (1)'),
        throwsA(isA<NotConnectedException>()),
      );
      expect(
        () => db.scalar<int>('SELECT COUNT(*) FROM x'),
        throwsA(isA<NotConnectedException>()),
      );
      expect(() => db.ping(), throwsA(isA<NotConnectedException>()));
    });
  });

  group('query', () {
    setUp(() async {
      driver.mockRows = [
        {'id': 1, 'name': 'Ana'},
        {'id': 2, 'name': 'Bob'},
      ];
      await db.open();
    });

    test('returns raw maps', () async {
      final rows = await db.query<Map<String, dynamic>>('SELECT * FROM users');
      expect(rows, hasLength(2));
      expect(rows[0]['name'], equals('Ana'));
      expect(rows[1]['name'], equals('Bob'));
    });

    test('maps rows with function', () async {
      final names = await db.query<String>(
        'SELECT * FROM users',
        null,
        (row) => row['name'] as String,
      );
      expect(names, equals(['Ana', 'Bob']));
    });

    test('passes params to driver', () async {
      await db.query('SELECT * FROM users WHERE id = @id', {'id': 1});
      expect(
        driver.callLog,
        contains('rawQuery:SELECT * FROM users WHERE id = @id'),
      );
    });
  });

  group('queryFirst', () {
    setUp(() async => await db.open());

    test('returns first row', () async {
      driver.mockRows = [
        {'id': 1, 'name': 'Ana'},
        {'id': 2, 'name': 'Bob'},
      ];
      final row = await db.queryFirst<Map<String, dynamic>>(
        'SELECT * FROM users',
      );
      expect(row, isNotNull);
      expect(row!['name'], equals('Ana'));
    });

    test('returns null when empty', () async {
      driver.mockRows = [];
      final row = await db.queryFirst<Map<String, dynamic>>(
        'SELECT * FROM users WHERE id = 999',
      );
      expect(row, isNull);
    });

    test('maps with function', () async {
      driver.mockRows = [
        {'id': 1, 'name': 'Ana'},
      ];
      final name = await db.queryFirst<String>(
        'SELECT * FROM users WHERE id = 1',
        null,
        (row) => row['name'] as String,
      );
      expect(name, equals('Ana'));
    });
  });

  group('execute', () {
    setUp(() async => await db.open());

    test('returns rows affected', () async {
      driver.executeResult = 3;
      final affected = await db.execute('DELETE FROM users WHERE active = 0');
      expect(affected, equals(3));
    });
  });

  group('executeBatch', () {
    setUp(() async => await db.open());

    test('returns total rows affected', () async {
      driver.executeResult = 1;
      final affected = await db.executeBatch(
        'INSERT INTO users (name) VALUES (@name)',
        [
          {'name': 'Ana'},
          {'name': 'Bob'},
          {'name': 'Carol'},
        ],
      );
      expect(affected, equals(3));
      expect(
        driver.callLog.last,
        equals('rawExecuteBatch:INSERT INTO users (name) VALUES (@name):3'),
      );
    });
  });

  group('scalar', () {
    setUp(() async => await db.open());

    test('returns single value', () async {
      driver.mockRows = [
        {'count': 42},
      ];
      final count = await db.scalar<int>('SELECT COUNT(*) FROM users');
      expect(count, equals(42));
    });

    test('returns null when empty', () async {
      driver.mockRows = [];
      final count = await db.scalar<int>('SELECT COUNT(*) FROM users');
      expect(count, isNull);
    });
  });

  group('queryPaged', () {
    setUp(() async {
      driver.mockRows = [
        {'id': 3, 'name': 'Carol'},
        {'id': 4, 'name': 'Dave'},
      ];
      await db.open();
    });

    test('returns PagedResult with correct metadata', () async {
      // The count query will return the mock rows, and the first value
      // will be used as total. We need to set up the mock properly.
      driver.mockRows = [
        {'_anaki_count': 10},
      ];

      final page = await db.queryPaged<Map<String, dynamic>>(
        'SELECT * FROM users',
        page: 2,
        pageSize: 5,
      );

      expect(page.page, equals(2));
      expect(page.pageSize, equals(5));
    });

    test('calculates totalPages correctly', () {
      final result = PagedResult(
        data: [1, 2, 3],
        total: 10,
        page: 1,
        pageSize: 3,
      );
      expect(result.totalPages, equals(4)); // ceil(10/3) = 4
      expect(result.hasNextPage, isTrue);
      expect(result.hasPreviousPage, isFalse);
    });

    test('hasPreviousPage on page > 1', () {
      final result = PagedResult(data: [1], total: 10, page: 2, pageSize: 5);
      expect(result.hasPreviousPage, isTrue);
    });
  });

  group('transaction', () {
    setUp(() async => await db.open());

    test('commits on success', () async {
      await db.transaction((tx) async {
        await tx.execute('UPDATE accounts SET balance = 100');
      });
      expect(driver.callLog, contains('rawBeginTransaction'));
      expect(driver.callLog, contains('rawCommit'));
      expect(driver.callLog, isNot(contains('rawRollback')));
    });

    test('rolls back on exception', () async {
      try {
        await db.transaction((tx) async {
          await tx.execute('UPDATE accounts SET balance = 100');
          throw Exception('Something went wrong');
        });
      } catch (_) {}
      expect(driver.callLog, contains('rawBeginTransaction'));
      expect(driver.callLog, contains('rawRollback'));
      expect(driver.callLog, isNot(contains('rawCommit')));
    });

    test('rethrows the original exception', () async {
      expect(
        () => db.transaction((tx) async {
          throw FormatException('bad data');
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ping', () {
    test('returns true when open', () async {
      await db.open();
      final alive = await db.ping();
      expect(alive, isTrue);
    });
  });

  group('Exceptions', () {
    test('AnakiException toString', () {
      const e = AnakiException('test error', details: 'some details');
      expect(e.toString(), contains('test error'));
      expect(e.toString(), contains('some details'));
    });

    test('ConnectionException toString', () {
      const e = ConnectionException('conn failed');
      expect(e.toString(), contains('ConnectionException'));
      expect(e.toString(), contains('conn failed'));
    });

    test('QueryException toString with sql', () {
      const e = QueryException('bad query', sql: 'SELECT * FROM x');
      expect(e.toString(), contains('QueryException'));
      expect(e.toString(), contains('SELECT * FROM x'));
    });

    test('TransactionException toString', () {
      const e = TransactionException('tx failed');
      expect(e.toString(), contains('TransactionException'));
    });

    test('NotConnectedException has helpful message', () {
      const e = NotConnectedException();
      expect(e.toString(), contains('open()'));
    });
  });
}
