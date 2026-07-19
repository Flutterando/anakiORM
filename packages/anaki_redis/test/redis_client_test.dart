import 'dart:convert';

import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_redis/anaki_redis.dart';
import 'package:test/test.dart';

/// In-memory fake driver recording every issued command.
class FakeRedisDriver implements RedisDriverBase {
  final List<String> callLog = [];
  dynamic nextReply;
  int nextPipelineCount = 0;
  bool isOpen = false;

  @override
  Future<void> rawOpen() async {
    callLog.add('open');
    isOpen = true;
  }

  @override
  Future<void> rawClose() async {
    callLog.add('close');
    isOpen = false;
  }

  @override
  Future<bool> rawPing() async {
    callLog.add('ping');
    return isOpen;
  }

  @override
  Future<dynamic> rawCommand(List<String> parts) async {
    callLog.add('command:${jsonEncode(parts)}');
    return nextReply;
  }

  @override
  Future<int> rawPipeline(List<List<String>> commands) async {
    callLog.add('pipeline:${jsonEncode(commands)}');
    return nextPipelineCount;
  }
}

void main() {
  late FakeRedisDriver driver;
  late AnakiRedis redis;

  setUp(() async {
    driver = FakeRedisDriver();
    redis = AnakiRedis.withDriver(driver);
    await redis.open();
  });

  group('Lifecycle', () {
    test('open and close flip isOpen', () async {
      expect(redis.isOpen, isTrue);
      await redis.close();
      expect(redis.isOpen, isFalse);
    });

    test('operations before open throw NotConnectedException', () async {
      final closed = AnakiRedis.withDriver(FakeRedisDriver());
      expect(() => closed.get('k'), throwsA(isA<NotConnectedException>()));
      expect(() => closed.ping(), throwsA(isA<NotConnectedException>()));
      expect(
        () => closed.pipeline((p) => p.incr('k')),
        throwsA(isA<NotConnectedException>()),
      );
    });
  });

  group('Command encoding', () {
    test('set encodes SET', () async {
      await redis.set('k', 'v');
      expect(driver.callLog.last, 'command:["SET","k","v"]');
    });

    test('set with ttl encodes PX milliseconds', () async {
      await redis.set('k', 'v', ttl: const Duration(milliseconds: 1500));
      expect(driver.callLog.last, 'command:["SET","k","v","PX","1500"]');
    });

    test('mset flattens entries', () async {
      await redis.mset({'a': '1', 'b': '2'});
      expect(driver.callLog.last, 'command:["MSET","a","1","b","2"]');
    });

    test('expire uses PEXPIRE', () async {
      driver.nextReply = 1;
      await redis.expire('k', const Duration(seconds: 2));
      expect(driver.callLog.last, 'command:["PEXPIRE","k","2000"]');
    });

    test('zadd interleaves score/member', () async {
      driver.nextReply = 2;
      await redis.zadd('board', {'ana': 10.5, 'bob': 3.0});
      expect(
        driver.callLog.last,
        'command:["ZADD","board","10.5","ana","3.0","bob"]',
      );
    });

    test('command passes through arbitrary parts', () async {
      await redis.command(['GETRANGE', 'k', 0, 3]);
      expect(driver.callLog.last, 'command:["GETRANGE","k","0","3"]');
    });

    test('null argument throws ArgumentError', () async {
      expect(() => redis.command(['SET', 'k', null]), throwsArgumentError);
    });

    test('non-scalar argument throws ArgumentError', () async {
      expect(
        () => redis.command([
          'SET',
          'k',
          {'a': 1},
        ]),
        throwsArgumentError,
      );
    });
  });

  group('Reply decoding', () {
    test('get returns null for nil', () async {
      driver.nextReply = null;
      expect(await redis.get('missing'), isNull);
    });

    test('incr coerces string reply', () async {
      driver.nextReply = '42';
      expect(await redis.incr('k'), 42);
    });

    test('ttl maps negative replies to null', () async {
      driver.nextReply = -2;
      expect(await redis.ttl('missing'), isNull);
      driver.nextReply = 1500;
      expect(await redis.ttl('k'), const Duration(milliseconds: 1500));
    });

    test('hgetall accepts RESP3 map reply', () async {
      driver.nextReply = {'name': 'Ana', 'age': '28'};
      expect(await redis.hgetall('user:1'), {'name': 'Ana', 'age': '28'});
    });

    test('hgetall accepts RESP2 flat array reply', () async {
      driver.nextReply = ['name', 'Ana', 'age', '28'];
      expect(await redis.hgetall('user:1'), {'name': 'Ana', 'age': '28'});
    });

    test('mget preserves nulls', () async {
      driver.nextReply = ['a', null, 'c'];
      expect(await redis.mget(['k1', 'k2', 'k3']), ['a', null, 'c']);
    });

    test('smembers returns a set', () async {
      driver.nextReply = ['a', 'b', 'a'];
      expect(await redis.smembers('s'), {'a', 'b'});
    });

    test('zrangeWithScores folds flat pairs', () async {
      driver.nextReply = ['ana', '10.5', 'bob', '3'];
      final result = await redis.zrangeWithScores('board', 0, -1);
      expect(result, hasLength(2));
      expect(result.first.member, 'ana');
      expect(result.first.score, 10.5);
    });

    test('zscore returns null for missing member', () async {
      driver.nextReply = null;
      expect(await redis.zscore('board', 'ghost'), isNull);
    });

    test('scan returns cursor and keys', () async {
      driver.nextReply = ['17', ['a', 'b']];
      final result = await redis.scan(match: 'user:*', count: 10);
      expect(result.cursor, 17);
      expect(result.keys, ['a', 'b']);
      expect(
        driver.callLog.last,
        'command:["SCAN","0","MATCH","user:*","COUNT","10"]',
      );
    });
  });

  group('JSON and object cache', () {
    test('setJson/getJson round-trip', () async {
      await redis.setJson('k', {'a': 1});
      expect(driver.callLog.last, 'command:["SET","k","{\\"a\\":1}"]');
      driver.nextReply = '{"a":1}';
      expect(await redis.getJson('k'), {'a': 1});
    });

    test('setObject without adapter throws StateError', () async {
      expect(() => redis.setObject('k', 'v'), throwsStateError);
    });
  });

  group('Pipeline', () {
    test('builder enqueues in order and returns count', () async {
      driver.nextPipelineCount = 3;
      final count = await redis.pipeline((p) {
        p.set('a', '1');
        p.incr('b');
        p.expire('a', const Duration(seconds: 1));
      });
      expect(count, 3);
      expect(
        driver.callLog.last,
        'pipeline:[["SET","a","1"],["INCR","b"],["PEXPIRE","a","1000"]]',
      );
    });

    test('empty builder short-circuits without FFI call', () async {
      final count = await redis.pipeline((_) {});
      expect(count, 0);
      expect(driver.callLog.where((c) => c.startsWith('pipeline')), isEmpty);
    });
  });

  group('AnakiRedis.url', () {
    test('rejects non-redis schemes', () {
      expect(() => AnakiRedis.url('http://x'), throwsArgumentError);
    });

    test('accepts redis:// with password and db', () {
      final client = AnakiRedis.url('redis://:secret@myhost:6380/2');
      expect(client, isA<AnakiRedis>());
    });
  });
}
