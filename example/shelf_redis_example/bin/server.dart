import 'dart:io';

import 'package:anaki_redis/anaki_redis.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:shelf_redis_example/routes/cache_routes.dart';

Future<void> main() async {
  // 1. Open Redis connection
  final redis = AnakiRedis(host: 'localhost', password: 'anaki');
  await redis.open();

  print('Redis connected.');

  // 2. Create routes
  final router = createCacheRouter(redis);

  // 3. Build pipeline with middleware
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  // 4. Start server
  final server = await shelf_io.serve(handler, 'localhost', 8080);
  print('Server running on http://${server.address.host}:${server.port}');

  // 5. Graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nShutting down...');
    await redis.close();
    server.close();
    exit(0);
  });
}
