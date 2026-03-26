// TODO: Implement OracleDriver
//
// Rust deps: sibyl or oracle (OCI wrapper)
// NOTE: Requires Oracle Instant Client installed on the host.
// FFI interface identical to anaki_sqlite.

import 'package:anaki_orm/anaki_orm.dart';

class OracleDriver implements AnakiDriver {
  // ignore: unused_field
  final String _connectionString;

  OracleDriver(this._connectionString);

  @override
  SqlDialect get dialect => SqlDialect.generic;

  @override
  Future<void> rawOpen() =>
      throw UnimplementedError('OracleDriver not yet implemented');
  @override
  Future<void> rawClose() =>
      throw UnimplementedError('OracleDriver not yet implemented');
  @override
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql,
    Map<String, dynamic>? params,
  ) => throw UnimplementedError('OracleDriver not yet implemented');
  @override
  Future<int> rawExecute(String sql, Map<String, dynamic>? params) =>
      throw UnimplementedError('OracleDriver not yet implemented');
  @override
  Future<int> rawExecuteBatch(
    String sql,
    List<Map<String, dynamic>> paramsList,
  ) => throw UnimplementedError('OracleDriver not yet implemented');
  @override
  Future<void> rawBeginTransaction() =>
      throw UnimplementedError('OracleDriver not yet implemented');
  @override
  Future<void> rawCommit() =>
      throw UnimplementedError('OracleDriver not yet implemented');
  @override
  Future<void> rawRollback() =>
      throw UnimplementedError('OracleDriver not yet implemented');
  @override
  Future<bool> rawPing() =>
      throw UnimplementedError('OracleDriver not yet implemented');
}
