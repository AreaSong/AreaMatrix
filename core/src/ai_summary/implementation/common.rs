use crate::CoreError;

pub(super) fn character_count(value: &str) -> i64 {
    value.chars().count() as i64
}

pub(super) fn current_timestamp() -> i64 {
    chrono::Utc::now().timestamp()
}

pub(super) fn map_file_lookup_error(error: CoreError) -> CoreError {
    match error {
        CoreError::RepoNotInitialized { .. } => {
            CoreError::config("AI summary requires initialized repository metadata")
        }
        other => other,
    }
}
