use serde_json::Value;

use crate::{CoreError, CoreResult};

pub(super) fn serialize_json(value: &Value) -> CoreResult<String> {
    serde_json::to_string(value).map_err(|error| CoreError::internal(error.to_string()))
}
