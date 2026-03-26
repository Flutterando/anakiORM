use crate::connector::DatabaseConnector;
use crate::error::AnakiError;
use tiberius::{AuthMethod, Client, Config, ColumnType, Query};
use tokio::net::TcpStream;
use tokio_util::compat::{Compat, TokioAsyncWriteCompatExt};
use std::sync::Arc;
use tokio::sync::Mutex;

type MssqlClient = Client<Compat<TcpStream>>;

/// SQL Server connector implementation using tiberius.
pub struct MssqlConnector {
    client: Arc<Mutex<MssqlClient>>,
    in_transaction: Arc<Mutex<bool>>,
}

#[derive(serde::Deserialize)]
struct MssqlConfig {
    host: String,
    #[serde(default = "default_port")]
    port: u16,
    username: String,
    #[serde(default)]
    password: String,
    database: String,
    #[serde(default)]
    trust_cert: bool,
    #[serde(default)]
    encrypt: Option<bool>,
}

fn default_port() -> u16 {
    1433
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

/// Replaces named parameters (@name) with tiberius positional parameters (@P1, @P2, ...)
/// and returns the ordered list of parameter values.
fn prepare_sql(
    sql: &str,
    params: &serde_json::Map<String, serde_json::Value>,
) -> (String, Vec<serde_json::Value>) {
    let mut result_sql = String::with_capacity(sql.len());
    let mut ordered_values = Vec::new();
    let mut param_index = 0u32;

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
                // Skip tiberius positional params like @P1, @P2
                if param_name.starts_with('P') && param_name[1..].parse::<u32>().is_ok() {
                    result_sql.push_str(&sql[start..i]);
                } else {
                    param_index += 1;
                    result_sql.push_str(&format!("@P{}", param_index));
                    let value = params
                        .get(param_name)
                        .cloned()
                        .unwrap_or(serde_json::Value::Null);
                    ordered_values.push(value);
                }
            } else {
                result_sql.push_str(&sql[start..i]);
            }
        } else {
            result_sql.push(sql[i..].chars().next().unwrap());
            i += 1;
        }
    }

    (result_sql, ordered_values)
}

fn row_to_map(row: &tiberius::Row) -> serde_json::Map<String, serde_json::Value> {
    let mut map = serde_json::Map::new();
    for col in row.columns() {
        let name = col.name().to_string();
        let col_type = col.column_type();

        let value: serde_json::Value = match col_type {
            ColumnType::Bit => {
                match row.try_get::<bool, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::Bool(v),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Int1 => {
                match row.try_get::<u8, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::Number((v as i64).into()),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Int2 => {
                match row.try_get::<i16, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::Number((v as i64).into()),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Int4 => {
                match row.try_get::<i32, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::Number((v as i64).into()),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Int8 => {
                match row.try_get::<i64, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::Number(v.into()),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Intn => {
                // Try largest int first
                match row.try_get::<i64, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::Number(v.into()),
                    _ => match row.try_get::<i32, _>(name.as_str()) {
                        Ok(Some(v)) => serde_json::Value::Number((v as i64).into()),
                        _ => serde_json::Value::Null,
                    },
                }
            }
            ColumnType::Float4 => {
                match row.try_get::<f32, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Number::from_f64(v as f64)
                        .map(serde_json::Value::Number)
                        .unwrap_or(serde_json::Value::Null),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Float8 => {
                match row.try_get::<f64, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Number::from_f64(v)
                        .map(serde_json::Value::Number)
                        .unwrap_or(serde_json::Value::Null),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Floatn => {
                match row.try_get::<f64, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Number::from_f64(v)
                        .map(serde_json::Value::Number)
                        .unwrap_or(serde_json::Value::Null),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::BigVarChar | ColumnType::BigChar | ColumnType::NVarchar | ColumnType::NChar
            | ColumnType::Text | ColumnType::NText => {
                match row.try_get::<&str, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::String(v.to_string()),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::BigBinary | ColumnType::BigVarBin => {
                match row.try_get::<&[u8], _>(name.as_str()) {
                    Ok(Some(v)) => {
                        use std::fmt::Write;
                        let mut hex = String::with_capacity(v.len() * 2);
                        for byte in v {
                            write!(hex, "{:02x}", byte).unwrap();
                        }
                        serde_json::Value::String(hex)
                    }
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Decimaln | ColumnType::Numericn => {
                match row.try_get::<f64, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Number::from_f64(v)
                        .map(serde_json::Value::Number)
                        .unwrap_or(serde_json::Value::Null),
                    _ => match row.try_get::<&str, _>(name.as_str()) {
                        Ok(Some(v)) => serde_json::Value::String(v.to_string()),
                        _ => serde_json::Value::Null,
                    },
                }
            }
            ColumnType::Datetime | ColumnType::Datetime2 | ColumnType::Datetime4
            | ColumnType::Datetimen | ColumnType::DatetimeOffsetn | ColumnType::Daten
            | ColumnType::Timen => {
                match row.try_get::<&str, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::String(v.to_string()),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Guid => {
                match row.try_get::<&str, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::String(v.to_string()),
                    _ => serde_json::Value::Null,
                }
            }
            ColumnType::Bitn => {
                match row.try_get::<bool, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::Bool(v),
                    _ => serde_json::Value::Null,
                }
            }
            // Fallback
            _ => {
                match row.try_get::<i64, _>(name.as_str()) {
                    Ok(Some(v)) => serde_json::Value::Number(v.into()),
                    _ => match row.try_get::<f64, _>(name.as_str()) {
                        Ok(Some(v)) => serde_json::Number::from_f64(v)
                            .map(serde_json::Value::Number)
                            .unwrap_or(serde_json::Value::Null),
                        _ => match row.try_get::<&str, _>(name.as_str()) {
                            Ok(Some(v)) => serde_json::Value::String(v.to_string()),
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

fn bind_query<'a>(query: &mut Query<'a>, values: &'a [serde_json::Value]) {
    for value in values {
        match value {
            serde_json::Value::Null => query.bind(Option::<String>::None),
            serde_json::Value::Bool(b) => query.bind(*b),
            serde_json::Value::Number(n) => {
                if let Some(i) = n.as_i64() {
                    query.bind(i);
                } else if let Some(f) = n.as_f64() {
                    query.bind(f);
                } else {
                    query.bind(n.to_string());
                }
            }
            serde_json::Value::String(s) => query.bind(s.as_str()),
            _ => query.bind(value.to_string()),
        }
    }
}

async fn connect(config_json: &str) -> Result<MssqlClient, AnakiError> {
    let config_parsed: MssqlConfig = serde_json::from_str(config_json).map_err(|e| {
        AnakiError::connection(format!("Invalid config: {}", e))
    })?;

    let mut config = Config::new();
    config.host(&config_parsed.host);
    config.port(config_parsed.port);
    config.database(&config_parsed.database);
    config.authentication(AuthMethod::sql_server(&config_parsed.username, &config_parsed.password));

    if config_parsed.trust_cert {
        config.trust_cert();
    }

    if let Some(encrypt) = config_parsed.encrypt {
        if encrypt {
            config.encryption(tiberius::EncryptionLevel::Required);
        } else {
            config.encryption(tiberius::EncryptionLevel::NotSupported);
        }
    }

    let tcp = TcpStream::connect(config.get_addr()).await
        .map_err(|e| AnakiError::connection(format!("Failed to connect TCP: {}", e)))?;
    tcp.set_nodelay(true)
        .map_err(|e| AnakiError::connection(format!("Failed to set nodelay: {}", e)))?;

    let client = Client::connect(config, tcp.compat_write()).await
        .map_err(|e| AnakiError::connection(format!("Failed to connect: {}", e)))?;

    Ok(client)
}

#[async_trait::async_trait]
impl DatabaseConnector for MssqlConnector {
    async fn open(config_json: &str) -> Result<Self, AnakiError> {
        let client = connect(config_json).await?;

        Ok(Self {
            client: Arc::new(Mutex::new(client)),
            in_transaction: Arc::new(Mutex::new(false)),
        })
    }

    async fn close(&self) -> Result<(), AnakiError> {
        // Tiberius close consumes the client. We just drop it.
        Ok(())
    }

    async fn query(
        &self,
        sql: &str,
        params_json: &str,
    ) -> Result<Vec<serde_json::Map<String, serde_json::Value>>, AnakiError> {
        let params = parse_params(params_json)?;
        let (prepared_sql, values) = prepare_sql(sql, &params);

        let mut query = Query::new(prepared_sql);
        bind_query(&mut query, &values);

        let mut client = self.client.lock().await;
        let stream = query.query(&mut *client).await
            .map_err(|e| AnakiError::query("Query failed", Some(e.to_string())))?;

        let rows = stream.into_first_result().await
            .map_err(|e| AnakiError::query("Failed to read results", Some(e.to_string())))?;

        Ok(rows.iter().map(row_to_map).collect())
    }

    async fn execute(&self, sql: &str, params_json: &str) -> Result<u64, AnakiError> {
        let params = parse_params(params_json)?;
        let (prepared_sql, values) = prepare_sql(sql, &params);

        let mut query = Query::new(prepared_sql);
        bind_query(&mut query, &values);

        let mut client = self.client.lock().await;
        let result = query.execute(&mut *client).await
            .map_err(|e| AnakiError::query("Execute failed", Some(e.to_string())))?;

        Ok(result.rows_affected().iter().sum::<u64>())
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
        let mut client = self.client.lock().await;

        for params in &params_list {
            let (prepared_sql, values) = prepare_sql(sql, params);
            let mut query = Query::new(prepared_sql);
            bind_query(&mut query, &values);

            let result = query.execute(&mut *client).await
                .map_err(|e| AnakiError::query("Batch execute failed", Some(e.to_string())))?;
            total_affected += result.rows_affected().iter().sum::<u64>();
        }

        Ok(total_affected)
    }

    async fn begin_transaction(&self) -> Result<(), AnakiError> {
        let mut client = self.client.lock().await;
        client.simple_query("BEGIN TRANSACTION").await
            .map_err(|e| AnakiError::transaction(format!("Failed to begin transaction: {}", e)))?
            .into_results().await
            .map_err(|e| AnakiError::transaction(format!("Failed to begin transaction: {}", e)))?;

        let mut in_tx = self.in_transaction.lock().await;
        *in_tx = true;
        Ok(())
    }

    async fn commit(&self) -> Result<(), AnakiError> {
        let mut client = self.client.lock().await;
        client.simple_query("COMMIT").await
            .map_err(|e| AnakiError::transaction(format!("Failed to commit: {}", e)))?
            .into_results().await
            .map_err(|e| AnakiError::transaction(format!("Failed to commit: {}", e)))?;

        let mut in_tx = self.in_transaction.lock().await;
        *in_tx = false;
        Ok(())
    }

    async fn rollback(&self) -> Result<(), AnakiError> {
        let mut client = self.client.lock().await;
        client.simple_query("ROLLBACK").await
            .map_err(|e| AnakiError::transaction(format!("Failed to rollback: {}", e)))?
            .into_results().await
            .map_err(|e| AnakiError::transaction(format!("Failed to rollback: {}", e)))?;

        let mut in_tx = self.in_transaction.lock().await;
        *in_tx = false;
        Ok(())
    }

    async fn ping(&self) -> Result<bool, AnakiError> {
        let mut client = self.client.lock().await;
        let result = client.simple_query("SELECT 1").await;
        match result {
            Ok(stream) => {
                let _ = stream.into_results().await;
                Ok(true)
            }
            Err(_) => Ok(false),
        }
    }
}
