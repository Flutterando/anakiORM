/// Configuration for the database connection pool.
class PoolConfig {
  /// Minimum number of connections to keep open.
  final int minConnections;

  /// Maximum number of connections allowed.
  final int maxConnections;

  /// Time in seconds before an idle connection is closed.
  final int idleTimeoutSeconds;

  /// Time in seconds to wait for a connection from the pool.
  final int acquireTimeoutSeconds;

  const PoolConfig({
    this.minConnections = 1,
    this.maxConnections = 10,
    this.idleTimeoutSeconds = 300,
    this.acquireTimeoutSeconds = 30,
  });

  Map<String, dynamic> toJson() => {
        'min_connections': minConnections,
        'max_connections': maxConnections,
        'idle_timeout_seconds': idleTimeoutSeconds,
        'acquire_timeout_seconds': acquireTimeoutSeconds,
      };
}
