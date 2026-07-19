/// Encodes command arguments to the string form Redis expects.
///
/// Strings pass through; `int`/`double` use `toString()`; `bool` becomes
/// `'true'`/`'false'` (Redis has no boolean type — this is a stored-string
/// convention). Anything else must be converted explicitly by the caller
/// (e.g. via `setJson`/`RowAdapter`).
List<String> encodeRedisArgs(List<Object?> parts) {
  return List<String>.generate(parts.length, (i) {
    final part = parts[i];
    if (part is String) return part;
    if (part is num) return part.toString();
    if (part is bool) return part.toString();
    if (part == null) {
      throw ArgumentError('null is not a valid Redis argument (index $i)');
    }
    throw ArgumentError(
      'Cannot encode ${part.runtimeType} as a Redis argument (index $i). '
      'Convert it to a String first (e.g. jsonEncode or RowAdapter).',
    );
  });
}

/// Coerces an integer-shaped reply (RESP2 may deliver numerics as strings).
int replyAsInt(dynamic reply) {
  if (reply is int) return reply;
  if (reply is String) return int.parse(reply);
  if (reply == null) return 0;
  throw StateError('Unexpected Redis reply for an integer: $reply');
}

/// Coerces a double-shaped reply, `null` for nil.
double? replyAsDoubleOrNull(dynamic reply) {
  if (reply == null) return null;
  if (reply is num) return reply.toDouble();
  if (reply is String) return double.parse(reply);
  throw StateError('Unexpected Redis reply for a double: $reply');
}

/// Coerces a boolean-shaped reply (1/0, true/false).
bool replyAsBool(dynamic reply) {
  if (reply is bool) return reply;
  if (reply is int) return reply != 0;
  if (reply is String) return reply == '1' || reply == 'true' || reply == 'OK';
  return false;
}

/// Coerces an array reply to a list of strings.
List<String> replyAsStringList(dynamic reply) {
  if (reply == null) return const [];
  return (reply as List).map((e) => e.toString()).toList();
}

/// Coerces an array reply to a list of nullable strings (MGET).
List<String?> replyAsNullableStringList(dynamic reply) {
  if (reply == null) return const [];
  return (reply as List).map((e) => e?.toString()).toList();
}

/// Coerces a map-shaped reply to `Map<String, String>`.
///
/// Accepts either a JSON object (RESP3 map replies) or a flat pair array
/// `[field1, value1, field2, value2, ...]` (RESP2 form of HGETALL etc.),
/// making callers immune to protocol negotiation.
Map<String, String> replyAsStringMap(dynamic reply) {
  if (reply == null) return const {};
  if (reply is Map) {
    return reply.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
  final list = reply as List;
  final map = <String, String>{};
  for (var i = 0; i + 1 < list.length; i += 2) {
    map[list[i].toString()] = list[i + 1].toString();
  }
  return map;
}

/// Folds a WITHSCORES reply into (member, score) records.
///
/// Accepts the RESP2 flat form `[m1, s1, m2, s2, ...]`, the RESP3 pair form
/// `[[m1, s1], [m2, s2]]`, or a map.
List<({String member, double score})> replyAsScoredMembers(dynamic reply) {
  if (reply == null) return const [];
  if (reply is Map) {
    return reply.entries
        .map((e) => (
              member: e.key.toString(),
              score: replyAsDoubleOrNull(e.value) ?? 0,
            ))
        .toList();
  }
  final list = reply as List;
  if (list.isEmpty) return const [];
  if (list.first is List) {
    return list
        .map((pair) => (
              member: (pair as List)[0].toString(),
              score: replyAsDoubleOrNull(pair[1]) ?? 0,
            ))
        .toList();
  }
  final result = <({String member, double score})>[];
  for (var i = 0; i + 1 < list.length; i += 2) {
    result.add((
      member: list[i].toString(),
      score: replyAsDoubleOrNull(list[i + 1]) ?? 0,
    ));
  }
  return result;
}
