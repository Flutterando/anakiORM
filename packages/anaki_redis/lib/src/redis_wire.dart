import 'package:anaki_orm/anaki_orm.dart';

/// Throws the appropriate exception if [response] carries an error.
///
/// [command] is the rendered command (e.g. `GET user:1`) and is exposed via
/// [QueryException.sql] for debugging. Note: argument values appear in it —
/// avoid logging exceptions verbatim if values are sensitive.
void checkWireError(Map<String, dynamic> response, {String? command}) {
  if (!response.containsKey('error')) return;

  final error = response['error'] as Map<String, dynamic>;
  final code = error['code'] as String;
  final message = error['message'] as String;
  final details = error['details'] as String?;

  switch (code) {
    case 'CONNECTION_ERROR':
      throw ConnectionException(message, details: details);
    case 'QUERY_ERROR':
      throw QueryException(message, sql: command, details: details);
    case 'TRANSACTION_ERROR':
      throw TransactionException(message, details: details);
    default:
      throw AnakiException(message, details: details);
  }
}

/// Unwraps the reply of a single-command query response.
///
/// The native side always returns one row `{"result": <reply>}`.
dynamic unwrapQueryResult(Map<String, dynamic> response) {
  final ok = response['ok'] as Map<String, dynamic>;
  final rows = ok['rows'] as List<dynamic>;
  if (rows.isEmpty) return null;
  return (rows.first as Map)['result'];
}
