import 'dart:io';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_mssql/anaki_mssql.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:shelf_mssql_example/routes/todo_routes.dart';

Future<void> main() async {
  // 1. Open database connection (reads from env vars with dev defaults)
  final env = Platform.environment;
  final db = AnakiDb(MssqlDriver(
    host: env['DB_HOST'] ?? 'localhost',
    port: int.parse(env['DB_PORT'] ?? '1433'),
    username: env['DB_USER'] ?? 'sa',
    password: env['DB_PASS'] ?? 'Anaki@Strong1',
    database: env['DB_NAME'] ?? 'anaki_test',
    trustCert: true,
  ));
  await db.open();

  // 2. Create table if not exists
  await db.execute('''
    IF OBJECT_ID('todos', 'U') IS NULL
    CREATE TABLE todos (
      id INT IDENTITY(1,1) PRIMARY KEY,
      title NVARCHAR(255) NOT NULL,
      description NVARCHAR(MAX),
      completed BIT DEFAULT 0
    )
  ''');

  print('Database connected (SQL Server).');

  // 3. Create routes
  final router = createTodoRouter(db);

  // 4. Build pipeline with middleware
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  // 5. Start server
  final host = env['HOST'] ?? 'localhost';
  final port = int.parse(env['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, host, port);
  print('Server running on http://${server.address.host}:${server.port}');

  // 6. Graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nShutting down...');
    await db.close();
    server.close();
    exit(0);
  });
}
