/// Base exception for all AnakiORM errors.
class AnakiException implements Exception {
  final String message;
  final String? details;

  const AnakiException(this.message, {this.details});

  @override
  String toString() {
    if (details != null) {
      return 'AnakiException: $message\nDetails: $details';
    }
    return 'AnakiException: $message';
  }
}

/// Thrown when a connection cannot be established or is lost.
class ConnectionException extends AnakiException {
  const ConnectionException(super.message, {super.details});

  @override
  String toString() {
    if (details != null) {
      return 'ConnectionException: $message\nDetails: $details';
    }
    return 'ConnectionException: $message';
  }
}

/// Thrown when a SQL query fails to execute.
class QueryException extends AnakiException {
  final String? sql;

  const QueryException(super.message, {this.sql, super.details});

  @override
  String toString() {
    final buffer = StringBuffer('QueryException: $message');
    if (sql != null) buffer.write('\nSQL: $sql');
    if (details != null) buffer.write('\nDetails: $details');
    return buffer.toString();
  }
}

/// Thrown when a transaction operation fails.
class TransactionException extends AnakiException {
  const TransactionException(super.message, {super.details});

  @override
  String toString() {
    if (details != null) {
      return 'TransactionException: $message\nDetails: $details';
    }
    return 'TransactionException: $message';
  }
}

/// Thrown when the driver is not connected and an operation is attempted.
class NotConnectedException extends AnakiException {
  const NotConnectedException()
      : super('Not connected. Call open() before performing operations.');
}
