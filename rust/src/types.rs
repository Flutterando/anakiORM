use serde::Serialize;

/// Successful response wrapping query results.
#[derive(Debug, Serialize)]
pub struct QueryResult {
    pub rows: Vec<serde_json::Map<String, serde_json::Value>>,
}

/// Successful response wrapping execute results.
#[derive(Debug, Serialize)]
pub struct ExecuteResult {
    pub rows_affected: u64,
}

/// Successful response for status-only operations.
#[derive(Debug, Serialize)]
pub struct StatusResult {
    pub success: bool,
}

/// Unified FFI response. Either `ok` with data or `error` with details.
#[derive(Debug, Serialize)]
#[serde(untagged)]
pub enum FfiResponse<T: Serialize> {
    Ok { ok: T },
    Err { error: crate::error::AnakiError },
}

impl<T: Serialize> FfiResponse<T> {
    pub fn success(data: T) -> Self {
        FfiResponse::Ok { ok: data }
    }

    pub fn fail(err: crate::error::AnakiError) -> Self {
        FfiResponse::Err { error: err }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| {
            r#"{"error":{"code":"INTERNAL_ERROR","message":"Failed to serialize response","details":null}}"#.to_string()
        })
    }
}
