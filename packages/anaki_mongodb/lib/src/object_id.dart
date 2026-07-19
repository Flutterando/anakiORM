import 'dart:math';

/// A BSON ObjectId: 12 bytes rendered as 24 lowercase hex characters.
///
/// Generated client-side with the standard layout — 4-byte seconds timestamp
/// (big-endian) + 5 random bytes (fixed per isolate) + 3-byte counter.
class ObjectId {
  static final Random _random = Random.secure();
  static final List<int> _processRandom =
      List<int>.unmodifiable(List<int>.generate(5, (_) => _random.nextInt(256)));
  static int _counter = _random.nextInt(0xFFFFFF);

  /// The 24-character lowercase hex representation.
  final String hexString;

  ObjectId._(this.hexString);

  /// Generates a new id.
  factory ObjectId() {
    final seconds =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
    _counter = (_counter + 1) & 0xFFFFFF;
    final bytes = <int>[
      (seconds >> 24) & 0xFF,
      (seconds >> 16) & 0xFF,
      (seconds >> 8) & 0xFF,
      seconds & 0xFF,
      ..._processRandom,
      (_counter >> 16) & 0xFF,
      (_counter >> 8) & 0xFF,
      _counter & 0xFF,
    ];
    return ObjectId._(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
  }

  /// Parses a 24-character hex string; throws [ArgumentError] otherwise.
  factory ObjectId.fromHexString(String hex) {
    if (!RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(hex)) {
      throw ArgumentError.value(
        hex,
        'hex',
        'Expected 24 hexadecimal characters',
      );
    }
    return ObjectId._(hex.toLowerCase());
  }

  /// The creation time encoded in the id (UTC, second precision).
  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(
        int.parse(hexString.substring(0, 8), radix: 16) *
            Duration.millisecondsPerSecond,
        isUtc: true,
      );

  /// Extended JSON form, for use in raw `runCommand` payloads.
  Map<String, dynamic> toJson() => {r'$oid': hexString};

  @override
  bool operator ==(Object other) =>
      other is ObjectId && other.hexString == hexString;

  @override
  int get hashCode => hexString.hashCode;

  @override
  String toString() => hexString;
}
