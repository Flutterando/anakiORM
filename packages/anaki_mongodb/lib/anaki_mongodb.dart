/// MongoDB document client for AnakiORM.
///
/// Unlike the SQL drivers, this package does not implement `AnakiDriver` and
/// is not used through `AnakiDb`. It provides a dedicated document API:
///
/// ```dart
/// final mongo = AnakiMongoDb(MongoDriver(host: 'localhost', database: 'app'));
/// await mongo.open();
///
/// final users = mongo.collection('users');
/// final id = await users.insertOne({'name': 'Ana', 'createdAt': DateTime.now()});
/// final ana = await users.findOne({'_id': id});
///
/// await mongo.close();
/// ```
library anaki_mongodb;

export 'src/mongo_db.dart';
export 'src/mongo_driver_base.dart';
export 'src/mongo_driver.dart';
export 'src/object_id.dart';
export 'src/mongo_codec.dart';
