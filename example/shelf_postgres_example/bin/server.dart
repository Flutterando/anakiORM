import 'dart:io';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_postgres/anaki_postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:shelf_postgres_example/routes/todo_routes.dart';

Future<void> main() async {
  // 1. Open database connection
  final db = AnakiDb(
    PostgresDriver(
      host: 'localhost',
      port: 5432,
      username: 'anaki',
      password: 'anaki',
      database: 'anaki_test',
      sslMode: 'disable',
    ),
  );
  await db.open();

  // 2. Create table if not exists
  await db.execute('''
    CREATE TABLE IF NOT EXISTS todos (
      id SERIAL PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      completed BOOLEAN DEFAULT false
    )
  ''');

  print('Database connected (PostgreSQL).');

  // 3. Create routes
  final router = createTodoRouter(db);

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
    await db.close();
    server.close();
    exit(0);
  });
}
