import 'package:anaki_mongodb/anaki_mongodb.dart';
import 'package:test/test.dart';

void main() {
  group('mongoEncode', () {
    test('passes scalars through', () {
      expect(mongoEncode(null), isNull);
      expect(mongoEncode(1), 1);
      expect(mongoEncode(1.5), 1.5);
      expect(mongoEncode(true), isTrue);
      expect(mongoEncode('x'), 'x');
    });

    test('converts ObjectId and DateTime deeply', () {
      final id = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      final encoded = mongoEncode({
        'ids': [id],
        'nested': {'at': DateTime.utc(2026, 1, 2, 3)},
      });
      expect(encoded, {
        'ids': [
          {r'$oid': '507f1f77bcf86cd799439011'},
        ],
        'nested': {
          'at': {r'$date': '2026-01-02T03:00:00.000Z'},
        },
      });
    });

    test('converts local DateTime to UTC', () {
      final local = DateTime(2026, 1, 1, 12);
      final encoded = mongoEncode(local) as Map;
      expect(encoded[r'$date'], local.toUtc().toIso8601String());
    });

    test('leaves operator keys untouched', () {
      expect(
        mongoEncode({
          'age': {r'$gt': 21},
        }),
        {
          'age': {r'$gt': 21},
        },
      );
    });

    test('rejects unsupported types', () {
      expect(() => mongoEncode(const Duration(seconds: 1)), throwsArgumentError);
    });
  });

  group('mongoDecode', () {
    test('rewrites single-key wrappers', () {
      expect(
        mongoDecode({r'$oid': '507f1f77bcf86cd799439011'}),
        ObjectId.fromHexString('507f1f77bcf86cd799439011'),
      );
      expect(
        mongoDecode({r'$date': '2026-01-02T03:00:00Z'}),
        DateTime.utc(2026, 1, 2, 3),
      );
      expect(
        mongoDecode({
          r'$date': {r'$numberLong': '1000'},
        }),
        DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
      expect(mongoDecode({r'$numberLong': '9007199254740993'}),
          9007199254740993);
      expect(mongoDecode({r'$numberInt': '7'}), 7);
      expect(mongoDecode({r'$numberDouble': '1.5'}), 1.5);
      expect(mongoDecode({r'$numberDecimal': '1.23'}), '1.23');
    });

    test('does not rewrite operator-shaped maps', () {
      expect(mongoDecode({r'$gt': 21}), {r'$gt': 21});
    });

    test('recurses through documents and lists', () {
      final decoded = mongoDecode({
        'items': [
          {
            '_id': {r'$oid': '507f1f77bcf86cd799439011'},
          },
        ],
      }) as Map;
      final item = (decoded['items'] as List).first as Map;
      expect(item['_id'], isA<ObjectId>());
    });

    test('round-trips with mongoEncode', () {
      final original = {
        '_id': ObjectId(),
        'at': DateTime.utc(2026, 7, 18, 9, 30),
        'tags': ['a', 'b'],
        'meta': {'n': 1},
      };
      expect(mongoDecode(mongoEncode(original)), original);
    });
  });
}
