/// Integration tests for anaki_redis.
///
/// Prerequisites:
///   1. Start Redis:  cd example/shelf_redis_example && docker compose up -d
///   2. Build the native library:  ./scripts/build_native.sh redis --local
///   3. Run:  dart test packages/anaki_redis/test/redis_integration_test.dart
library;

import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_redis/anaki_redis.dart';
import 'package:test/test.dart';

void main() {
  late AnakiRedis redis;

  setUpAll(() async {
    redis = AnakiRedis(host: 'localhost', password: 'anaki');
    await redis.open();
  });

  setUp(() async {
    await redis.flushDb();
  });

  tearDownAll(() async {
    await redis.flushDb();
    await redis.close();
  });

  group('Connection', () {
    test('ping', () async {
      expect(await redis.ping(), isTrue);
    });
  });

  group('Strings', () {
    test('set/get/del round-trip', () async {
      await redis.set('k', 'valor');
      expect(await redis.get('k'), 'valor');
      expect(await redis.del(['k']), 1);
      expect(await redis.get('k'), isNull);
    });

    test('set with ttl expires', () async {
      await redis.set('temp', 'x', ttl: const Duration(milliseconds: 500));
      expect(await redis.get('temp'), 'x');
      final remaining = await redis.ttl('temp');
      expect(remaining, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(await redis.get('temp'), isNull);
    });

    test('incr/incrBy/decr', () async {
      expect(await redis.incr('n'), 1);
      expect(await redis.incrBy('n', 10), 11);
      expect(await redis.decr('n'), 10);
    });

    test('mset/mget with missing key', () async {
      await redis.mset({'a': '1', 'b': '2'});
      expect(await redis.mget(['a', 'missing', 'b']), ['1', null, '2']);
    });

    test('exists/expire/persist', () async {
      await redis.set('k', 'v');
      expect(await redis.exists('k'), isTrue);
      expect(await redis.expire('k', const Duration(minutes: 1)), isTrue);
      expect(await redis.ttl('k'), isNotNull);
      expect(await redis.persist('k'), isTrue);
      expect(await redis.ttl('k'), isNull);
    });
  });

  group('Hashes', () {
    test('hset/hget/hgetall/hdel/hkeys/hexists', () async {
      expect(await redis.hset('user:1', 'name', 'Ana'), isTrue);
      expect(await redis.hsetAll('user:1', {'city': 'SP', 'age': '28'}), 2);
      expect(await redis.hget('user:1', 'name'), 'Ana');
      expect(
        await redis.hgetall('user:1'),
        {'name': 'Ana', 'city': 'SP', 'age': '28'},
      );
      expect(await redis.hexists('user:1', 'city'), isTrue);
      expect(await redis.hkeys('user:1'), containsAll(['name', 'city', 'age']));
      expect(await redis.hdel('user:1', ['city']), 1);
      expect(await redis.hgetall('missing'), isEmpty);
    });
  });

  group('Lists', () {
    test('push/pop/range/len', () async {
      await redis.rpush('queue', ['a', 'b']);
      await redis.lpush('queue', ['z']);
      expect(await redis.lrange('queue', 0, -1), ['z', 'a', 'b']);
      expect(await redis.llen('queue'), 3);
      expect(await redis.lpop('queue'), 'z');
      expect(await redis.rpop('queue'), 'b');
    });
  });

  group('Sets', () {
    test('sadd/smembers/sismember/srem/scard', () async {
      expect(await redis.sadd('tags', ['x', 'y', 'x']), 2);
      expect(await redis.smembers('tags'), {'x', 'y'});
      expect(await redis.sismember('tags', 'x'), isTrue);
      expect(await redis.srem('tags', ['x']), 1);
      expect(await redis.scard('tags'), 1);
    });
  });

  group('Sorted sets', () {
    test('zadd/zrange/zscore/zrem/zcard', () async {
      expect(await redis.zadd('board', {'ana': 10.5, 'bob': 3}), 2);
      expect(await redis.zrange('board', 0, -1), ['bob', 'ana']);
      final scored = await redis.zrangeWithScores('board', 0, -1);
      expect(scored.last, (member: 'ana', score: 10.5));
      expect(await redis.zscore('board', 'ana'), 10.5);
      expect(await redis.zscore('board', 'ghost'), isNull);
      expect(await redis.zrem('board', ['bob']), 1);
      expect(await redis.zcard('board'), 1);
    });
  });

  group('Keys', () {
    test('keys and scan', () async {
      await redis.mset({'user:1': 'a', 'user:2': 'b', 'other': 'c'});
      expect(await redis.keys('user:*'), hasLength(2));

      final found = <String>[];
      var cursor = 0;
      do {
        final page = await redis.scan(cursor: cursor, match: 'user:*');
        found.addAll(page.keys);
        cursor = page.cursor;
      } while (cursor != 0);
      expect(found.toSet(), hasLength(2));
    });
  });

  group('Pipeline', () {
    test('atomic batch applies all commands', () async {
      final count = await redis.pipeline((p) {
        p.set('p:a', '1');
        p.incr('p:counter');
        p.incr('p:counter');
        p.expire('p:a', const Duration(minutes: 1));
      });
      expect(count, 4);
      expect(await redis.get('p:a'), '1');
      expect(await redis.get('p:counter'), '2');
      expect(await redis.ttl('p:a'), isNotNull);
    });
  });

  group('JSON helpers', () {
    test('setJson/getJson round-trip', () async {
      await redis.setJson('doc', {'name': 'Ana', 'tags': ['a', 'b']});
      expect(await redis.getJson('doc'), {'name': 'Ana', 'tags': ['a', 'b']});
    });
  });

  group('Errors', () {
    test('wrong-type command throws QueryException with the command', () async {
      await redis.set('str', 'text');
      await expectLater(
        redis.lpush('str', ['x']),
        throwsA(
          isA<QueryException>().having(
            (e) => e.sql,
            'sql',
            contains('LPUSH'),
          ),
        ),
      );
    });

    test('generic command escape hatch', () async {
      await redis.set('range', 'hello world');
      expect(await redis.command(['GETRANGE', 'range', 0, 4]), 'hello');
    });
  });
}
