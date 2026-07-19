/// Redis key-value client for AnakiORM.
///
/// Unlike the SQL drivers, this package does not implement `AnakiDriver` and
/// is not used through `AnakiDb`. It provides a dedicated typed client:
///
/// ```dart
/// final redis = AnakiRedis(host: 'localhost', password: 'secret');
/// await redis.open();
/// await redis.set('greeting', 'hello', ttl: Duration(minutes: 5));
/// final value = await redis.get('greeting');
/// await redis.close();
/// ```
library anaki_redis;

export 'src/redis_client.dart';
export 'src/redis_driver_base.dart';
export 'src/redis_driver.dart';
