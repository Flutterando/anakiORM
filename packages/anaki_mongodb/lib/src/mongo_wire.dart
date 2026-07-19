import 'package:anaki_orm/anaki_orm.dart';

/// Throws the appropriate exception if [response] carries an error.
///
/// [statement] is the JSON command envelope sent on the wire and is exposed
/// via [QueryException.sql] for debugging (filters visible — avoid logging
/// exceptions verbatim if values are sensitive).
void checkWireError(Map<String, dynamic> response, {String? statement}) {
  if (!response.containsKey('error')) return;

  final error = response['error'] as Map<String, dynamic>;
  final code = error['code'] as String;
  final message = error['message'] as String;
  final details = error['details'] as String?;

  switch (code) {
    case 'CONNECTION_ERROR':
      throw ConnectionException(message, details: details);
    case 'QUERY_ERROR':
      throw QueryException(message, sql: statement, details: details);
    case 'TRANSACTION_ERROR':
      throw TransactionException(message, details: details);
    default:
      throw AnakiException(message, details: details);
  }
}
