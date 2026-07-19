import 'package:anaki_mongodb/anaki_mongodb.dart';
import 'package:test/test.dart';

void main() {
  group('ObjectId', () {
    test('generates unique 24-char lowercase hex ids', () {
      final ids = List.generate(1000, (_) => ObjectId().hexString).toSet();
      expect(ids, hasLength(1000));
      for (final id in ids.take(10)) {
        expect(id, matches(r'^[0-9a-f]{24}$'));
      }
    });

    test('fromHexString validates and normalizes case', () {
      final id = ObjectId.fromHexString('507F1F77BCF86CD799439011');
      expect(id.hexString, '507f1f77bcf86cd799439011');
      expect(() => ObjectId.fromHexString('nope'), throwsArgumentError);
      expect(
        () => ObjectId.fromHexString('507f1f77bcf86cd79943901'),
        throwsArgumentError,
      );
    });

    test('timestamp decodes the leading 4 bytes', () {
      final id = ObjectId.fromHexString('65a5f1f70000000000000000');
      expect(
        id.timestamp,
        DateTime.fromMillisecondsSinceEpoch(0x65a5f1f7 * 1000, isUtc: true),
      );
      final fresh = ObjectId();
      expect(
        DateTime.now().toUtc().difference(fresh.timestamp).inSeconds.abs(),
        lessThan(5),
      );
    });

    test('equality and toString', () {
      final a = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      final b = ObjectId.fromHexString('507f1f77bcf86cd799439011');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), '507f1f77bcf86cd799439011');
      expect(a.toJson(), {r'$oid': '507f1f77bcf86cd799439011'});
    });
  });
}
