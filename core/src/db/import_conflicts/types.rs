use serde_json::Value;

#[derive(Clone, Debug)]
pub(crate) struct ImportConflictRow {
    pub(crate) conflict_id: String,
    pub(crate) import_session_id: String,
    pub(crate) conflict_type: ImportConflictKind,
    pub(crate) staging_file_id: i64,
    pub(crate) existing_file_id: Option<i64>,
    pub(crate) incoming_path: String,
    pub(crate) target_path: String,
    pub(crate) status: ImportConflictStatus,
    pub(crate) failure_reason: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum ImportConflictKind {
    DuplicateHash,
    SameNameDifferentContent,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum ImportConflictStatus {
    Pending,
    QueuedForPerItem,
    Resolved,
    Failed,
}

pub(crate) struct ImportConflictApplyItem<'a> {
    pub(crate) conflict: &'a ImportConflictRow,
    pub(crate) final_path: Option<&'a str>,
    pub(crate) final_name: Option<&'a str>,
    pub(crate) change_detail: Option<&'a Value>,
    pub(crate) replaced: Option<ImportConflictReplacement<'a>>,
    pub(crate) decision: &'a str,
}

pub(crate) struct ImportConflictReplacement<'a> {
    pub(crate) archived_path: &'a str,
    pub(crate) deleted_detail: &'a Value,
}
