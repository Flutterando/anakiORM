mod connector;
mod error;
mod types;

#[cfg(feature = "sqlite")]
mod sqlite;

#[cfg(feature = "postgres")]
mod postgres;
#[cfg(feature = "mysql")]
mod mysql;
#[cfg(feature = "mssql")]
mod mssql;
// #[cfg(feature = "oracle")]
// mod oracle;

use connector::DatabaseConnector;
use error::AnakiError;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::OnceLock;
use tokio::runtime::Runtime;
use types::{ExecuteResult, FfiResponse, QueryResult, StatusResult};

/// Global tokio runtime for async operations.
fn runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        Runtime::new().expect("Failed to create tokio runtime")
    })
}

/// Global connector instance stored as a trait object.
/// Set on `anaki_open`, cleared on `anaki_close`.
static CONNECTOR: OnceLock<std::sync::Mutex<Option<Box<dyn DatabaseConnector>>>> = OnceLock::new();

fn get_connector_lock() -> &'static std::sync::Mutex<Option<Box<dyn DatabaseConnector>>> {
    CONNECTOR.get_or_init(|| std::sync::Mutex::new(None))
}

// ─── Helper functions ───

fn c_str_to_str(ptr: *const c_char) -> &'static str {
    if ptr.is_null() {
        return "";
    }
    unsafe { CStr::from_ptr(ptr) }.to_str().unwrap_or("")
}

fn string_to_c(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new("").unwrap())
        .into_raw()
}

/// Creates the correct connector based on the compiled feature.
///
/// The config JSON must include a `"driver"` field matching the feature,
/// or it defaults to the single compiled feature.
async fn create_connector(config_json: &str) -> Result<Box<dyn DatabaseConnector>, AnakiError> {
    // Parse to check for explicit driver field
    let config: serde_json::Value = serde_json::from_str(config_json)
        .map_err(|e| AnakiError::connection(format!("Invalid config JSON: {}", e)))?;

    let _driver = config.get("driver").and_then(|v| v.as_str()).unwrap_or("");

    #[cfg(feature = "sqlite")]
    {
        let conn = sqlite::SqliteConnector::open(config_json).await?;
        return Ok(Box::new(conn));
    }

    #[cfg(feature = "postgres")]
    {
        let conn = postgres::PostgresConnector::open(config_json).await?;
        return Ok(Box::new(conn));
    }

    #[cfg(feature = "mysql")]
    {
        let conn = mysql::MysqlConnector::open(config_json).await?;
        return Ok(Box::new(conn));
    }

    #[cfg(feature = "mssql")]
    {
        let conn = mssql::MssqlConnector::open(config_json).await?;
        return Ok(Box::new(conn));
    }

    // #[cfg(feature = "oracle")]
    // {
    //     let conn = oracle::OracleConnector::open(config_json).await?;
    //     return Ok(Box::new(conn));
    // }

    #[allow(unreachable_code)]
    Err(AnakiError::connection(
        "No database driver compiled. Build with --features <driver>.",
    ))
}

// ─── FFI Exports ───

/// Opens a database connection.
///
/// `config_json`: JSON string with driver-specific configuration.
///
/// Returns JSON: `{"ok": {"success": true}}` or `{"error": {...}}`
#[no_mangle]
pub extern "C" fn anaki_open(config_json: *const c_char) -> *mut c_char {
    let config = c_str_to_str(config_json);
    let result = runtime().block_on(async {
        match create_connector(config).await {
            Ok(conn) => {
                let lock = get_connector_lock();
                let mut guard = lock.lock().unwrap();
                *guard = Some(conn);
                FfiResponse::success(StatusResult { success: true }).to_json()
            }
            Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
        }
    });
    string_to_c(result)
}

/// Closes the database connection.
#[no_mangle]
pub extern "C" fn anaki_close() -> *mut c_char {
    let result = runtime().block_on(async {
        let lock = get_connector_lock();
        let mut guard = lock.lock().unwrap();
        if let Some(conn) = guard.take() {
            match conn.close().await {
                Ok(_) => FfiResponse::success(StatusResult { success: true }).to_json(),
                Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<StatusResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    });
    string_to_c(result)
}

/// Executes a SQL query and returns rows as JSON.
#[no_mangle]
pub extern "C" fn anaki_query(
    sql: *const c_char,
    params_json: *const c_char,
) -> *mut c_char {
    let sql = c_str_to_str(sql);
    let params = c_str_to_str(params_json);
    let result = runtime().block_on(async {
        let lock = get_connector_lock();
        let guard = lock.lock().unwrap();
        if let Some(ref conn) = *guard {
            match conn.query(sql, params).await {
                Ok(rows) => FfiResponse::success(QueryResult { rows }).to_json(),
                Err(e) => FfiResponse::<QueryResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<QueryResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    });
    string_to_c(result)
}

/// Executes a non-query SQL statement.
#[no_mangle]
pub extern "C" fn anaki_execute(
    sql: *const c_char,
    params_json: *const c_char,
) -> *mut c_char {
    let sql = c_str_to_str(sql);
    let params = c_str_to_str(params_json);
    let result = runtime().block_on(async {
        let lock = get_connector_lock();
        let guard = lock.lock().unwrap();
        if let Some(ref conn) = *guard {
            match conn.execute(sql, params).await {
                Ok(affected) => {
                    FfiResponse::success(ExecuteResult {
                        rows_affected: affected,
                    })
                    .to_json()
                }
                Err(e) => FfiResponse::<ExecuteResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<ExecuteResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    });
    string_to_c(result)
}

/// Executes a batch of statements with different parameter sets.
#[no_mangle]
pub extern "C" fn anaki_execute_batch(
    sql: *const c_char,
    params_list_json: *const c_char,
) -> *mut c_char {
    let sql = c_str_to_str(sql);
    let params_list = c_str_to_str(params_list_json);
    let result = runtime().block_on(async {
        let lock = get_connector_lock();
        let guard = lock.lock().unwrap();
        if let Some(ref conn) = *guard {
            match conn.execute_batch(sql, params_list).await {
                Ok(affected) => {
                    FfiResponse::success(ExecuteResult {
                        rows_affected: affected,
                    })
                    .to_json()
                }
                Err(e) => FfiResponse::<ExecuteResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<ExecuteResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    });
    string_to_c(result)
}

/// Begins a transaction.
#[no_mangle]
pub extern "C" fn anaki_begin_transaction() -> *mut c_char {
    let result = runtime().block_on(async {
        let lock = get_connector_lock();
        let guard = lock.lock().unwrap();
        if let Some(ref conn) = *guard {
            match conn.begin_transaction().await {
                Ok(_) => FfiResponse::success(StatusResult { success: true }).to_json(),
                Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<StatusResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    });
    string_to_c(result)
}

/// Commits the current transaction.
#[no_mangle]
pub extern "C" fn anaki_commit() -> *mut c_char {
    let result = runtime().block_on(async {
        let lock = get_connector_lock();
        let guard = lock.lock().unwrap();
        if let Some(ref conn) = *guard {
            match conn.commit().await {
                Ok(_) => FfiResponse::success(StatusResult { success: true }).to_json(),
                Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<StatusResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    });
    string_to_c(result)
}

/// Rolls back the current transaction.
#[no_mangle]
pub extern "C" fn anaki_rollback() -> *mut c_char {
    let result = runtime().block_on(async {
        let lock = get_connector_lock();
        let guard = lock.lock().unwrap();
        if let Some(ref conn) = *guard {
            match conn.rollback().await {
                Ok(_) => FfiResponse::success(StatusResult { success: true }).to_json(),
                Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<StatusResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    });
    string_to_c(result)
}

/// Checks if the connection is alive.
#[no_mangle]
pub extern "C" fn anaki_ping() -> *mut c_char {
    let result = runtime().block_on(async {
        let lock = get_connector_lock();
        let guard = lock.lock().unwrap();
        if let Some(ref conn) = *guard {
            match conn.ping().await {
                Ok(alive) => {
                    FfiResponse::success(StatusResult { success: alive }).to_json()
                }
                Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<StatusResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    });
    string_to_c(result)
}

/// Frees a string previously allocated by Rust.
///
/// Must be called by Dart for every string returned by the FFI functions.
#[no_mangle]
pub extern "C" fn anaki_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}
