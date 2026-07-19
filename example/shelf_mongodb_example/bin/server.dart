import 'dart:io';

import 'package:anaki_mongodb/anaki_mongodb.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:shelf_mongodb_example/routes/todo_routes.dart';

Future<void> main() async {
  // 1. Open MongoDB connection (single-node replica set from docker-compose)
  final mongo = AnakiMongoDb(
    MongoDriver.uri(
      'mongodb://localhost:27017/?replicaSet=rs0&directConnection=true',
      database: 'anaki_test',
    ),
  );
  await mongo.open();

  // 2. Ensure indexes
  await mongo.collection('todos').createIndex({'createdAt': -1});

  print('Database connected (MongoDB).');

  // 3. Create routes
  final router = createTodoRouter(mongo);

  // 4. Build pipeline with middleware
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  // 5. Start server
  final server = await shelf_io.serve(handler, 'localhost', 8080);
  print('Server running on http://${server.address.host}:${server.port}');

  // 6. Graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nShutting down...');
    await mongo.close();
    server.close();
    exit(0);
  });
}
