import 'package:anaki_orm/anaki_orm.dart';
import 'package:anaki_redis/src/redis_codec.dart';
import 'package:anaki_redis/src/redis_wire.dart';
import 'package:test/test.dart';

void main() {
  group('encodeRedisArgs', () {
    test('encodes scalars', () {
      expect(
        encodeRedisArgs(['SET', 'k', 1, 2.5, true]),
        ['SET', 'k', '1', '2.5', 'true'],
      );
    });

    test('rejects null with index in message', () {
      expect(
        () => encodeRedisArgs(['SET', null]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('index 1'),
          ),
        ),
      );
    });
  });

  group('reply decoders', () {
    test('replyAsInt accepts int and numeric string', () {
      expect(replyAsInt(7), 7);
      expect(replyAsInt('7'), 7);
      expect(replyAsInt(null), 0);
    });

    test('replyAsBool handles common shapes', () {
      expect(replyAsBool(1), isTrue);
      expect(replyAsBool(0), isFalse);
      expect(replyAsBool('OK'), isTrue);
      expect(replyAsBool(null), isFalse);
    });

    test('replyAsStringMap handles both wire shapes', () {
      expect(replyAsStringMap({'a': '1'}), {'a': '1'});
      expect(replyAsStringMap(['a', '1', 'b', '2']), {'a': '1', 'b': '2'});
      expect(replyAsStringMap(null), isEmpty);
    });

    test('replyAsScoredMembers handles flat, paired and map shapes', () {
      expect(
        replyAsScoredMembers(['a', '1.5']).single,
        (member: 'a', score: 1.5),
      );
      expect(
        replyAsScoredMembers([
          ['a', 1.5],
        ]).single,
        (member: 'a', score: 1.5),
      );
      expect(
        replyAsScoredMembers({'a': 1.5}).single,
        (member: 'a', score: 1.5),
      );
    });
  });

  group('checkWireError', () {
    test('maps error codes to exception types', () {
      expect(
        () => checkWireError({
          'error': {'code': 'CONNECTION_ERROR', 'message': 'down'},
        }),
        throwsA(isA<ConnectionException>()),
      );
      expect(
        () => checkWireError({
          'error': {'code': 'QUERY_ERROR', 'message': 'WRONGTYPE'},
        }, command: 'INCR user:1:name'),
        throwsA(
          isA<QueryException>().having(
            (e) => e.sql,
            'sql',
            'INCR user:1:name',
          ),
        ),
      );
      expect(
        () => checkWireError({
          'error': {'code': 'TRANSACTION_ERROR', 'message': 'nope'},
        }),
        throwsA(isA<TransactionException>()),
      );
      expect(
        () => checkWireError({
          'error': {'code': 'INTERNAL_ERROR', 'message': 'panic'},
        }),
        throwsA(isA<AnakiException>()),
      );
    });

    test('passes through ok responses', () {
      expect(
        () => checkWireError({
          'ok': {'rows': []},
        }),
        returnsNormally,
      );
    });

    test('unwrapQueryResult returns first row result', () {
      expect(
        unwrapQueryResult({
          'ok': {
            'rows': [
              {'result': 'value'},
            ],
          },
        }),
        'value',
      );
      expect(
        unwrapQueryResult({
          'ok': {'rows': []},
        }),
        isNull,
      );
    });
  });
}
