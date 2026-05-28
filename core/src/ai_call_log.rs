//! C3-05 AI call log contract types and entry points.

use std::path::{Component, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{db, CoreError, CoreResult};

const AREA_MATRIX_DIR: &str = ".areamatrix";
const MAX_SEARCH_QUERY_LEN: usize = 256;
const MAX_REDACTED_TEXT_LEN: usize = 240;
const MAX_PAGE_LIMIT: i64 = 200;
const MAX_CLEAR_ENTRY_IDS: usize = 500;
const RETENTION_DAYS: i64 = 90;
const REDACTION_POLICY: &str =
    "No API keys, full prompts, outputs, notes, file contents, raw provider responses, or absolute user paths.";

/// AI feature represented by one redacted call log row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCallLogFeature {
    /// AI classification suggestion.
    Classification,
    /// AI summary generation or update.
    Summary,
    /// AI tag suggestion.
    Tags,
    /// Semantic search or embedding operation.
    SemanticSearch,
    /// Remote provider connection verification.
    ProviderTest,
}

/// Local or remote execution route recorded for an AI call.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCallLogRoute {
    /// Local model route.
    Local,
    /// Remote provider route.
    Remote,
}

/// Redacted AI call status shown by S3-05.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCallLogStatus {
    /// The call completed successfully.
    Success,
    /// The call failed after a route was selected.
    Failed,
    /// The call was intentionally skipped by settings or privacy gates.
    Skipped,
    /// The required provider or runtime was unavailable.
    Unavailable,
}

/// Field category that may be listed without exposing field contents.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCallLogSentField {
    /// File name only.
    FileName,
    /// Repository-relative path category.
    RepoRelativePath,
    /// File extension only.
    Extension,
    /// Limited extracted text excerpt category.
    ExtractedTextExcerpt,
    /// AI summary field category.
    AiSummary,
    /// User note summary field category.
    NoteSummary,
    /// Tag or category context category.
    TagCategoryContext,
}

/// Scope accepted by `clear_ai_call_log`.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum AiCallLogClearScope {
    /// Clear every local AI call log row.
    All,
    /// Clear the selected log rows only.
    SelectedEntries,
    /// Clear rows older than `older_than`.
    OlderThan,
}

/// Filter for listing redacted AI call log rows.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiCallLogFilter {
    /// Feature filter. `None` means all features.
    pub feature: Option<AiCallLogFeature>,
    /// Route filter. `None` means local and remote rows.
    pub route: Option<AiCallLogRoute>,
    /// Status filter. `None` means all statuses.
    pub status: Option<AiCallLogStatus>,
    /// Inclusive lower bound Unix timestamp.
    pub occurred_after: Option<i64>,
    /// Exclusive upper bound Unix timestamp.
    pub occurred_before: Option<i64>,
    /// Redacted search text for filename, provider, model, or error code.
    pub search_query: Option<String>,
}

/// Pagination for AI call log listing.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiCallLogPagination {
    /// Maximum rows to return. Must be between 1 and 200.
    pub limit: i64,
    /// Zero-based row offset.
    pub offset: i64,
}

/// One redacted AI call log row.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiCallLogRecord {
    /// Stable log row id.
    pub id: i64,
    /// Unix timestamp when the call attempt or skip was recorded.
    pub occurred_at: i64,
    /// Feature that produced the row.
    pub feature: AiCallLogFeature,
    /// File id related to the call, when there is one.
    pub file_id: Option<i64>,
    /// Redacted file display name, when available.
    pub file_display_name: Option<String>,
    /// Batch id related to the call, when available.
    pub batch_id: Option<String>,
    /// Feature or provider scope label, such as `Provider verification`.
    pub scope: Option<String>,
    /// Local or remote route, when a route was selected.
    pub route: Option<AiCallLogRoute>,
    /// Redacted provider display name.
    pub provider_name: Option<String>,
    /// Redacted model display name.
    pub model_name: Option<String>,
    /// Call status.
    pub status: AiCallLogStatus,
    /// Duration in milliseconds, when measured.
    pub duration_ms: Option<i64>,
    /// Sent field categories. This never contains field values.
    pub sent_fields: Vec<AiCallLogSentField>,
    /// Whether privacy rules were evaluated for this row.
    pub privacy_rules_checked: bool,
    /// Matched privacy rule id, when a skip was rule-driven.
    pub privacy_rule_id: Option<String>,
    /// Matched privacy rule name snapshot, when available.
    pub privacy_rule_name: Option<String>,
    /// Matched field category snapshot, when available.
    pub matched_field_type: Option<AiCallLogSentField>,
    /// Redacted result summary.
    pub result_summary: String,
    /// Stable sanitized error code, when failed or unavailable.
    pub error_code: Option<String>,
}

/// Page of redacted AI call log rows.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiCallLogPage {
    /// Total rows matching the filter.
    pub total_count: i64,
    /// Returned rows ordered by newest first.
    pub records: Vec<AiCallLogRecord>,
    /// Effective limit.
    pub limit: i64,
    /// Effective offset.
    pub offset: i64,
    /// Whether there are more rows after this page.
    pub has_more: bool,
    /// Local retention policy in days.
    pub retention_days: i64,
    /// Human-readable redaction policy summary for export confirmation UI.
    pub redaction_policy: String,
}

/// Request for clearing local AI call log rows.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiCallLogClearRequest {
    /// Clear scope selected by the caller.
    pub scope: AiCallLogClearScope,
    /// Selected row ids when `scope` is `SelectedEntries`.
    pub entry_ids: Vec<i64>,
    /// Timestamp cutoff when `scope` is `OlderThan`.
    pub older_than: Option<i64>,
}

/// Result of clearing local AI call log rows.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiCallLogClearReport {
    /// Number of deleted log rows.
    pub deleted_count: i64,
    /// Remaining log row count after clear.
    pub remaining_count: i64,
    /// Unix timestamp when the clear operation completed.
    pub cleared_at: i64,
}

pub(crate) fn list_ai_calls(
    repo_path: String,
    filter: AiCallLogFilter,
    pagination: AiCallLogPagination,
) -> CoreResult<AiCallLogPage> {
    validate_repo_path(&repo_path)?;
    validate_filter(&filter)?;
    validate_pagination(&pagination)?;
    let repo = PathBuf::from(repo_path);
    let db_filter = to_db_filter(&filter);
    let db_pagination = db::AiCallLogPagination {
        limit: pagination.limit,
        offset: pagination.offset,
    };
    let page = db::list_ai_call_log_rows(&repo, &db_filter, &db_pagination)?;
    let records = page
        .rows
        .into_iter()
        .map(record_from_row)
        .collect::<CoreResult<Vec<_>>>()?;
    Ok(AiCallLogPage {
        total_count: page.total_count,
        records,
        limit: pagination.limit,
        offset: pagination.offset,
        has_more: pagination.offset + pagination.limit < page.total_count,
        retention_days: RETENTION_DAYS,
        redaction_policy: REDACTION_POLICY.to_owned(),
    })
}

pub(crate) fn clear_ai_call_log(
    repo_path: String,
    request: AiCallLogClearRequest,
) -> CoreResult<AiCallLogClearReport> {
    validate_repo_path(&repo_path)?;
    validate_clear_request(&request)?;
    let repo = PathBuf::from(repo_path);
    let stats = db::clear_ai_call_log_rows(&repo, clear_spec(request))?;
    Ok(AiCallLogClearReport {
        deleted_count: stats.deleted_count,
        remaining_count: stats.remaining_count,
        cleared_at: stats.cleared_at,
    })
}

fn validate_repo_path(repo_path: &str) -> CoreResult<()> {
    if repo_path.trim().is_empty() || repo_path.contains('\0') {
        return Err(CoreError::db("AI call log repository path is invalid"));
    }
    let repo = PathBuf::from(repo_path);
    if repo.components().any(is_area_matrix_component) {
        return Err(CoreError::db(
            "AI call log repository path must not point inside metadata",
        ));
    }
    Ok(())
}

fn validate_filter(filter: &AiCallLogFilter) -> CoreResult<()> {
    if let Some(query) = filter.search_query.as_deref() {
        if query.trim() != query || query.len() > MAX_SEARCH_QUERY_LEN || query.contains('\0') {
            return Err(CoreError::db("AI call log search query is invalid"));
        }
    }
    match (filter.occurred_after, filter.occurred_before) {
        (Some(after), _) if after < 0 => Err(CoreError::db("AI call log start time is invalid")),
        (_, Some(before)) if before < 0 => Err(CoreError::db("AI call log end time is invalid")),
        (Some(after), Some(before)) if after >= before => {
            Err(CoreError::db("AI call log date range is invalid"))
        }
        _ => Ok(()),
    }
}

fn validate_pagination(pagination: &AiCallLogPagination) -> CoreResult<()> {
    if !(1..=MAX_PAGE_LIMIT).contains(&pagination.limit) || pagination.offset < 0 {
        return Err(CoreError::db("AI call log pagination is invalid"));
    }
    Ok(())
}

fn validate_clear_request(request: &AiCallLogClearRequest) -> CoreResult<()> {
    match request.scope {
        AiCallLogClearScope::All => validate_all_clear_request(request),
        AiCallLogClearScope::SelectedEntries => validate_selected_clear_request(request),
        AiCallLogClearScope::OlderThan => validate_older_than_clear_request(request),
    }
}

fn validate_all_clear_request(request: &AiCallLogClearRequest) -> CoreResult<()> {
    if request.older_than.is_some() || !request.entry_ids.is_empty() {
        return Err(CoreError::db("AI call log clear-all request is invalid"));
    }
    Ok(())
}

fn validate_selected_clear_request(request: &AiCallLogClearRequest) -> CoreResult<()> {
    if request.entry_ids.is_empty()
        || request.entry_ids.len() > MAX_CLEAR_ENTRY_IDS
        || request.entry_ids.iter().any(|id| *id <= 0)
        || request.older_than.is_some()
    {
        return Err(CoreError::db(
            "AI call log selected-entry request is invalid",
        ));
    }
    Ok(())
}

fn validate_older_than_clear_request(request: &AiCallLogClearRequest) -> CoreResult<()> {
    if !request.entry_ids.is_empty() || !request.older_than.is_some_and(|value| value >= 0) {
        return Err(CoreError::db(
            "AI call log retention clear request is invalid",
        ));
    }
    Ok(())
}

fn is_area_matrix_component(component: Component<'_>) -> bool {
    matches!(component, Component::Normal(name) if name == AREA_MATRIX_DIR)
}

fn to_db_filter(filter: &AiCallLogFilter) -> db::AiCallLogListFilter {
    db::AiCallLogListFilter {
        feature: filter.feature.as_ref().map(feature_to_db),
        route: filter.route.as_ref().map(route_to_db),
        status: filter.status.as_ref().map(status_to_db),
        occurred_after: filter.occurred_after,
        occurred_before: filter.occurred_before,
        search_pattern: filter.search_query.as_deref().map(search_pattern),
    }
}

fn clear_spec(request: AiCallLogClearRequest) -> db::AiCallLogClearSpec {
    match request.scope {
        AiCallLogClearScope::All => db::AiCallLogClearSpec::All,
        AiCallLogClearScope::SelectedEntries => {
            db::AiCallLogClearSpec::SelectedEntries(request.entry_ids)
        }
        AiCallLogClearScope::OlderThan => {
            db::AiCallLogClearSpec::OlderThan(request.older_than.unwrap_or_default())
        }
    }
}

fn record_from_row(row: db::AiCallLogRow) -> CoreResult<AiCallLogRecord> {
    Ok(AiCallLogRecord {
        id: row.id,
        occurred_at: row.occurred_at,
        feature: feature_from_db(&row.feature)?,
        file_id: row.file_id,
        file_display_name: row.file_display_name.map(sanitize_text),
        batch_id: row.batch_id.map(sanitize_text),
        scope: row.scope.map(sanitize_text),
        route: row.route.as_deref().map(route_from_db).transpose()?,
        provider_name: row.provider_name.map(sanitize_text),
        model_name: row.model_name.map(sanitize_text),
        status: status_from_db(&row.status)?,
        duration_ms: row.duration_ms,
        sent_fields: sent_fields_from_json(&row.sent_fields_json)?,
        privacy_rules_checked: row.privacy_rules_checked,
        privacy_rule_id: row.privacy_rule_id.map(sanitize_text),
        privacy_rule_name: row.privacy_rule_name.map(sanitize_text),
        matched_field_type: row
            .matched_field_type
            .as_deref()
            .map(sent_field_from_db)
            .transpose()?,
        result_summary: sanitize_text(row.result_summary),
        error_code: row.error_code.map(sanitize_text),
    })
}

fn feature_to_db(feature: &AiCallLogFeature) -> String {
    match feature {
        AiCallLogFeature::Classification => "classification",
        AiCallLogFeature::Summary => "summary",
        AiCallLogFeature::Tags => "tags",
        AiCallLogFeature::SemanticSearch => "semantic_search",
        AiCallLogFeature::ProviderTest => "provider_test",
    }
    .to_owned()
}

fn feature_from_db(value: &str) -> CoreResult<AiCallLogFeature> {
    match value {
        "classification" | "Classification" => Ok(AiCallLogFeature::Classification),
        "summary" | "Summary" => Ok(AiCallLogFeature::Summary),
        "tags" | "Tags" => Ok(AiCallLogFeature::Tags),
        "semantic_search" | "SemanticSearch" => Ok(AiCallLogFeature::SemanticSearch),
        "provider_test" | "ProviderTest" => Ok(AiCallLogFeature::ProviderTest),
        _ => Err(CoreError::db("AI call log feature is invalid")),
    }
}

fn route_to_db(route: &AiCallLogRoute) -> String {
    match route {
        AiCallLogRoute::Local => "local",
        AiCallLogRoute::Remote => "remote",
    }
    .to_owned()
}

fn route_from_db(value: &str) -> CoreResult<AiCallLogRoute> {
    match value {
        "local" | "Local" => Ok(AiCallLogRoute::Local),
        "remote" | "Remote" => Ok(AiCallLogRoute::Remote),
        _ => Err(CoreError::db("AI call log route is invalid")),
    }
}

fn status_to_db(status: &AiCallLogStatus) -> String {
    match status {
        AiCallLogStatus::Success => "success",
        AiCallLogStatus::Failed => "failed",
        AiCallLogStatus::Skipped => "skipped",
        AiCallLogStatus::Unavailable => "unavailable",
    }
    .to_owned()
}

fn status_from_db(value: &str) -> CoreResult<AiCallLogStatus> {
    match value {
        "success" | "Success" => Ok(AiCallLogStatus::Success),
        "failed" | "Failed" => Ok(AiCallLogStatus::Failed),
        "skipped" | "Skipped" => Ok(AiCallLogStatus::Skipped),
        "unavailable" | "Unavailable" => Ok(AiCallLogStatus::Unavailable),
        _ => Err(CoreError::db("AI call log status is invalid")),
    }
}

fn sent_fields_from_json(value: &str) -> CoreResult<Vec<AiCallLogSentField>> {
    let raw_fields: Vec<String> = serde_json::from_str(value)
        .map_err(|_| CoreError::db("AI call log sent fields are invalid"))?;
    raw_fields
        .iter()
        .map(|field| sent_field_from_db(field))
        .collect()
}

fn sent_field_from_db(value: &str) -> CoreResult<AiCallLogSentField> {
    match value {
        "filename" | "file_name" | "FileName" => Ok(AiCallLogSentField::FileName),
        "repo_relative_path" | "RepoRelativePath" => Ok(AiCallLogSentField::RepoRelativePath),
        "extension" | "Extension" => Ok(AiCallLogSentField::Extension),
        "limited_text_summary" | "extracted_text_excerpt" | "ExtractedTextExcerpt" => {
            Ok(AiCallLogSentField::ExtractedTextExcerpt)
        }
        "ai_summary" | "AiSummary" => Ok(AiCallLogSentField::AiSummary),
        "note_summary" | "NoteSummary" => Ok(AiCallLogSentField::NoteSummary),
        "tag_category_context" | "TagCategoryContext" => Ok(AiCallLogSentField::TagCategoryContext),
        _ => Err(CoreError::db("AI call log sent field is invalid")),
    }
}

fn search_pattern(query: &str) -> String {
    let mut escaped = String::with_capacity(query.len());
    for ch in query.chars() {
        if matches!(ch, '%' | '_' | '\\') {
            escaped.push('\\');
        }
        escaped.push(ch);
    }
    format!("%{}%", escaped.to_ascii_lowercase())
}

fn sanitize_text(value: String) -> String {
    let cleaned = value.replace('\0', "");
    let redacted = cleaned
        .split_whitespace()
        .map(redact_sensitive_token)
        .collect::<Vec<_>>()
        .join(" ");
    truncate_redacted_text(redacted)
}

fn redact_sensitive_token(token: &str) -> String {
    let normalized = token.to_ascii_lowercase();
    if normalized.contains("api_key")
        || normalized.contains("api-key")
        || normalized.contains("apikey")
        || normalized.contains("keychain:")
        || normalized.contains("secure-storage:")
        || normalized.contains("token=")
        || normalized.contains("sk-")
    {
        "[redacted]".to_owned()
    } else {
        token.to_owned()
    }
}

fn truncate_redacted_text(value: String) -> String {
    let mut chars = value.chars();
    let truncated = chars
        .by_ref()
        .take(MAX_REDACTED_TEXT_LEN)
        .collect::<String>();
    if chars.next().is_some() {
        format!("{truncated}...")
    } else {
        value
    }
}
