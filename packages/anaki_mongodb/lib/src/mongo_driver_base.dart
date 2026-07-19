/// Low-level driver contract for the MongoDB client.
///
/// Commands are JSON envelopes (`{"op": "find", "collection": ..., ...}`)
/// carried over the shared native FFI surface. Implemented by [MongoDriver]
/// (FFI) and by in-memory fakes in tests.
abstract class MongoDriverBase {
  /// Opens the connection.
  Future<void> rawOpen();

  /// Closes the connection and releases resources.
  Future<void> rawClose();

  /// Checks if the connection is alive.
  Future<bool> rawPing();

  /// Runs a query-path envelope (find/findOne/aggregate/countDocuments/
  /// distinct/runCommand) and returns the resulting rows.
  Future<List<Map<String, dynamic>>> rawQuery(Map<String, dynamic> envelope);

  /// Runs an execute-path envelope (insert/update/delete/index ops) and
  /// returns the affected count.
  Future<int> rawExecute(Map<String, dynamic> envelope);

  /// Runs a batch: [envelope] is the operation template and [documents] the
  /// per-entry payloads. Returns the total affected count.
  Future<int> rawExecuteBatch(
    Map<String, dynamic> envelope,
    List<Map<String, dynamic>> documents,
  );

  /// Begins a transaction (requires a replica set).
  Future<void> rawBeginTransaction();

  /// Commits the current transaction.
  Future<void> rawCommit();

  /// Aborts the current transaction.
  Future<void> rawRollback();
}
