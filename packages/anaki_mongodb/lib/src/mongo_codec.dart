import 'object_id.dart';

/// Deep-converts Dart values to the (extended) JSON the native side expects.
///
/// [ObjectId] becomes `{"$oid": ...}` and [DateTime] becomes `{"$date": ...}`
/// (relaxed extended JSON, always UTC). Plain maps/lists/scalars — including
/// operator keys like `{'$gt': 21}` — pass through untouched.
dynamic mongoEncode(dynamic value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is ObjectId) return {r'$oid': value.hexString};
  if (value is DateTime) return {r'$date': value.toUtc().toIso8601String()};
  if (value is Map) {
    return value.map(
      (k, v) => MapEntry(k as String, mongoEncode(v)),
    );
  }
  if (value is Iterable) return value.map(mongoEncode).toList();
  throw ArgumentError(
    'Cannot encode ${value.runtimeType} as a BSON value. '
    'Convert it to a Map first (e.g. via RowAdapter.toJson).',
  );
}

/// Deep-converts extended JSON coming from the native side to Dart values.
///
/// Only single-key wrapper maps are rewritten (`$oid` → [ObjectId],
/// `$date` → UTC [DateTime], `$numberLong`/`$numberInt` → [int],
/// `$numberDouble` → [double], `$numberDecimal` → [String]); everything else
/// recurses as plain data, so `{'$gt': 21}` inside a document is untouched.
dynamic mongoDecode(dynamic value) {
  if (value is Map) {
    if (value.length == 1) {
      final oid = value[r'$oid'];
      if (oid is String) return ObjectId.fromHexString(oid);

      final date = value[r'$date'];
      if (date is String) return DateTime.parse(date).toUtc();
      if (date is Map) {
        final ms = date[r'$numberLong'];
        if (ms is String) {
          return DateTime.fromMillisecondsSinceEpoch(int.parse(ms), isUtc: true);
        }
      }

      final long = value[r'$numberLong'];
      if (long is String) return int.parse(long);
      final int32 = value[r'$numberInt'];
      if (int32 is String) return int.parse(int32);
      final dbl = value[r'$numberDouble'];
      if (dbl is String) return double.parse(dbl);
      final decimal = value[r'$numberDecimal'];
      if (decimal is String) return decimal;
    }
    return value.map((k, v) => MapEntry(k as String, mongoDecode(v)));
  }
  if (value is List) return value.map(mongoDecode).toList();
  return value;
}
