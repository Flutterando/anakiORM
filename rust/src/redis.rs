use crate::connector::DatabaseConnector;
use crate::error::AnakiError;
use std::time::Duration;

/// Redis connector implementation using the `redis` crate.
///
/// This is not a SQL driver: the `sql` argument of `query`/`execute` carries a
/// JSON array command, e.g. `["SET","user:1","Ana"]`. Replies are converted to
/// JSON and returned as a single row `{"result": <reply>}`. `execute_batch`
/// runs an atomic MULTI/EXEC pipeline. Interactive transactions are not
/// supported (begin/commit/rollback return TRANSACTION_ERROR).
pub struct RedisConnector {
    manager: ::redis::aio::ConnectionManager,
}

#[derive(serde::Deserialize)]
struct RedisConfig {
    #[serde(default)]
    url: Option<String>,
    #[serde(default = "default_host")]
    host: String,
    #[serde(default = "default_port")]
    port: u16,
    #[serde(default)]
    username: Option<String>,
    #[serde(default)]
    password: Option<String>,
    #[serde(default)]
    db: i64,
    #[serde(default)]
    tls: bool,
    #[serde(default)]
    connect_timeout_ms: Option<u64>,
    #[serde(default)]
    response_timeout_ms: Option<u64>,
}

fn default_host() -> String {
    "localhost".to_string()
}
fn default_port() -> u16 {
    6379
}

/// Parses a JSON array command (`["GET","key"]`) into a redis Cmd.
fn parse_command(parts: &[serde_json::Value]) -> Result<::redis::Cmd, AnakiError> {
    let name = parts.first().and_then(|v| v.as_str()).ok_or_else(|| {
        AnakiError::query(
            "Redis command must be a non-empty JSON array with a string command name, e.g. [\"GET\",\"key\"]",
            None,
        )
    })?;
    let mut cmd = ::redis::cmd(name);
    for (i, arg) in parts[1..].iter().enumerate() {
        match arg {
            serde_json::Value::String(s) => {
                cmd.arg(s);
            }
            serde_json::Value::Number(n) => {
                cmd.arg(n.to_string());
            }
            serde_json::Value::Bool(b) => {
                cmd.arg(if *b { "1" } else { "0" });
            }
            serde_json::Value::Null => {
                return Err(AnakiError::query(
                    format!("null is not a valid Redis argument (index {})", i + 1),
                    None,
                ));
            }
            other => {
                // Arrays/objects are stored as their JSON text (documented convenience).
                cmd.arg(other.to_string());
            }
        }
    }
    Ok(cmd)
}

fn parse_command_json(sql: &str) -> Result<::redis::Cmd, AnakiError> {
    let parts: Vec<serde_json::Value> = serde_json::from_str(sql).map_err(|e| {
        AnakiError::query(
            "Redis command must be a JSON array, e.g. [\"GET\",\"key\"]",
            Some(e.to_string()),
        )
    })?;
    parse_command(&parts)
}

/// Converts a redis reply (RESP2 and RESP3 variants) to JSON.
fn value_to_json(v: ::redis::Value) -> Result<serde_json::Value, AnakiError> {
    use serde_json::Value as J;
    Ok(match v {
        ::redis::Value::Nil => J::Null,
        ::redis::Value::Int(i) => J::Number(i.into()),
        ::redis::Value::BulkString(bytes) => match String::from_utf8(bytes) {
            Ok(s) => J::String(s),
            // Lossy fallback for binary-unsafe values (documented v1 limitation).
            Err(e) => J::String(String::from_utf8_lossy(e.as_bytes()).into_owned()),
        },
        ::redis::Value::SimpleString(s) => J::String(s),
        ::redis::Value::Okay => J::String("OK".to_string()),
        ::redis::Value::Array(items) => J::Array(
            items
                .into_iter()
                .map(value_to_json)
                .collect::<Result<_, _>>()?,
        ),
        ::redis::Value::Set(items) => J::Array(
            items
                .into_iter()
                .map(value_to_json)
                .collect::<Result<_, _>>()?,
        ),
        ::redis::Value::Map(pairs) => {
            let mut map = serde_json::Map::new();
            for (k, val) in pairs {
                let key_json = value_to_json(k)?;
                let key = match key_json {
                    J::String(s) => s,
                    other => other.to_string(),
                };
                map.insert(key, value_to_json(val)?);
            }
            J::Object(map)
        }
        ::redis::Value::Double(f) => serde_json::Number::from_f64(f)
            .map(J::Number)
            .unwrap_or(J::Null),
        ::redis::Value::Boolean(b) => J::Bool(b),
        ::redis::Value::BigNumber(n) => J::String(n.to_string()),
        ::redis::Value::VerbatimString { text, .. } => J::String(text),
        ::redis::Value::Attribute { data, .. } => value_to_json(*data)?,
        ::redis::Value::Push { data, .. } => J::Array(
            data.into_iter()
                .map(value_to_json)
                .collect::<Result<_, _>>()?,
        ),
        ::redis::Value::ServerError(e) => {
            return Err(AnakiError::query(
                format!("Redis server error: {:?}", e),
                None,
            ));
        }
    })
}

fn map_redis_err(e: ::redis::RedisError) -> AnakiError {
    let details = e.code().map(|c| c.to_string());
    if e.is_connection_refusal()
        || e.is_connection_dropped()
        || e.is_timeout()
        || e.is_io_error()
        || e.kind() == ::redis::ErrorKind::AuthenticationFailed
    {
        AnakiError::connection(e.to_string())
    } else {
        AnakiError::query(e.to_string(), details)
    }
}

impl RedisConnector {
    async fn conn(&self) -> ::redis::aio::ConnectionManager {
        self.manager.clone()
    }
}

#[async_trait::async_trait]
impl DatabaseConnector for RedisConnector {
    async fn open(config_json: &str) -> Result<Self, AnakiError> {
        let cfg: RedisConfig = serde_json::from_str(config_json)
            .map_err(|e| AnakiError::connection(format!("Invalid config JSON: {}", e)))?;

        if cfg.tls {
            return Err(AnakiError::connection(
                "TLS is not compiled into this build of anaki_redis",
            ));
        }

        let client = match &cfg.url {
            Some(url) => ::redis::Client::open(url.as_str()),
            None => ::redis::Client::open(::redis::ConnectionInfo {
                addr: ::redis::ConnectionAddr::Tcp(cfg.host.clone(), cfg.port),
                redis: ::redis::RedisConnectionInfo {
                    db: cfg.db,
                    username: cfg.username.clone(),
                    password: cfg.password.clone(),
                    ..Default::default()
                },
            }),
        }
        .map_err(|e| AnakiError::connection(format!("Invalid Redis config: {}", e)))?;

        let mut mgr_cfg = ::redis::aio::ConnectionManagerConfig::new();
        if let Some(ms) = cfg.connect_timeout_ms {
            mgr_cfg = mgr_cfg.set_connection_timeout(Duration::from_millis(ms));
        }
        if let Some(ms) = cfg.response_timeout_ms {
            mgr_cfg = mgr_cfg.set_response_timeout(Duration::from_millis(ms));
        }

        let manager = client
            .get_connection_manager_with_config(mgr_cfg)
            .await
            .map_err(|e| AnakiError::connection(format!("Failed to connect to Redis: {}", e)))?;

        Ok(RedisConnector { manager })
    }

    async fn close(&self) -> Result<(), AnakiError> {
        // ConnectionManager has no explicit close; dropping the connector
        // (anaki_close takes it out of the global slot) closes the connection.
        Ok(())
    }

    async fn query(
        &self,
        sql: &str,
        _params_json: &str,
    ) -> Result<Vec<serde_json::Map<String, serde_json::Value>>, AnakiError> {
        let cmd = parse_command_json(sql)?;
        let mut conn = self.conn().await;
        let reply: ::redis::Value = cmd.query_async(&mut conn).await.map_err(map_redis_err)?;
        let mut row = serde_json::Map::new();
        row.insert("result".to_string(), value_to_json(reply)?);
        Ok(vec![row])
    }

    async fn execute(&self, sql: &str, _params_json: &str) -> Result<u64, AnakiError> {
        let cmd = parse_command_json(sql)?;
        let mut conn = self.conn().await;
        let reply: ::redis::Value = cmd.query_async(&mut conn).await.map_err(map_redis_err)?;
        Ok(match reply {
            ::redis::Value::Int(i) => i.max(0) as u64,
            ::redis::Value::Okay | ::redis::Value::SimpleString(_) => 1,
            ::redis::Value::Nil => 0,
            ::redis::Value::Boolean(b) => b as u64,
            ::redis::Value::Array(a) | ::redis::Value::Set(a) => a.len() as u64,
            ::redis::Value::Map(m) => m.len() as u64,
            _ => 1,
        })
    }

    async fn execute_batch(
        &self,
        _sql: &str,
        params_list_json: &str,
    ) -> Result<u64, AnakiError> {
        let entries: Vec<serde_json::Map<String, serde_json::Value>> =
            serde_json::from_str(params_list_json).map_err(|e| {
                AnakiError::query("Failed to parse batch commands", Some(e.to_string()))
            })?;

        if entries.is_empty() {
            return Ok(0);
        }

        let mut pipe = ::redis::pipe();
        pipe.atomic(); // MULTI/EXEC
        for entry in &entries {
            let cmd_json = entry.get("cmd").ok_or_else(|| {
                AnakiError::query("Batch entry missing \"cmd\" array", None)
            })?;
            let parts = cmd_json.as_array().ok_or_else(|| {
                AnakiError::query("Batch \"cmd\" must be a JSON array", None)
            })?;
            pipe.add_command(parse_command(parts)?);
        }

        let mut conn = self.conn().await;
        let _reply: ::redis::Value =
            pipe.query_async(&mut conn).await.map_err(map_redis_err)?;
        Ok(entries.len() as u64)
    }

    async fn begin_transaction(&self) -> Result<(), AnakiError> {
        Err(AnakiError::transaction(
            "Redis does not support interactive transactions; use execute_batch (MULTI/EXEC pipeline)",
        ))
    }

    async fn commit(&self) -> Result<(), AnakiError> {
        Err(AnakiError::transaction(
            "Redis does not support interactive transactions; use execute_batch (MULTI/EXEC pipeline)",
        ))
    }

    async fn rollback(&self) -> Result<(), AnakiError> {
        Err(AnakiError::transaction(
            "Redis does not support interactive transactions; use execute_batch (MULTI/EXEC pipeline)",
        ))
    }

    async fn ping(&self) -> Result<bool, AnakiError> {
        let mut conn = self.conn().await;
        let result: Result<String, _> = ::redis::cmd("PING").query_async(&mut conn).await;
        Ok(result.is_ok())
    }
}
