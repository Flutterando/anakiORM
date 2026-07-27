use crate::connector::DatabaseConnector;
use crate::error::AnakiError;
use mongodb::bson::{doc, Bson, Document};
use mongodb::options::{ClientOptions, Credential, ServerAddress, Tls, TlsOptions};
use mongodb::{Client, ClientSession, Database, IndexModel};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

/// MongoDB connector implementation using the official `mongodb` crate.
///
/// This is not a SQL driver: the `sql` argument carries a JSON command
/// envelope, e.g. `{"op":"find","collection":"users","filter":{...}}`.
/// Documents cross the boundary as relaxed extended JSON (`{"$oid":...}`,
/// `{"$date":...}`). Transactions are real (ClientSession) and require a
/// replica set.
pub struct MongoConnector {
    client: Client,
    db: Database,
    session: Arc<Mutex<Option<ClientSession>>>,
}

#[derive(serde::Deserialize)]
struct MongoConfig {
    #[serde(default)]
    uri: Option<String>,
    #[serde(default = "default_host")]
    host: String,
    #[serde(default = "default_port")]
    port: u16,
    #[serde(default)]
    username: Option<String>,
    #[serde(default)]
    password: Option<String>,
    database: String,
    #[serde(default)]
    auth_source: Option<String>,
    #[serde(default = "default_min_connections")]
    min_connections: u32,
    #[serde(default = "default_max_connections")]
    max_connections: u32,
    #[serde(default)]
    direct_connection: Option<bool>,
    #[serde(default)]
    replica_set: Option<String>,
    #[serde(default)]
    tls: Option<bool>,
    #[serde(default)]
    connect_timeout_ms: Option<u64>,
    #[serde(default)]
    server_selection_timeout_ms: Option<u64>,
}

fn default_host() -> String {
    "localhost".to_string()
}
fn default_port() -> u16 {
    27017
}
fn default_min_connections() -> u32 {
    1
}
fn default_max_connections() -> u32 {
    10
}

type JsonValue = serde_json::Value;

/// Query-path operations (routed through `anaki_query`).
#[derive(serde::Deserialize)]
#[serde(tag = "op", rename_all = "camelCase")]
enum QueryOp {
    Find {
        collection: String,
        #[serde(default)]
        filter: Option<JsonValue>,
        #[serde(default)]
        sort: Option<JsonValue>,
        #[serde(default)]
        projection: Option<JsonValue>,
        #[serde(default)]
        skip: Option<u64>,
        #[serde(default)]
        limit: Option<i64>,
    },
    FindOne {
        collection: String,
        #[serde(default)]
        filter: Option<JsonValue>,
        #[serde(default)]
        sort: Option<JsonValue>,
        #[serde(default)]
        projection: Option<JsonValue>,
    },
    Aggregate {
        collection: String,
        pipeline: Vec<JsonValue>,
    },
    CountDocuments {
        collection: String,
        #[serde(default)]
        filter: Option<JsonValue>,
    },
    Distinct {
        collection: String,
        field: String,
        #[serde(default)]
        filter: Option<JsonValue>,
    },
    InsertOne {
        collection: String,
        document: JsonValue,
    },
    RunCommand {
        command: JsonValue,
    },
}

/// Execute-path operations (routed through `anaki_execute`).
#[derive(serde::Deserialize)]
#[serde(tag = "op", rename_all = "camelCase")]
enum ExecOp {
    InsertOne {
        collection: String,
        document: JsonValue,
    },
    InsertMany {
        collection: String,
        documents: Vec<JsonValue>,
        #[serde(default = "default_true")]
        ordered: bool,
    },
    UpdateOne {
        collection: String,
        filter: JsonValue,
        update: JsonValue,
        #[serde(default)]
        upsert: bool,
    },
    UpdateMany {
        collection: String,
        filter: JsonValue,
        update: JsonValue,
        #[serde(default)]
        upsert: bool,
    },
    ReplaceOne {
        collection: String,
        filter: JsonValue,
        replacement: JsonValue,
        #[serde(default)]
        upsert: bool,
    },
    DeleteOne {
        collection: String,
        filter: JsonValue,
    },
    DeleteMany {
        collection: String,
        filter: JsonValue,
    },
    CreateIndex {
        collection: String,
        keys: JsonValue,
        #[serde(default)]
        name: Option<String>,
        #[serde(default)]
        unique: bool,
    },
    DropIndex {
        collection: String,
        name: String,
    },
    DropCollection {
        collection: String,
    },
}

fn default_true() -> bool {
    true
}

/// Converts inbound JSON (possibly extended JSON) to a BSON Document.
///
/// Uses `Bson::try_from`, which reinterprets `{"$oid":...}` etc. as real
/// BSON types (serde-based `to_bson` would keep them as literal subdocuments).
fn json_to_doc(v: JsonValue) -> Result<Document, AnakiError> {
    match Bson::try_from(v)
        .map_err(|e| AnakiError::query("Invalid document/filter", Some(e.to_string())))?
    {
        Bson::Document(d) => Ok(d),
        _ => Err(AnakiError::query("Expected a JSON object", None)),
    }
}

fn opt_json_to_doc(v: Option<JsonValue>) -> Result<Document, AnakiError> {
    match v {
        Some(v) => json_to_doc(v),
        None => Ok(Document::new()),
    }
}

/// Converts an outbound BSON Document to a relaxed extended JSON row.
fn doc_to_row(doc: Document) -> serde_json::Map<String, JsonValue> {
    match Bson::Document(doc).into_relaxed_extjson() {
        JsonValue::Object(m) => m,
        _ => serde_json::Map::new(),
    }
}

fn json_to_pipeline(pipeline: Vec<JsonValue>) -> Result<Vec<Document>, AnakiError> {
    pipeline.into_iter().map(json_to_doc).collect()
}

fn map_mongo_err(e: mongodb::error::Error) -> AnakiError {
    use mongodb::error::ErrorKind;
    match e.kind.as_ref() {
        ErrorKind::ServerSelection { .. }
        | ErrorKind::Io(_)
        | ErrorKind::Authentication { .. }
        | ErrorKind::DnsResolve { .. }
        | ErrorKind::ConnectionPoolCleared { .. }
        | ErrorKind::Shutdown => AnakiError::connection(e.to_string()),
        ErrorKind::Command(c) => {
            AnakiError::query(e.to_string(), Some(format!("code {}", c.code)))
        }
        _ => AnakiError::query(e.to_string(), None),
    }
}

/// Runs a single-result action builder with or without the active session.
macro_rules! with_session {
    ($guard:expr, $action:expr) => {
        match $guard.as_mut() {
            Some(sess) => $action.session(&mut *sess).await,
            None => $action.await,
        }
    };
}

impl MongoConnector {
    fn coll(&self, name: &str) -> mongodb::Collection<Document> {
        self.db.collection::<Document>(name)
    }

    async fn run_exec_op(
        &self,
        op: ExecOp,
        guard: &mut Option<ClientSession>,
    ) -> Result<u64, AnakiError> {
        match op {
            ExecOp::InsertOne { collection, document } => {
                let doc = json_to_doc(document)?;
                with_session!(guard, self.coll(&collection).insert_one(doc))
                    .map_err(map_mongo_err)?;
                Ok(1)
            }
            ExecOp::InsertMany { collection, documents, ordered } => {
                let docs = json_to_pipeline(documents)?;
                if docs.is_empty() {
                    return Ok(0);
                }
                let result = with_session!(
                    guard,
                    self.coll(&collection).insert_many(docs).ordered(ordered)
                )
                .map_err(map_mongo_err)?;
                Ok(result.inserted_ids.len() as u64)
            }
            ExecOp::UpdateOne { collection, filter, update, upsert } => {
                let filter = json_to_doc(filter)?;
                let modifications = json_to_update(update)?;
                let result = with_session!(
                    guard,
                    self.coll(&collection).update_one(filter, modifications).upsert(upsert)
                )
                .map_err(map_mongo_err)?;
                Ok(if result.upserted_id.is_some() { 1 } else { result.modified_count })
            }
            ExecOp::UpdateMany { collection, filter, update, upsert } => {
                let filter = json_to_doc(filter)?;
                let modifications = json_to_update(update)?;
                let result = with_session!(
                    guard,
                    self.coll(&collection).update_many(filter, modifications).upsert(upsert)
                )
                .map_err(map_mongo_err)?;
                Ok(if result.upserted_id.is_some() { 1 } else { result.modified_count })
            }
            ExecOp::ReplaceOne { collection, filter, replacement, upsert } => {
                let filter = json_to_doc(filter)?;
                let replacement = json_to_doc(replacement)?;
                let result = with_session!(
                    guard,
                    self.coll(&collection).replace_one(filter, replacement).upsert(upsert)
                )
                .map_err(map_mongo_err)?;
                Ok(if result.upserted_id.is_some() { 1 } else { result.modified_count })
            }
            ExecOp::DeleteOne { collection, filter } => {
                let filter = json_to_doc(filter)?;
                let result = with_session!(guard, self.coll(&collection).delete_one(filter))
                    .map_err(map_mongo_err)?;
                Ok(result.deleted_count)
            }
            ExecOp::DeleteMany { collection, filter } => {
                let filter = json_to_doc(filter)?;
                let result = with_session!(guard, self.coll(&collection).delete_many(filter))
                    .map_err(map_mongo_err)?;
                Ok(result.deleted_count)
            }
            ExecOp::CreateIndex { collection, keys, name, unique } => {
                let keys = json_to_doc(keys)?;
                let mut options = mongodb::options::IndexOptions::default();
                options.name = name;
                options.unique = if unique { Some(true) } else { None };
                let model = IndexModel::builder().keys(keys).options(options).build();
                with_session!(guard, self.coll(&collection).create_index(model))
                    .map_err(map_mongo_err)?;
                Ok(1)
            }
            ExecOp::DropIndex { collection, name } => {
                with_session!(guard, self.coll(&collection).drop_index(name))
                    .map_err(map_mongo_err)?;
                Ok(1)
            }
            ExecOp::DropCollection { collection } => {
                with_session!(guard, self.coll(&collection).drop())
                    .map_err(map_mongo_err)?;
                Ok(1)
            }
        }
    }
}

/// Update payload: an object (`{"$set":...}`) or an array (aggregation pipeline).
fn json_to_update(update: JsonValue) -> Result<mongodb::options::UpdateModifications, AnakiError> {
    match update {
        JsonValue::Array(stages) => Ok(mongodb::options::UpdateModifications::Pipeline(
            json_to_pipeline(stages)?,
        )),
        other => Ok(mongodb::options::UpdateModifications::Document(json_to_doc(
            other,
        )?)),
    }
}

#[async_trait::async_trait]
impl DatabaseConnector for MongoConnector {
    async fn open(config_json: &str) -> Result<Self, AnakiError> {
        let cfg: MongoConfig = serde_json::from_str(config_json)
            .map_err(|e| AnakiError::connection(format!("Invalid config JSON: {}", e)))?;

        let mut opts = match &cfg.uri {
            Some(uri) => ClientOptions::parse(uri.as_str())
                .await
                .map_err(|e| AnakiError::connection(format!("Invalid MongoDB URI: {}", e)))?,
            None => {
                let mut opts = ClientOptions::builder()
                    .hosts(vec![ServerAddress::Tcp {
                        host: cfg.host.clone(),
                        port: Some(cfg.port),
                    }])
                    .build();
                if let Some(username) = &cfg.username {
                    opts.credential = Some(
                        Credential::builder()
                            .username(username.clone())
                            .password(cfg.password.clone())
                            .source(cfg.auth_source.clone())
                            .build(),
                    );
                }
                if let Some(direct) = cfg.direct_connection {
                    opts.direct_connection = Some(direct);
                }
                if let Some(rs) = &cfg.replica_set {
                    opts.repl_set_name = Some(rs.clone());
                }
                if cfg.tls == Some(true) {
                    opts.tls = Some(Tls::Enabled(TlsOptions::default()));
                }
                opts
            }
        };

        opts.min_pool_size = Some(cfg.min_connections);
        opts.max_pool_size = Some(cfg.max_connections);
        if let Some(ms) = cfg.connect_timeout_ms {
            opts.connect_timeout = Some(Duration::from_millis(ms));
        }
        if let Some(ms) = cfg.server_selection_timeout_ms {
            opts.server_selection_timeout = Some(Duration::from_millis(ms));
        }

        let client = Client::with_options(opts)
            .map_err(|e| AnakiError::connection(format!("Failed to create client: {}", e)))?;
        let db = client.database(&cfg.database);

        // Client creation is lazy — ping to fail fast like the other drivers.
        db.run_command(doc! {"ping": 1})
            .await
            .map_err(|e| AnakiError::connection(format!("Failed to connect to MongoDB: {}", e)))?;

        Ok(MongoConnector {
            client,
            db,
            session: Arc::new(Mutex::new(None)),
        })
    }

    async fn close(&self) -> Result<(), AnakiError> {
        self.session.lock().await.take();
        self.client.clone().shutdown().await;
        Ok(())
    }

    async fn query(
        &self,
        sql: &str,
        _params_json: &str,
    ) -> Result<Vec<serde_json::Map<String, JsonValue>>, AnakiError> {
        let op: QueryOp = serde_json::from_str(sql)
            .map_err(|e| AnakiError::query("Invalid MongoDB command envelope", Some(e.to_string())))?;
        let mut guard = self.session.lock().await;

        match op {
            QueryOp::Find { collection, filter, sort, projection, skip, limit } => {
                let filter = opt_json_to_doc(filter)?;
                let coll = self.coll(&collection);
                let mut action = coll.find(filter);
                if let Some(s) = sort {
                    action = action.sort(json_to_doc(s)?);
                }
                if let Some(p) = projection {
                    action = action.projection(json_to_doc(p)?);
                }
                if let Some(n) = skip {
                    action = action.skip(n);
                }
                if let Some(n) = limit {
                    action = action.limit(n);
                }

                let mut rows = Vec::new();
                match guard.as_mut() {
                    Some(sess) => {
                        let mut cursor =
                            action.session(&mut *sess).await.map_err(map_mongo_err)?;
                        while let Some(doc) = cursor.next(&mut *sess).await {
                            rows.push(doc_to_row(doc.map_err(map_mongo_err)?));
                        }
                    }
                    None => {
                        use futures_util::TryStreamExt;
                        let mut cursor = action.await.map_err(map_mongo_err)?;
                        while let Some(doc) = cursor.try_next().await.map_err(map_mongo_err)? {
                            rows.push(doc_to_row(doc));
                        }
                    }
                }
                Ok(rows)
            }
            QueryOp::FindOne { collection, filter, sort, projection } => {
                let filter = opt_json_to_doc(filter)?;
                let coll = self.coll(&collection);
                let mut action = coll.find_one(filter);
                if let Some(s) = sort {
                    action = action.sort(json_to_doc(s)?);
                }
                if let Some(p) = projection {
                    action = action.projection(json_to_doc(p)?);
                }
                let result = with_session!(guard, action).map_err(map_mongo_err)?;
                Ok(result.map(doc_to_row).into_iter().collect())
            }
            QueryOp::Aggregate { collection, pipeline } => {
                let pipeline = json_to_pipeline(pipeline)?;
                let coll = self.coll(&collection);
                let action = coll.aggregate(pipeline);

                let mut rows = Vec::new();
                match guard.as_mut() {
                    Some(sess) => {
                        let mut cursor =
                            action.session(&mut *sess).await.map_err(map_mongo_err)?;
                        while let Some(doc) = cursor.next(&mut *sess).await {
                            rows.push(doc_to_row(doc.map_err(map_mongo_err)?));
                        }
                    }
                    None => {
                        use futures_util::TryStreamExt;
                        let mut cursor = action.await.map_err(map_mongo_err)?;
                        while let Some(doc) = cursor.try_next().await.map_err(map_mongo_err)? {
                            rows.push(doc_to_row(doc));
                        }
                    }
                }
                Ok(rows)
            }
            QueryOp::CountDocuments { collection, filter } => {
                let filter = opt_json_to_doc(filter)?;
                let count = with_session!(guard, self.coll(&collection).count_documents(filter))
                    .map_err(map_mongo_err)?;
                let mut row = serde_json::Map::new();
                row.insert("count".to_string(), JsonValue::Number(count.into()));
                Ok(vec![row])
            }
            QueryOp::Distinct { collection, field, filter } => {
                let filter = opt_json_to_doc(filter)?;
                let values =
                    with_session!(guard, self.coll(&collection).distinct(&field, filter))
                        .map_err(map_mongo_err)?;
                Ok(values
                    .into_iter()
                    .map(|v| {
                        let mut row = serde_json::Map::new();
                        row.insert("value".to_string(), v.into_relaxed_extjson());
                        row
                    })
                    .collect())
            }
            QueryOp::InsertOne { collection, document } => {
                let doc = json_to_doc(document)?;
                let result = with_session!(guard, self.coll(&collection).insert_one(doc))
                    .map_err(map_mongo_err)?;
                let mut row = serde_json::Map::new();
                row.insert(
                    "insertedId".to_string(),
                    result.inserted_id.into_relaxed_extjson(),
                );
                Ok(vec![row])
            }
            QueryOp::RunCommand { command } => {
                let command = json_to_doc(command)?;
                let action = self.db.run_command(command);
                let reply = with_session!(guard, action).map_err(map_mongo_err)?;
                Ok(vec![doc_to_row(reply)])
            }
        }
    }

    async fn execute(&self, sql: &str, _params_json: &str) -> Result<u64, AnakiError> {
        let op: ExecOp = serde_json::from_str(sql)
            .map_err(|e| AnakiError::query("Invalid MongoDB command envelope", Some(e.to_string())))?;
        let mut guard = self.session.lock().await;
        self.run_exec_op(op, &mut guard).await
    }

    async fn execute_batch(
        &self,
        sql: &str,
        params_list_json: &str,
    ) -> Result<u64, AnakiError> {
        let template: serde_json::Map<String, JsonValue> = serde_json::from_str(sql)
            .map_err(|e| AnakiError::query("Invalid MongoDB batch template", Some(e.to_string())))?;
        let entries: Vec<serde_json::Map<String, JsonValue>> =
            serde_json::from_str(params_list_json).map_err(|e| {
                AnakiError::query("Failed to parse batch documents", Some(e.to_string()))
            })?;

        if entries.is_empty() {
            return Ok(0);
        }

        let mut guard = self.session.lock().await;
        let op_name = template.get("op").and_then(|v| v.as_str()).unwrap_or("");

        // Fast path: insertOne template + one document per entry -> single insert_many.
        if op_name == "insertOne" {
            let collection = template
                .get("collection")
                .and_then(|v| v.as_str())
                .ok_or_else(|| AnakiError::query("Batch template missing \"collection\"", None))?
                .to_string();
            let docs = entries
                .into_iter()
                .map(|e| json_to_doc(JsonValue::Object(e)))
                .collect::<Result<Vec<_>, _>>()?;
            let result = with_session!(
                guard,
                self.coll(&collection).insert_many(docs).ordered(true)
            )
            .map_err(map_mongo_err)?;
            return Ok(result.inserted_ids.len() as u64);
        }

        // Generic path: merge each entry into the template and execute.
        let mut total = 0u64;
        for entry in entries {
            let mut merged = template.clone();
            merged.extend(entry);
            let op: ExecOp = serde_json::from_value(JsonValue::Object(merged)).map_err(|e| {
                AnakiError::query("Invalid MongoDB batch entry", Some(e.to_string()))
            })?;
            total += self.run_exec_op(op, &mut guard).await?;
        }
        Ok(total)
    }

    async fn begin_transaction(&self) -> Result<(), AnakiError> {
        let mut guard = self.session.lock().await;
        if guard.is_some() {
            return Err(AnakiError::transaction("Transaction already in progress"));
        }
        let mut session = self
            .client
            .start_session()
            .await
            .map_err(|e| AnakiError::transaction(format!("Failed to start session: {}", e)))?;
        session
            .start_transaction()
            .await
            .map_err(|e| AnakiError::transaction(format!("Failed to begin transaction: {}", e)))?;
        *guard = Some(session);
        Ok(())
    }

    async fn commit(&self) -> Result<(), AnakiError> {
        let mut guard = self.session.lock().await;
        match guard.take() {
            Some(mut session) => session.commit_transaction().await.map_err(|e| {
                let indeterminate = e
                    .contains_label(mongodb::error::UNKNOWN_TRANSACTION_COMMIT_RESULT);
                AnakiError::transaction(format!(
                    "Failed to commit transaction{}: {}",
                    if indeterminate { " (outcome unknown)" } else { "" },
                    e
                ))
            }),
            None => Err(AnakiError::transaction("No active transaction")),
        }
    }

    async fn rollback(&self) -> Result<(), AnakiError> {
        let mut guard = self.session.lock().await;
        match guard.take() {
            Some(mut session) => session
                .abort_transaction()
                .await
                .map_err(|e| AnakiError::transaction(format!("Failed to rollback: {}", e))),
            None => Err(AnakiError::transaction("No active transaction")),
        }
    }

    async fn ping(&self) -> Result<bool, AnakiError> {
        Ok(self.db.run_command(doc! {"ping": 1}).await.is_ok())
    }
}

#[cfg(test)]
mod socks5_tests {
    #[test]
    fn proxy_options_accepted() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        let r = rt.block_on(async {
            mongodb::options::ClientOptions::parse(
                "mongodb://user:pass@host:27017/db?proxyHost=127.0.0.1&proxyPort=1080",
            )
            .await
        });
        assert!(r.is_ok(), "socks5-proxy options rejected: {:?}", r.err());
    }
}
