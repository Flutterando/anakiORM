import 'package:anaki_mongodb/anaki_mongodb.dart';
import 'package:anaki_orm/anaki_orm.dart';
import 'package:test/test.dart';

/// In-memory fake driver capturing envelopes as decoded maps.
class FakeMongoDriver implements MongoDriverBase {
  final List<String> callLog = [];
  Map<String, dynamic>? lastEnvelope;
  List<Map<String, dynamic>>? lastBatchDocuments;
  List<Map<String, dynamic>> nextRows = [];
  int nextCount = 0;
  bool isOpen = false;

  @override
  Future<void> rawOpen() async {
    callLog.add('open');
    isOpen = true;
  }

  @override
  Future<void> rawClose() async {
    callLog.add('close');
    isOpen = false;
  }

  @override
  Future<bool> rawPing() async {
    callLog.add('ping');
    return isOpen;
  }

  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    Map<String, dynamic> envelope,
  ) async {
    callLog.add('query:${envelope['op']}');
    lastEnvelope = envelope;
    return nextRows;
  }

  @override
  Future<int> rawExecute(Map<String, dynamic> envelope) async {
    callLog.add('execute:${envelope['op']}');
    lastEnvelope = envelope;
    return nextCount;
  }

  @override
  Future<int> rawExecuteBatch(
    Map<String, dynamic> envelope,
    List<Map<String, dynamic>> documents,
  ) async {
    callLog.add('executeBatch:${documents.length}');
    lastEnvelope = envelope;
    lastBatchDocuments = documents;
    return documents.length;
  }

  @override
  Future<void> rawBeginTransaction() async => callLog.add('begin');

  @override
  Future<void> rawCommit() async => callLog.add('commit');

  @override
  Future<void> rawRollback() async => callLog.add('rollback');
}

void main() {
  late FakeMongoDriver driver;
  late AnakiMongoDb mongo;

  setUp(() async {
    driver = FakeMongoDriver();
    mongo = AnakiMongoDb(driver);
    await mongo.open();
  });

  group('Lifecycle', () {
    test('open/close flip isOpen', () async {
      expect(mongo.isOpen, isTrue);
      await mongo.close();
      expect(mongo.isOpen, isFalse);
    });

    test('operations before open throw NotConnectedException', () {
      final closed = AnakiMongoDb(FakeMongoDriver());
      expect(
        () => closed.collection('users').find(),
        throwsA(isA<NotConnectedException>()),
      );
      expect(() => closed.ping(), throwsA(isA<NotConnectedException>()));
      expect(
        () => closed.transaction((_) async {}),
        throwsA(isA<NotConnectedException>()),
      );
    });
  });

  group('Envelopes', () {
    test('find builds full envelope', () async {
      await mongo.collection('users').find(
        {'active': true},
        {'name': 1},
        {'email': 1},
        10,
        20,
      );
      expect(driver.lastEnvelope, {
        'op': 'find',
        'collection': 'users',
        'filter': {'active': true},
        'sort': {'name': 1},
        'projection': {'email': 1},
        'skip': 10,
        'limit': 20,
      });
    });

    test('findOne omits optional fields', () async {
      await mongo.collection('users').findOne({'name': 'Ana'});
      expect(driver.lastEnvelope, {
        'op': 'findOne',
        'collection': 'users',
        'filter': {'name': 'Ana'},
      });
    });

    test('updateOne carries filter/update/upsert', () async {
      await mongo.collection('users').updateOne(
        {'name': 'Ana'},
        {
          r'$set': {'age': 29},
        },
        upsert: true,
      );
      expect(driver.lastEnvelope, {
        'op': 'updateOne',
        'collection': 'users',
        'filter': {'name': 'Ana'},
        'update': {
          r'$set': {'age': 29},
        },
        'upsert': true,
      });
    });

    test('deleteMany carries filter', () async {
      await mongo.collection('users').deleteMany({'inactive': true});
      expect(driver.lastEnvelope, {
        'op': 'deleteMany',
        'collection': 'users',
        'filter': {'inactive': true},
      });
    });

    test('aggregate carries pipeline', () async {
      await mongo.collection('orders').aggregate([
        {
          r'$match': {'paid': true},
        },
        {
          r'$group': {'_id': r'$city', 'total': {r'$sum': r'$value'}},
        },
      ]);
      expect(driver.lastEnvelope!['op'], 'aggregate');
      expect(driver.lastEnvelope!['pipeline'], hasLength(2));
    });

    test('createIndex builds keys/name/unique', () async {
      await mongo
          .collection('users')
          .createIndex({'email': 1}, name: 'ix_email', unique: true);
      expect(driver.lastEnvelope, {
        'op': 'createIndex',
        'collection': 'users',
        'keys': {'email': 1},
        'name': 'ix_email',
        'unique': true,
      });
    });

    test('runCommand wraps the command', () async {
      driver.nextRows = [
        {'ok': 1},
      ];
      final reply = await mongo.runCommand({'ping': 1});
      expect(driver.lastEnvelope, {
        'op': 'runCommand',
        'command': {'ping': 1},
      });
      expect(reply, {'ok': 1});
    });
  });

  group('insertOne / insertMany', () {
    test('insertOne generates and returns ObjectId when _id is absent',
        () async {
      final id = await mongo.collection('users').insertOne({'name': 'Ana'});
      expect(id, isA<ObjectId>());
      final doc = driver.lastEnvelope!['document'] as Map;
      expect(doc['_id'], {r'$oid': (id as ObjectId).hexString});
      expect(doc['name'], 'Ana');
    });

    test('insertOne preserves a caller-provided _id', () async {
      final id = await mongo.collection('users').insertOne({'_id': 42});
      expect(id, 42);
    });

    test('insertMany routes through executeBatch', () async {
      final count = await mongo.collection('users').insertMany([
        {'name': 'Ana'},
        {'name': 'Bob'},
      ]);
      expect(count, 2);
      expect(driver.callLog.last, 'executeBatch:2');
      expect(driver.lastEnvelope, {'op': 'insertOne', 'collection': 'users'});
    });

    test('insertMany with empty list short-circuits', () async {
      expect(await mongo.collection('users').insertMany([]), 0);
      expect(driver.callLog.where((c) => c.startsWith('executeBatch')), isEmpty);
    });
  });

  group('Extended JSON codec at the boundary', () {
    test('ObjectId and DateTime are encoded in filters', () async {
      final id = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      final when = DateTime.utc(2026, 7, 18, 12);
      await mongo.collection('events').find({
        '_id': id,
        'at': {r'$gte': when},
      });
      expect(driver.lastEnvelope!['filter'], {
        '_id': {r'$oid': '507f1f77bcf86cd799439011'},
        'at': {r'$gte': {r'$date': '2026-07-18T12:00:00.000Z'}},
      });
    });

    test('rows are decoded back to ObjectId/DateTime', () async {
      driver.nextRows = [
        {
          '_id': {r'$oid': '507f1f77bcf86cd799439011'},
          'at': {r'$date': '2026-07-18T12:00:00Z'},
          'name': 'Ana',
        },
      ];
      final doc = await mongo.collection('events').findOne();
      expect(doc!['_id'], ObjectId.fromHexString('507f1f77bcf86cd799439011'));
      expect(doc['at'], DateTime.utc(2026, 7, 18, 12));
      expect(doc['name'], 'Ana');
    });

    test('extendedJsonCodec: false passes maps through raw', () async {
      final rawMongo = AnakiMongoDb(driver, extendedJsonCodec: false);
      await rawMongo.open();
      final id = {r'$oid': '507f1f77bcf86cd799439011'};
      await rawMongo.collection('users').find({'_id': id});
      expect(driver.lastEnvelope!['filter'], {'_id': id});
      driver.nextRows = [
        {'_id': id},
      ];
      final doc = await rawMongo.collection('users').findOne();
      expect(doc!['_id'], id);
    });
  });

  group('findPaged', () {
    test('issues countDocuments plus skip/limit find', () async {
      driver.nextRows = [
        {'count': 45},
      ];
      final page = await mongo.collection('users').findPaged<dynamic>(
        filter: {'active': true},
        sort: {'name': 1},
        page: 2,
        pageSize: 20,
      );
      // last query was the find with computed skip/limit
      expect(driver.lastEnvelope!['op'], 'find');
      expect(driver.lastEnvelope!['skip'], 20);
      expect(driver.lastEnvelope!['limit'], 20);
      expect(page.total, 45);
      expect(page.page, 2);
      expect(page.totalPages, 3);
      expect(page.hasNextPage, isTrue);
    });
  });

  group('Transaction', () {
    test('commits on success', () async {
      await mongo.transaction((tx) async {
        await tx.collection('a').insertOne({'x': 1});
      });
      expect(driver.callLog, contains('begin'));
      expect(driver.callLog, contains('commit'));
      expect(driver.callLog, isNot(contains('rollback')));
    });

    test('rolls back and rethrows on error', () async {
      await expectLater(
        mongo.transaction((_) async => throw StateError('boom')),
        throwsStateError,
      );
      expect(driver.callLog, contains('begin'));
      expect(driver.callLog, contains('rollback'));
      expect(driver.callLog, isNot(contains('commit')));
    });
  });

  group('Adapter fallback', () {
    test('maps rows through the RowAdapter when no map is given', () async {
      final adapter = RowAdapter(
        <T>(row) => row['name'] as T,
        <T>(entity) => {'name': entity},
      );
      final withAdapter = AnakiMongoDb(driver, adapter: adapter);
      await withAdapter.open();
      driver.nextRows = [
        {'name': 'Ana'},
      ];
      final names = await withAdapter.collection('users').find<String>();
      expect(names, ['Ana']);
    });
  });
}
