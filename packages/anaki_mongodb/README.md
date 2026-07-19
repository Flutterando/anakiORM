# anaki_mongodb

MongoDB document client for [AnakiORM](https://github.com/anaki/anaki_orm), backed by the same native Rust connector infrastructure as the SQL drivers.

Unlike the SQL drivers, this package does **not** implement `AnakiDriver` and is not used through `AnakiDb` — MongoDB is not a SQL database. It ships a dedicated document API.

## Usage

```dart
import 'package:anaki_mongodb/anaki_mongodb.dart';

final mongo = AnakiMongoDb(MongoDriver(host: 'localhost', database: 'app'));
// or: MongoDriver.uri('mongodb://localhost:27017/?replicaSet=rs0', database: 'app')
await mongo.open();

final users = mongo.collection('users');

// insertOne returns the _id (client-generated ObjectId when absent)
final id = await users.insertOne({'name': 'Ana', 'createdAt': DateTime.now()});

// ObjectId/DateTime convert automatically at the boundary
final ana = await users.findOne({'_id': id});

// Queries
final active = await users.find({'active': true}, {'name': 1}, null, 0, 20);
final page = await users.findPaged(filter: {'active': true}, sort: {'name': 1}, page: 1, pageSize: 20);
final total = await users.countDocuments();
final cities = await users.distinct('city');

// Typed mapping (per-call map or a client-wide RowAdapter)
final dtos = await users.find({}, null, null, null, null, UserDTO.fromJson);

// Transactions (requires a replica set)
await mongo.transaction((tx) async {
  await tx.collection('accounts').updateOne({'_id': a}, {r'$inc': {'balance': -100}});
  await tx.collection('accounts').updateOne({'_id': b}, {r'$inc': {'balance': 100}});
});

await mongo.close();
```

## Semantics and limits (v1)

- `insertOne` returns the `_id`; when the document has none, a client-side `ObjectId` is generated and injected (no extra round-trip).
- Transactions require a replica set; on a standalone server the first operation inside the transaction fails with the server's error. Commit is single-attempt (an indeterminate outcome is flagged in the error message).
- `Decimal128` values decode as `String`; `$binary` and other wrappers pass through as raw maps.
- Not in v1: `findOneAndUpdate`, mixed `bulkWrite`, change streams, GridFS — `runCommand` is the escape hatch.
- `QueryException.sql` carries the JSON envelope (filters visible — avoid logging verbatim if sensitive).

## Native library

The Rust connector is built per platform with:

```sh
./scripts/build_native.sh mongodb --local
```

Integration tests expect a local single-node replica set: `docker compose up` from `example/shelf_mongodb_example/`.
