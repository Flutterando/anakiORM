/// SQL dialect hint used by [AnakiDb] to generate dialect-specific SQL.
enum SqlDialect {
  /// Standard SQL (PostgreSQL, MySQL): uses LIMIT/OFFSET, SERIAL for auto-increment.
  generic,

  /// SQLite: uses LIMIT/OFFSET, INTEGER PRIMARY KEY AUTOINCREMENT.
  sqlite,

  /// SQL Server (T-SQL): uses OFFSET/FETCH, INT IDENTITY(1,1).
  mssql,
}

/// Base interface for all AnakiORM database drivers.
///
/// Each driver package (anaki_postgres, anaki_mysql, anaki_sqlite, etc.)
/// must provide a concrete implementation of this interface.
///
/// The driver handles the low-level communication with the native Rust
/// connector via FFI. All data exchange uses JSON strings internally.
abstract class AnakiDriver {
  /// The SQL dialect used by this driver.
  ///
  /// Defaults to [SqlDialect.generic]. Override in drivers that need
  /// dialect-specific SQL generation (e.g. SQL Server).
  SqlDialect get dialect => SqlDialect.generic;

  /// Opens the database connection.
  Future<void> rawOpen();

  /// Closes the database connection and releases resources.
  Future<void> rawClose();

  /// Executes a query and returns the result as a list of row maps.
  ///
  /// [sql] is the SQL query string with named parameters (e.g. `@name`).
  /// [params] is an optional map of parameter names to values.
  Future<List<Map<String, dynamic>>> rawQuery(
    String sql,
    Map<String, dynamic>? params,
  );

  /// Executes a non-query statement (INSERT, UPDATE, DELETE) and returns
  /// the number of affected rows.
  Future<int> rawExecute(String sql, Map<String, dynamic>? params);

  /// Executes a batch of statements with different parameter sets.
  ///
  /// Returns the total number of affected rows.
  Future<int> rawExecuteBatch(
    String sql,
    List<Map<String, dynamic>> paramsList,
  );

  /// Begins a new transaction.
  Future<void> rawBeginTransaction();

  /// Commits the current transaction.
  Future<void> rawCommit();

  /// Rolls back the current transaction.
  Future<void> rawRollback();

  /// Checks if the connection is alive.
  Future<bool> rawPing();
}
