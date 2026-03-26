use crate::connector::DatabaseConnector;
use crate::error::AnakiError;
use sqlx::mysql::{MySqlPool, MySqlPoolOptions, MySqlRow};
use sqlx::{Column, Row, TypeInfo};
use std::sync::Arc;
use tokio::sync::Mutex;

/// MySQL connector implementation using sqlx.
pub struct MysqlConnector {
    pool: MySqlPool,
    transaction_conn: Arc<Mutex<Option<sqlx::pool::PoolConnection<sqlx::MySql>>>>,
    in_transaction: Arc<Mutex<bool>>,
}

#[derive(serde::Deserialize)]
struct MysqlConfig {
    host: String,
    #[serde(default = "default_port")]
    port: u16,
    username: String,
    #[serde(default)]
    password: String,
    database: String,
    #[serde(default = "default_min_connections")]
    min_connections: u32,
    #[serde(default = "default_max_connections")]
    max_connections: u32,
}

fn default_port() -> u16 {
    3306
}
fn default_min_connections() -> u32 {
    1
}
fn default_max_connections() -> u32 {
    10
}

fn parse_params(params_json: &str) -> Result<serde_json::Map<String, serde_json::Value>, AnakiError> {
    if params_json.is_empty() || params_json == "{}" || params_json == "null" {
        return Ok(serde_json::Map::new());
    }
    serde_json::from_str(params_json).map_err(|e| {
        AnakiError::query(
            "Failed to parse parameters",
            Some(e.to_string()),
        )
    })
}

/// Replaces named parameters (@name) with positional parameters (?) for MySQL
/// and returns the ordered list of parameter values.
fn prepare_sql(
    sql: &str,
    params: &serde_json::Map<String, serde_json::Value>,
) -> (String, Vec<serde_json::Value>) {
    let mut result_sql = sql.to_string();
    let mut ordered_values = Vec::new();

    let mut replacements: Vec<(usize, usize, String)> = Vec::new();
    let bytes = sql.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'@' {
            let start = i;
            i += 1;
            let param_start = i;
            while i < bytes.len()
                && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'_')
            {
                i += 1;
            }
            if i > param_start {
                let param_name = &sql[param_start..i];
                replacements.push((start, i, param_name.to_string()));
            }
        } else {
            i += 1;
        }
    }

    // Replace from end to start to preserve positions
    for (start, end, _param_name) in replacements.iter().rev() {
        result_sql.replace_range(*start..*end, "?");
    }

    for (_, _, param_name) in &replacements {
        let value = params
            .get(param_name.as_str())
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        ordered_values.push(value);
    }

    (result_sql, ordered_values)
}

fn row_to_map(row: &MySqlRow) -> serde_json::Map<String, serde_json::Value> {
    let mut map = serde_json::Map::new();
    for (i, col) in row.columns().iter().enumerate() {
        let name = col.name().to_string();
        let type_name = col.type_info().name();

        let value: serde_json::Value = match type_name {
            "TINYINT(1)" | "BOOLEAN" | "BOOL" => {
                // MySQL uses TINYINT(1) for booleans
                match row.try_get::<Option<i8>, _>(i) {
                    Ok(Some(v)) => serde_json::Value::Bool(v != 0),
                    _ => serde_json::Value::Null,
                }
            }
            "TINYINT" | "SMALLINT" | "MEDIUMINT" | "INT" | "INTEGER" | "BIGINT"
            | "TINYINT UNSIGNED" | "SMALLINT UNSIGNED" | "MEDIUMINT UNSIGNED"
            | "INT UNSIGNED" | "INTEGER UNSIGNED" | "BIGINT UNSIGNED" => {
                match row.try_get::<Option<i64>, _>(i) {
                    Ok(Some(v)) => serde_json::Value::Number(v.into()),
                    _ => serde_json::Value::Null,
                }
            }
            "FLOAT" => {
                match row.try_get::<Option<f32>, _>(i) {
                    Ok(Some(v)) => serde_json::Number::from_f64(v as f64)
                        .map(serde_json::Value::Number)
                        .unwrap_or(serde_json::Value::Null),
                    _ => serde_json::Value::Null,
                }
            }
            "DOUBLE" | "DECIMAL" | "NUMERIC" => {
                match row.try_get::<Option<f64>, _>(i) {
                    Ok(Some(v)) => serde_json::Number::from_f64(v)
                        .map(serde_json::Value::Number)
                        .unwrap_or(serde_json::Value::Null),
                    _ => {
                        // DECIMAL might not decode as f64, try as string
                        match row.try_get::<Option<String>, _>(i) {
                            Ok(Some(v)) => serde_json::Value::String(v),
                            _ => serde_json::Value::Null,
                        }
                    }
                }
            }
            "VARCHAR" | "CHAR" | "TEXT" | "TINYTEXT" | "MEDIUMTEXT" | "LONGTEXT"
            | "ENUM" | "SET" => {
                match row.try_get::<Option<String>, _>(i) {
                    Ok(Some(v)) => serde_json::Value::String(v),
                    _ => serde_json::Value::Null,
                }
            }
            "BLOB" | "TINYBLOB" | "MEDIUMBLOB" | "LONGBLOB" | "BINARY" | "VARBINARY" => {
                match row.try_get::<Option<Vec<u8>>, _>(i) {
                    Ok(Some(v)) => {
                        use std::fmt::Write;
                        let mut hex = String::with_capacity(v.len() * 2);
                        for byte in &v {
                            write!(hex, "{:02x}", byte).unwrap();
                        }
                        serde_json::Value::String(hex)
                    }
                    _ => serde_json::Value::Null,
                }
            }
            "JSON" => {
                match row.try_get::<Option<serde_json::Value>, _>(i) {
                    Ok(Some(v)) => v,
                    _ => serde_json::Value::Null,
                }
            }
            "DATE" | "TIME" | "DATETIME" | "TIMESTAMP" | "YEAR" => {
                match row.try_get::<Option<String>, _>(i) {
                    Ok(Some(v)) => serde_json::Value::String(v),
                    _ => serde_json::Value::Null,
                }
            }
            // Fallback: try i64, f64, String in order
            _ => {
                match row.try_get::<Option<i64>, _>(i) {
                    Ok(Some(v)) => serde_json::Value::Number(v.into()),
                    _ => match row.try_get::<Option<f64>, _>(i) {
                        Ok(Some(v)) => serde_json::Number::from_f64(v)
                            .map(serde_json::Value::Number)
                            .unwrap_or(serde_json::Value::Null),
                        _ => match row.try_get::<Option<String>, _>(i) {
                            Ok(Some(v)) => serde_json::Value::String(v),
                            _ => serde_json::Value::Null,
                        },
                    },
                }
            }
        };

        map.insert(name, value);
    }
    map
}

fn bind_params<'q>(
    mut query: sqlx::query::Query<'q, sqlx::MySql, sqlx::mysql::MySqlArguments>,
    values: &'q [serde_json::Value],
) -> sqlx::query::Query<'q, sqlx::MySql, sqlx::mysql::MySqlArguments> {
    for value in values {
        query = match value {
            serde_json::Value::Null => query.bind(None::<String>),
            serde_json::Value::Bool(b) => query.bind(*b),
            serde_json::Value::Number(n) => {
                if let Some(i) = n.as_i64() {
                    query.bind(i)
                } else if let Some(f) = n.as_f64() {
                    query.bind(f)
                } else {
                    query.bind(n.to_string())
                }
            }
            serde_json::Value::String(s) => query.bind(s.as_str()),
            _ => query.bind(value.to_string()),
        };
    }
    query
}

#[async_trait::async_trait]
impl DatabaseConnector for MysqlConnector {
    async fn open(config_json: &str) -> Result<Self, AnakiError> {
        let config: MysqlConfig = serde_json::from_str(config_json).map_err(|e| {
            AnakiError::connection(format!("Invalid config: {}", e))
        })?;

        let url = format!(
            "mysql://{}:{}@{}:{}/{}",
            config.username, config.password, config.host, config.port, config.database
        );

        let pool = MySqlPoolOptions::new()
            .min_connections(config.min_connections)
            .max_connections(config.max_connections)
            .connect(&url)
            .await
            .map_err(|e| AnakiError::connection(format!("Failed to connect: {}", e)))?;

        Ok(Self {
            pool,
            transaction_conn: Arc::new(Mutex::new(None)),
            in_transaction: Arc::new(Mutex::new(false)),
        })
    }

    async fn close(&self) -> Result<(), AnakiError> {
        self.pool.close().await;
        Ok(())
    }

    async fn query(
        &self,
        sql: &str,
        params_json: &str,
    ) -> Result<Vec<serde_json::Map<String, serde_json::Value>>, AnakiError> {
        let params = parse_params(params_json)?;
        let (prepared_sql, values) = prepare_sql(sql, &params);

        let query = sqlx::query(&prepared_sql);
        let query = bind_params(query, &values);

        let mut tx_guard = self.transaction_conn.lock().await;
        let rows = if let Some(ref mut conn) = *tx_guard {
            query.fetch_all(&mut **conn).await.map_err(AnakiError::from)?
        } else {
            query.fetch_all(&self.pool).await.map_err(AnakiError::from)?
        };

        Ok(rows.iter().map(row_to_map).collect())
    }

    async fn execute(&self, sql: &str, params_json: &str) -> Result<u64, AnakiError> {
        let params = parse_params(params_json)?;
        let (prepared_sql, values) = prepare_sql(sql, &params);

        let query = sqlx::query(&prepared_sql);
        let query = bind_params(query, &values);

        let mut tx_guard = self.transaction_conn.lock().await;
        let result = if let Some(ref mut conn) = *tx_guard {
            query.execute(&mut **conn).await.map_err(AnakiError::from)?
        } else {
            query.execute(&self.pool).await.map_err(AnakiError::from)?
        };

        Ok(result.rows_affected())
    }

    async fn execute_batch(
        &self,
        sql: &str,
        params_list_json: &str,
    ) -> Result<u64, AnakiError> {
        let params_list: Vec<serde_json::Map<String, serde_json::Value>> =
            serde_json::from_str(params_list_json).map_err(|e| {
                AnakiError::query("Failed to parse batch parameters", Some(e.to_string()))
            })?;

        let mut total_affected = 0u64;
        let mut tx_guard = self.transaction_conn.lock().await;

        for params in &params_list {
            let (prepared_sql, values) = prepare_sql(sql, params);
            let query = sqlx::query(&prepared_sql);
            let query = bind_params(query, &values);

            let result = if let Some(ref mut conn) = *tx_guard {
                query.execute(&mut **conn).await.map_err(AnakiError::from)?
            } else {
                query.execute(&self.pool).await.map_err(AnakiError::from)?
            };
            total_affected += result.rows_affected();
        }

        Ok(total_affected)
    }

    async fn begin_transaction(&self) -> Result<(), AnakiError> {
        let mut conn = self.pool.acquire().await
            .map_err(|e| AnakiError::transaction(format!("Failed to acquire connection: {}", e)))?;

        // MySQL doesn't support BEGIN/START TRANSACTION as prepared statements.
        // Use execute_unprepared via raw_sql on the underlying connection.
        {
            use sqlx::Executor;
            conn.execute("START TRANSACTION").await
                .map_err(|e| AnakiError::transaction(format!("Failed to begin transaction: {}", e)))?;
        }

        let mut tx_conn = self.transaction_conn.lock().await;
        *tx_conn = Some(conn);
        let mut in_tx = self.in_transaction.lock().await;
        *in_tx = true;
        Ok(())
    }

    async fn commit(&self) -> Result<(), AnakiError> {
        let mut tx_conn = self.transaction_conn.lock().await;
        if let Some(mut conn) = tx_conn.take() {
            use sqlx::Executor;
            conn.execute("COMMIT").await
                .map_err(|e| AnakiError::transaction(format!("Failed to commit: {}", e)))?;
        } else {
            return Err(AnakiError::transaction("No active transaction"));
        }
        let mut in_tx = self.in_transaction.lock().await;
        *in_tx = false;
        Ok(())
    }

    async fn rollback(&self) -> Result<(), AnakiError> {
        let mut tx_conn = self.transaction_conn.lock().await;
        if let Some(mut conn) = tx_conn.take() {
            use sqlx::Executor;
            conn.execute("ROLLBACK").await
                .map_err(|e| AnakiError::transaction(format!("Failed to rollback: {}", e)))?;
        } else {
            return Err(AnakiError::transaction("No active transaction"));
        }
        let mut in_tx = self.in_transaction.lock().await;
        *in_tx = false;
        Ok(())
    }

    async fn ping(&self) -> Result<bool, AnakiError> {
        match sqlx::query("SELECT 1").fetch_one(&self.pool).await {
            Ok(_) => Ok(true),
            Err(_) => Ok(false),
        }
    }
}
