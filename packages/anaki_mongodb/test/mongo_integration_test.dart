/// Integration tests for anaki_mongodb.
///
/// Prerequisites:
///   1. Start MongoDB (single-node replica set, required for transactions):
///        cd example/shelf_mongodb_example && docker compose up -d
///      Wait for the healthcheck to initiate the replica set (~10s).
///   2. Build the native library:  ./scripts/build_native.sh mongodb --local
///   3. Run:  dart test packages/anaki_mongodb/test/mongo_integration_test.dart
library;

import 'package:anaki_mongodb/anaki_mongodb.dart';
import 'package:anaki_orm/anaki_orm.dart';
import 'package:test/test.dart';

class UserDTO {
  final ObjectId? id;
  final String name;
  final int age;

  UserDTO({this.id, required this.name, required this.age});

  factory UserDTO.fromJson(Map<String, dynamic> json) => UserDTO(
        id: json['_id'] as ObjectId?,
        name: json['name'] as String,
        age: json['age'] as int,
      );
}

void main() {
  late AnakiMongoDb mongo;

  setUpAll(() async {
    mongo = AnakiMongoDb(
      MongoDriver.uri(
        'mongodb://localhost:27017/?replicaSet=rs0&directConnection=true',
        database: 'anaki_test',
      ),
    );
    await mongo.open();
  });

  setUp(() async {
    await mongo.collection('users').deleteMany({});
    await mongo.collection('accounts').deleteMany({});
  });

  tearDownAll(() async {
    await mongo.collection('users').drop();
    await mongo.collection('accounts').drop();
    await mongo.close();
  });

  group('Connection', () {
    test('ping', () async {
      expect(await mongo.ping(), isTrue);
    });

    test('runCommand escape hatch', () async {
      final reply = await mongo.runCommand({'ping': 1});
      expect(reply['ok'], 1);
    });
  });

  group('CRUD', () {
    test('insertOne returns id; types round-trip', () async {
      final users = mongo.collection('users');
      final createdAt = DateTime.utc(2026, 7, 18, 12, 30);
      final id = await users.insertOne({
        'name': 'Ana',
        'age': 28,
        'createdAt': createdAt,
      });
      expect(id, isA<ObjectId>());

      final doc = await users.findOne({'_id': id});
      expect(doc!['_id'], id);
      expect(doc['name'], 'Ana');
      expect(doc['age'], 28);
      expect(doc['createdAt'], createdAt);
    });

    test('insertMany + find with filter/sort/projection/skip/limit', () async {
      final users = mongo.collection('users');
      final inserted = await users.insertMany([
        for (var i = 0; i < 10; i++)
          {'name': 'User$i', 'age': 20 + i, 'active': i.isEven},
      ]);
      expect(inserted, 10);

      final result = await users.find(
        {'active': true},
        {'age': -1},
        {'name': 1, 'age': 1},
        1,
        2,
      );
      expect(result, hasLength(2));
      expect(result.first['name'], 'User6');
      expect(result.first.containsKey('active'), isFalse);
    });

    test('updateOne / updateMany / upsert', () async {
      final users = mongo.collection('users');
      await users.insertMany([
        {'name': 'Ana', 'age': 28},
        {'name': 'Bob', 'age': 30},
      ]);

      expect(
        await users.updateOne({'name': 'Ana'}, {r'$set': {'age': 29}}),
        1,
      );
      expect(
        await users.updateMany({}, {r'$inc': {'age': 1}}),
        2,
      );
      expect(
        await users.updateOne(
          {'name': 'Carol'},
          {r'$set': {'age': 22}},
          upsert: true,
        ),
        1,
      );
      expect(await users.countDocuments(), 3);
    });

    test('replaceOne and deleteOne/deleteMany', () async {
      final users = mongo.collection('users');
      await users.insertOne({'name': 'Ana', 'age': 28});
      expect(
        await users.replaceOne({'name': 'Ana'}, {'name': 'Ana', 'age': 40}),
        1,
      );
      expect((await users.findOne({'name': 'Ana'}))!['age'], 40);
      expect(await users.deleteOne({'name': 'Ana'}), 1);
      await users.insertMany([
        {'name': 'X'},
        {'name': 'Y'},
      ]);
      expect(await users.deleteMany({}), 2);
    });
  });

  group('Queries', () {
    setUp(() async {
      await mongo.collection('users').insertMany([
        {'name': 'Ana', 'age': 28, 'city': 'SP'},
        {'name': 'Bob', 'age': 30, 'city': 'RJ'},
        {'name': 'Carol', 'age': 22, 'city': 'SP'},
      ]);
    });

    test('findPaged returns data and totals', () async {
      final page = await mongo.collection('users').findPaged<UserDTO>(
        sort: {'age': 1},
        page: 1,
        pageSize: 2,
        map: UserDTO.fromJson,
      );
      expect(page.total, 3);
      expect(page.data, hasLength(2));
      expect(page.data.first.name, 'Carol');
      expect(page.hasNextPage, isTrue);
      expect(page.totalPages, 2);
    });

    test('aggregate match + group', () async {
      final result = await mongo.collection('users').aggregate([
        {
          r'$match': {'city': 'SP'},
        },
        {
          r'$group': {
            '_id': r'$city',
            'total': {r'$sum': 1},
          },
        },
      ]);
      expect(result.single['_id'], 'SP');
      expect(result.single['total'], 2);
    });

    test('distinct', () async {
      final cities = await mongo.collection('users').distinct('city');
      expect(cities.toSet(), {'SP', 'RJ'});
    });

    test('mapping with fromJson', () async {
      final users = await mongo.collection('users').findOne<UserDTO>(
        {'name': 'Ana'},
        null,
        null,
        UserDTO.fromJson,
      );
      expect(users!.name, 'Ana');
      expect(users.id, isA<ObjectId>());
    });
  });

  group('Indexes', () {
    test('unique index violation throws QueryException', () async {
      final users = mongo.collection('users');
      await users.createIndex({'email': 1}, name: 'ix_email', unique: true);
      await users.insertOne({'email': 'ana@example.com'});
      await expectLater(
        users.insertOne({'email': 'ana@example.com'}),
        throwsA(isA<QueryException>()),
      );
      await users.dropIndex('ix_email');
    });
  });

  group('Transaction', () {
    test('commit persists across two collections', () async {
      final users = mongo.collection('users');
      final accounts = mongo.collection('accounts');
      await mongo.transaction((tx) async {
        await tx.collection('users').insertOne({'name': 'TxUser'});
        await tx.collection('accounts').insertOne({'owner': 'TxUser', 'balance': 100});
      });
      expect(await users.countDocuments({'name': 'TxUser'}), 1);
      expect(await accounts.countDocuments({'owner': 'TxUser'}), 1);
    });

    test('rollback reverts data', () async {
      final users = mongo.collection('users');
      try {
        await mongo.transaction((tx) async {
          await tx.collection('users').insertOne({'name': 'Ghost'});
          throw Exception('force rollback');
        });
      } catch (_) {}
      expect(await users.countDocuments({'name': 'Ghost'}), 0);
    });
  });
}
