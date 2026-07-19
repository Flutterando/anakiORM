import 'dart:convert';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_redis/anaki_redis.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

Router createCacheRouter(AnakiRedis redis) {
  final router = Router();

  // GET /cache/<key> — read a value
  router.get('/cache/<key>', (Request request, String key) async {
    final value = await redis.get(key);
    if (value == null) {
      return Response.notFound(jsonEncode({'error': 'Key not found'}));
    }
    final ttl = await redis.ttl(key);
    return Response.ok(
      jsonEncode({
        'key': key,
        'value': value,
        if (ttl != null) 'ttlSeconds': ttl.inSeconds,
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  // PUT /cache/<key> — body {"value": "...", "ttlSeconds": N?}
  router.put('/cache/<key>', (Request request, String key) async {
    final body = jsonDecode(await request.readAsString()) as Map;
    final value = body['value'];
    if (value is! String) {
      return Response.badRequest(
        body: jsonEncode({'error': '"value" must be a string'}),
      );
    }
    final ttlSeconds = body['ttlSeconds'] as int?;
    await redis.set(
      key,
      value,
      ttl: ttlSeconds != null ? Duration(seconds: ttlSeconds) : null,
    );
    return Response.ok(jsonEncode({'ok': true}));
  });

  // DELETE /cache/<key>
  router.delete('/cache/<key>', (Request request, String key) async {
    final removed = await redis.del([key]);
    return Response.ok(jsonEncode({'removed': removed}));
  });

  // GET /stats — pipeline demo: atomic visit counter with a daily expiry
  router.get('/stats', (Request request) async {
    await redis.pipeline((p) {
      p.incr('stats:visits');
      p.expire('stats:visits', const Duration(days: 1));
    });
    final visits = await redis.get('stats:visits');
    return Response.ok(
      jsonEncode({'visits': int.tryParse(visits ?? '0') ?? 0}),
      headers: {'content-type': 'application/json'},
    );
  });

  // Error handling example: wrong-type command surfaces as QueryException
  router.get('/health', (Request request) async {
    try {
      final alive = await redis.ping();
      return Response.ok(jsonEncode({'redis': alive ? 'up' : 'down'}));
    } on AnakiException catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.message}),
      );
    }
  });

  return router;
}
