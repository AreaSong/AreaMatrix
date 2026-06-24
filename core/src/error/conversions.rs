use super::core_error::CoreError;

impl From<std::io::Error> for CoreError {
    fn from(error: std::io::Error) -> Self {
        match error.kind() {
            std::io::ErrorKind::NotFound => Self::file_not_found(error.to_string()),
            std::io::ErrorKind::PermissionDenied => Self::permission_denied(error.to_string()),
            std::io::ErrorKind::InvalidInput => Self::invalid_path(error.to_string()),
            _ => Self::io(error.to_string()),
        }
    }
}

impl From<rusqlite::Error> for CoreError {
    fn from(error: rusqlite::Error) -> Self {
        Self::db(error.to_string())
    }
}

impl From<serde_json::Error> for CoreError {
    fn from(error: serde_json::Error) -> Self {
        Self::internal(format!("json: {error}"))
    }
}

impl From<walkdir::Error> for CoreError {
    fn from(error: walkdir::Error) -> Self {
        Self::io(error.to_string())
    }
}
