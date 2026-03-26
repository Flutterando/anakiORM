use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct AnakiError {
    pub code: String,
    pub message: String,
    pub details: Option<String>,
}

impl AnakiError {
    pub fn connection(msg: impl Into<String>) -> Self {
        Self {
            code: "CONNECTION_ERROR".into(),
            message: msg.into(),
            details: None,
        }
    }

    pub fn query(msg: impl Into<String>, details: Option<String>) -> Self {
        Self {
            code: "QUERY_ERROR".into(),
            message: msg.into(),
            details,
        }
    }

    pub fn transaction(msg: impl Into<String>) -> Self {
        Self {
            code: "TRANSACTION_ERROR".into(),
            message: msg.into(),
            details: None,
        }
    }

    pub fn internal(msg: impl Into<String>) -> Self {
        Self {
            code: "INTERNAL_ERROR".into(),
            message: msg.into(),
            details: None,
        }
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| {
            format!(
                r#"{{"code":"INTERNAL_ERROR","message":"Failed to serialize error","details":null}}"#
            )
        })
    }
}

impl From<sqlx::Error> for AnakiError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::Database(e) => AnakiError::query(e.message().to_string(), None),
            sqlx::Error::PoolTimedOut => {
                AnakiError::connection("Connection pool timed out".to_string())
            }
            _ => AnakiError::query(err.to_string(), None),
        }
    }
}
