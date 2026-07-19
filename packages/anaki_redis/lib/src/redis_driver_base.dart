/// Low-level driver contract for the Redis client.
///
/// Deliberately minimal: single commands flow through [rawCommand]
/// (`anaki_query` on the native side) and atomic MULTI/EXEC batches through
/// [rawPipeline] (`anaki_execute_batch`). There are no transaction methods —
/// the native connector rejects them by contract, and excluding them from the
/// interface makes calling them structurally impossible.
///
/// Implemented by [RedisDriver] (FFI) and by in-memory fakes in tests.
abstract class RedisDriverBase {
  /// Opens the connection.
  Future<void> rawOpen();

  /// Closes the connection and releases resources.
  Future<void> rawClose();

  /// Checks if the connection is alive (PING).
  Future<bool> rawPing();

  /// Sends a single command (e.g. `["GET", "key"]`) and returns the
  /// decoded reply (`null` for nil, `int`, `String`, `List`, or `Map`).
  Future<dynamic> rawCommand(List<String> parts);

  /// Runs an atomic MULTI/EXEC pipeline.
  ///
  /// Returns the number of commands applied.
  Future<int> rawPipeline(List<List<String>> commands);
}
