import 'dart:convert';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../dto/todo_dto.dart';

/// Creates the router for Todo CRUD endpoints.
Router createTodoRouter(AnakiDb db) {
  final router = Router();

  // GET /todos — List all todos
  router.get('/todos', (Request request) async {
    final todos = await db.query(
      'SELECT * FROM todos ORDER BY id DESC',
      null,
      TodoDTO.fromJson,
    );

    return Response.ok(
      jsonEncode(todos.map((t) => t.toJson()).toList()),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // GET /todos/<id> — Get a single todo
  router.get('/todos/<id>', (Request request, String id) async {
    final todo = await db.queryFirst(
      'SELECT * FROM todos WHERE id = @id',
      {'id': int.parse(id)},
      TodoDTO.fromJson,
    );

    if (todo == null) {
      return Response.notFound(
        jsonEncode({'error': 'Todo not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(todo.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // POST /todos — Create a new todo
  router.post('/todos', (Request request) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final todo = TodoDTO.fromJson(json);

    final affected = await db.execute(
      'INSERT INTO todos (title, description, completed) VALUES (@title, @description, @completed)',
      todo.toJson(),
    );

    if (affected == 0) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create todo'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Get the created todo (last inserted)
    final created = await db.queryFirst(
      'SELECT TOP 1 * FROM todos ORDER BY id DESC',
      null,
      TodoDTO.fromJson,
    );

    return Response(
      201,
      body: jsonEncode(created?.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // PUT /todos/<id> — Update a todo
  router.put('/todos/<id>', (Request request, String id) async {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final todo = TodoDTO.fromJson(json);

    final affected = await db.execute(
      'UPDATE todos SET title = @title, description = @description, completed = @completed WHERE id = @id',
      {...todo.toJson(), 'id': int.parse(id)},
    );

    if (affected == 0) {
      return Response.notFound(
        jsonEncode({'error': 'Todo not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final updated = await db.queryFirst(
      'SELECT * FROM todos WHERE id = @id',
      {'id': int.parse(id)},
      TodoDTO.fromJson,
    );

    return Response.ok(
      jsonEncode(updated?.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // DELETE /todos/<id> — Delete a todo
  router.delete('/todos/<id>', (Request request, String id) async {
    final affected = await db.execute(
      'DELETE FROM todos WHERE id = @id',
      {'id': int.parse(id)},
    );

    if (affected == 0) {
      return Response.notFound(
        jsonEncode({'error': 'Todo not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({'deleted': true}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  return router;
}
