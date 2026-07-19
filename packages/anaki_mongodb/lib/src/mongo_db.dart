import 'package:anaki_orm/anaki_orm.dart';

import 'mongo_codec.dart';
import 'mongo_driver_base.dart';
import 'object_id.dart';

part 'mongo_collection.dart';

/// Main entry point for AnakiORM MongoDB operations.
///
/// ```dart
/// final mongo = AnakiMongoDb(MongoDriver(host: 'localhost', database: 'app'));
/// await mongo.open();
///
/// final users = mongo.collection('users');
/// final id = await users.insertOne({'name': 'Ana'});
/// final ana = await users.findOne({'_id': id});
///
/// await mongo.transaction((tx) async {
///   await tx.collection('accounts').updateOne({'_id': a}, {r'$inc': {'balance': -100}});
///   await tx.collection('accounts').updateOne({'_id': b}, {r'$inc': {'balance': 100}});
/// });
///
/// await mongo.close();
/// ```
class AnakiMongoDb {
  final MongoDriverBase _driver;
  final RowAdapter? _adapter;
  final bool _codec;
  bool _isOpen = false;

  /// Creates the client over [driver].
  ///
  /// [extendedJsonCodec] (default true) converts [ObjectId]/[DateTime] to and
  /// from extended JSON at the boundary; disable it to work with raw relaxed
  /// extended JSON maps yourself.
  AnakiMongoDb(
    MongoDriverBase driver, {
    bool extendedJsonCodec = true,
    RowAdapter? adapter,
  })  : _driver = driver,
        _codec = extendedJsonCodec,
        _adapter = adapter;

  /// Whether the connection is currently open.
  bool get isOpen => _isOpen;

  /// Opens the connection.
  Future<void> open() async {
    await _driver.rawOpen();
    _isOpen = true;
  }

  /// Closes the connection.
  Future<void> close() async {
    await _driver.rawClose();
    _isOpen = false;
  }

  /// Checks if the connection is alive.
  Future<bool> ping() async {
    _ensureOpen();
    return _driver.rawPing();
  }

  /// Returns a view over collection [name].
  MongoCollection collection(String name) => MongoCollection._(this, name);

  /// Runs a raw database command (escape hatch for anything without a
  /// typed wrapper, e.g. `{'ping': 1}` or `{'listCollections': 1}`).
  Future<Map<String, dynamic>> runCommand(Map<String, dynamic> command) async {
    final rows = await _query({'op': 'runCommand', 'command': command});
    return rows.isEmpty ? <String, dynamic>{} : rows.first;
  }

  /// Executes operations within a transaction (requires a replica set).
  ///
  /// If the callback completes successfully, the transaction is committed.
  /// If an exception is thrown, the transaction is rolled back and the
  /// exception is rethrown.
  Future<void> transaction(Future<void> Function(AnakiMongoDb tx) action) async {
    _ensureOpen();
    await _driver.rawBeginTransaction();
    try {
      await action(this);
      await _driver.rawCommit();
    } catch (e) {
      try {
        await _driver.rawRollback();
      } catch (rollbackError) {
        throw TransactionException(
          'Transaction rollback failed',
          details: 'Original error: $e\nRollback error: $rollbackError',
        );
      }
      rethrow;
    }
  }

  void _ensureOpen() {
    if (!_isOpen) {
      throw const NotConnectedException();
    }
  }

  Map<String, dynamic> _encodeEnvelope(Map<String, dynamic> envelope) {
    if (!_codec) return envelope;
    return (mongoEncode(envelope) as Map).cast<String, dynamic>();
  }

  Map<String, dynamic> _decodeRow(Map<String, dynamic> row) {
    if (!_codec) return row;
    return (mongoDecode(row) as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> _query(
    Map<String, dynamic> envelope,
  ) async {
    _ensureOpen();
    final rows = await _driver.rawQuery(_encodeEnvelope(envelope));
    return rows.map(_decodeRow).toList();
  }

  Future<int> _execute(Map<String, dynamic> envelope) async {
    _ensureOpen();
    return _driver.rawExecute(_encodeEnvelope(envelope));
  }

  Future<int> _executeBatch(
    Map<String, dynamic> envelope,
    List<Map<String, dynamic>> documents,
  ) async {
    _ensureOpen();
    final encodedDocs = _codec
        ? documents
            .map((d) => (mongoEncode(d) as Map).cast<String, dynamic>())
            .toList()
        : documents;
    return _driver.rawExecuteBatch(_encodeEnvelope(envelope), encodedDocs);
  }

  List<T> _mapRows<T>(
    List<Map<String, dynamic>> rows,
    T Function(Map<String, dynamic>)? map,
  ) {
    if (map != null) return rows.map(map).toList();
    final adapter = _adapter;
    if (adapter != null && T != dynamic && T != Map<String, dynamic>) {
      return rows.map((r) => adapter.fromJson<T>(r)).toList();
    }
    return rows as List<T>;
  }
}
