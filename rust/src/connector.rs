use crate::error::AnakiError;

/// Common trait for all database connectors.
///
/// Each database implementation (SQLite, Postgres, MySQL, etc.)
/// must implement this trait.
#[async_trait::async_trait]
pub trait DatabaseConnector: Send + Sync {
    /// Opens a connection using the provided configuration JSON.
    async fn open(config_json: &str) -> Result<Self, AnakiError>
    where
        Self: Sized;

    /// Closes the connection and releases resources.
    async fn close(&self) -> Result<(), AnakiError>;

    /// Executes a query and returns rows as JSON-serializable maps.
    async fn query(
        &self,
        sql: &str,
        params_json: &str,
    ) -> Result<Vec<serde_json::Map<String, serde_json::Value>>, AnakiError>;

    /// Executes a non-query statement and returns the number of affected rows.
    async fn execute(&self, sql: &str, params_json: &str) -> Result<u64, AnakiError>;

    /// Executes a batch of statements with different parameter sets.
    async fn execute_batch(
        &self,
        sql: &str,
        params_list_json: &str,
    ) -> Result<u64, AnakiError>;

    /// Begins a transaction.
    async fn begin_transaction(&self) -> Result<(), AnakiError>;

    /// Commits the current transaction.
    async fn commit(&self) -> Result<(), AnakiError>;

    /// Rolls back the current transaction.
    async fn rollback(&self) -> Result<(), AnakiError>;

    /// Checks if the connection is alive.
    async fn ping(&self) -> Result<bool, AnakiError>;
}
