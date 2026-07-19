import 'dart:convert';

import 'package:anaki_mongodb/anaki_mongodb.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../dto/todo_dto.dart';

Router createTodoRouter(AnakiMongoDb mongo) {
  final router = Router();
  final todos = mongo.collection('todos');

  // GET /todos — newest first
  router.get('/todos', (Request request) async {
    final list = await todos.find<TodoDTO>(
      {},
      {'createdAt': -1},
      null,
      null,
      null,
      TodoDTO.fromJson,
    );
    return Response.ok(
      jsonEncode(list.map((t) => t.toApiJson()).toList()),
      headers: {'content-type': 'application/json'},
    );
  });

  // GET /todos/<id>
  router.get('/todos/<id>', (Request request, String id) async {
    final ObjectId oid;
    try {
      oid = ObjectId.fromHexString(id);
    } on ArgumentError {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid id'}));
    }
    final todo = await todos.findOne<TodoDTO>(
      {'_id': oid},
      null,
      null,
      TodoDTO.fromJson,
    );
    if (todo == null) {
      return Response.notFound(jsonEncode({'error': 'Todo not found'}));
    }
    return Response.ok(
      jsonEncode(todo.toApiJson()),
      headers: {'content-type': 'application/json'},
    );
  });

  // POST /todos — body {"title": "...", "description": "..."}
  router.post('/todos', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map;
    final title = body['title'];
    if (title is! String || title.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': '"title" is required'}),
      );
    }
    final id = await todos.insertOne({
      'title': title,
      'description': body['description'] as String?,
      'completed': false,
      'createdAt': DateTime.now(),
    });
    return Response.ok(jsonEncode({'id': id.toString()}));
  });

  // PUT /todos/<id> — body {"title"?, "description"?, "completed"?}
  router.put('/todos/<id>', (Request request, String id) async {
    final ObjectId oid;
    try {
      oid = ObjectId.fromHexString(id);
    } on ArgumentError {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid id'}));
    }
    final body = jsonDecode(await request.readAsString()) as Map;
    final updates = <String, dynamic>{
      if (body['title'] is String) 'title': body['title'],
      if (body.containsKey('description')) 'description': body['description'],
      if (body['completed'] is bool) 'completed': body['completed'],
    };
    if (updates.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Nothing to update'}),
      );
    }
    final modified = await todos.updateOne({'_id': oid}, {r'$set': updates});
    if (modified == 0) {
      return Response.notFound(jsonEncode({'error': 'Todo not found'}));
    }
    return Response.ok(jsonEncode({'updated': modified}));
  });

  // DELETE /todos/<id>
  router.delete('/todos/<id>', (Request request, String id) async {
    final ObjectId oid;
    try {
      oid = ObjectId.fromHexString(id);
    } on ArgumentError {
      return Response.badRequest(body: jsonEncode({'error': 'Invalid id'}));
    }
    final deleted = await todos.deleteOne({'_id': oid});
    if (deleted == 0) {
      return Response.notFound(jsonEncode({'error': 'Todo not found'}));
    }
    return Response.ok(jsonEncode({'deleted': deleted}));
  });

  return router;
}
