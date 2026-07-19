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
#[cfg(feature = "redis")]
mod redis;
#[cfg(feature = "mongodb")]
mod mongo;
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
///
/// Fallible: a runtime creation failure is reported as an error response
/// instead of panicking across the FFI boundary.
fn runtime() -> Result<&'static Runtime, AnakiError> {
    static RUNTIME: OnceLock<Result<Runtime, String>> = OnceLock::new();
    RUNTIME
        .get_or_init(|| Runtime::new().map_err(|e| e.to_string()))
        .as_ref()
        .map_err(|e| AnakiError::internal(format!("Failed to create tokio runtime: {}", e)))
}

/// Global connector instance stored as a trait object.
/// Set on `anaki_open`, cleared on `anaki_close`.
static CONNECTOR: OnceLock<std::sync::Mutex<Option<Box<dyn DatabaseConnector>>>> = OnceLock::new();

fn get_connector_lock() -> &'static std::sync::Mutex<Option<Box<dyn DatabaseConnector>>> {
    CONNECTOR.get_or_init(|| std::sync::Mutex::new(None))
}

/// Locks the global connector, recovering from a poisoned mutex so a past
/// panic doesn't permanently break every subsequent call.
fn lock_connector() -> std::sync::MutexGuard<'static, Option<Box<dyn DatabaseConnector>>> {
    get_connector_lock()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Runs an FFI body catching any panic and converting it into a normal
/// `{"error": ...}` response. Panics must never unwind across `extern "C"`.
fn ffi_guard(f: impl FnOnce() -> String) -> *mut c_char {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(f));
    let json = match result {
        Ok(json) => json,
        Err(panic) => {
            let msg = panic
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| panic.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "unknown panic".to_string());
            FfiResponse::<StatusResult>::fail(AnakiError::internal(format!(
                "internal panic: {}",
                msg
            )))
            .to_json()
        }
    };
    string_to_c(json)
}

/// Runs an async block on the global runtime, returning an error response
/// if the runtime could not be created.
fn block_on_ffi<F: std::future::Future<Output = String>>(fut: F) -> String {
    match runtime() {
        Ok(rt) => rt.block_on(fut),
        Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
    }
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

    #[cfg(feature = "redis")]
    {
        let conn = redis::RedisConnector::open(config_json).await?;
        return Ok(Box::new(conn));
    }

    #[cfg(feature = "mongodb")]
    {
        let conn = mongo::MongoConnector::open(config_json).await?;
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
    ffi_guard(|| {
        let config = c_str_to_str(config_json);
        block_on_ffi(async {
            match create_connector(config).await {
                Ok(conn) => {
                    let mut guard = lock_connector();
                    *guard = Some(conn);
                    FfiResponse::success(StatusResult { success: true }).to_json()
                }
                Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
            }
        })
    })
}

/// Closes the database connection.
#[no_mangle]
pub extern "C" fn anaki_close() -> *mut c_char {
    ffi_guard(|| {
        block_on_ffi(async {
            let mut guard = lock_connector();
            if let Some(conn) = guard.take() {
                match conn.close().await {
                    Ok(_) => FfiResponse::success(StatusResult { success: true }).to_json(),
                    Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
                }
            } else {
                FfiResponse::<StatusResult>::fail(AnakiError::connection("Not connected")).to_json()
            }
        })
    })
}

/// Executes a SQL query and returns rows as JSON.
#[no_mangle]
pub extern "C" fn anaki_query(
    sql: *const c_char,
    params_json: *const c_char,
) -> *mut c_char {
    ffi_guard(|| {
        let sql = c_str_to_str(sql);
        let params = c_str_to_str(params_json);
        block_on_ffi(async {
            let guard = lock_connector();
            if let Some(ref conn) = *guard {
                match conn.query(sql, params).await {
                    Ok(rows) => FfiResponse::success(QueryResult { rows }).to_json(),
                    Err(e) => FfiResponse::<QueryResult>::fail(e).to_json(),
                }
            } else {
                FfiResponse::<QueryResult>::fail(AnakiError::connection("Not connected")).to_json()
            }
        })
    })
}

/// Executes a non-query SQL statement.
#[no_mangle]
pub extern "C" fn anaki_execute(
    sql: *const c_char,
    params_json: *const c_char,
) -> *mut c_char {
    ffi_guard(|| {
        let sql = c_str_to_str(sql);
        let params = c_str_to_str(params_json);
        block_on_ffi(async {
            let guard = lock_connector();
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
        })
    })
}

/// Executes a batch of statements with different parameter sets.
#[no_mangle]
pub extern "C" fn anaki_execute_batch(
    sql: *const c_char,
    params_list_json: *const c_char,
) -> *mut c_char {
    ffi_guard(|| {
        let sql = c_str_to_str(sql);
        let params_list = c_str_to_str(params_list_json);
        block_on_ffi(async {
            let guard = lock_connector();
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
        })
    })
}

/// Begins a transaction.
#[no_mangle]
pub extern "C" fn anaki_begin_transaction() -> *mut c_char {
    ffi_guard(|| block_on_ffi(async {
        let guard = lock_connector();
        if let Some(ref conn) = *guard {
            match conn.begin_transaction().await {
                Ok(_) => FfiResponse::success(StatusResult { success: true }).to_json(),
                Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<StatusResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    }))
}

/// Commits the current transaction.
#[no_mangle]
pub extern "C" fn anaki_commit() -> *mut c_char {
    ffi_guard(|| block_on_ffi(async {
        let guard = lock_connector();
        if let Some(ref conn) = *guard {
            match conn.commit().await {
                Ok(_) => FfiResponse::success(StatusResult { success: true }).to_json(),
                Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<StatusResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    }))
}

/// Rolls back the current transaction.
#[no_mangle]
pub extern "C" fn anaki_rollback() -> *mut c_char {
    ffi_guard(|| block_on_ffi(async {
        let guard = lock_connector();
        if let Some(ref conn) = *guard {
            match conn.rollback().await {
                Ok(_) => FfiResponse::success(StatusResult { success: true }).to_json(),
                Err(e) => FfiResponse::<StatusResult>::fail(e).to_json(),
            }
        } else {
            FfiResponse::<StatusResult>::fail(AnakiError::connection("Not connected")).to_json()
        }
    }))
}

/// Checks if the connection is alive.
#[no_mangle]
pub extern "C" fn anaki_ping() -> *mut c_char {
    ffi_guard(|| block_on_ffi(async {
        let guard = lock_connector();
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
    }))
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
