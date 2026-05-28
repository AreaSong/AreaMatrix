use std::path::Path;

use rusqlite::params;

use crate::{CoreError, CoreResult, SearchFilter, SearchPagination};

use super::{privacy::PrivacyEvaluator, SemanticSearchInputField, SemanticSearchRoute};

#[path = "store/db.rs"]
mod db;
#[path = "store/types.rs"]
mod types;

use types::{Candidate, IndexStats};
pub(super) use types::{
    SemanticFieldMatch, SemanticFieldTerms, SemanticIndexBuildOutcome, SemanticIndexedFile,
    StoredSemanticIndex,
};

const SEMANTIC_INDEX_KEY: &str = "semantic_index_metadata";
const PRIVACY_RULES_KEY: &str = "ai_privacy_rules";

pub(super) fn load_semantic_index(repo: &Path) -> CoreResult<Option<StoredSemanticIndex>> {
    let connection = db::open_read_connection(repo)?;
    let Some(serialized) = db::repo_config_value(&connection, SEMANTIC_INDEX_KEY)? else {
        return Ok(None);
    };
    deserialize_index(&serialized)
}

pub(super) fn load_indexed_files(
    repo: &Path,
    query: &str,
    filter: &SearchFilter,
    pagination: &SearchPagination,
) -> CoreResult<(i64, Vec<SemanticIndexedFile>)> {
    let connection = db::open_read_connection(repo)?;
    let query_tokens = query_terms(query);
    if query_tokens.is_empty() {
        return Ok((0, Vec::new()));
    }

    let required_tags = normalized_tags(&filter.tags);
    let mut matches = db::load_indexed_candidates(&connection, filter)?
        .into_iter()
        .filter(|candidate| tags_match(&required_tags, &filter.tag_match_mode, &candidate.tags))
        .filter_map(|candidate| candidate.match_query(&query_tokens))
        .collect::<Vec<_>>();
    sort_indexed_files(&mut matches);

    let total_count =
        i64::try_from(matches.len()).map_err(|error| CoreError::db(error.to_string()))?;
    Ok((total_count, page_indexed_files(matches, pagination)?))
}

pub(super) fn save_semantic_index(
    repo: &Path,
    tx: &rusqlite::Transaction<'_>,
    route: SemanticSearchRoute,
    filter: &SearchFilter,
    _privacy_ref: Option<&str>,
) -> CoreResult<SemanticIndexBuildOutcome> {
    db::ensure_schema_tx(tx)?;
    let updated_at = db::current_timestamp(tx)?;
    let privacy_rules_json = db::repo_config_value_tx(tx, PRIVACY_RULES_KEY)?;
    let privacy = PrivacyEvaluator::from_rules_json(privacy_rules_json.as_deref())?;
    let candidates = load_candidates(tx, filter)?;
    let mut stats = IndexStats::new(route.clone(), candidates.len(), updated_at);

    tx.execute("DELETE FROM semantic_index_entries", [])
        .map_err(|error| CoreError::db(error.to_string()))?;
    let privacy_rule_id = replace_entries(repo, tx, candidates, &route, &privacy, &mut stats)?;
    stats.metadata.privacy_rule_id = privacy_rule_id.clone();
    let serialized = serialize_index(stats.metadata.clone())?;
    tx.execute(
        "INSERT INTO repo_config (key, value, updated_at) \
         VALUES (?1, ?2, ?3) \
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
        params![SEMANTIC_INDEX_KEY, serialized, updated_at],
    )
    .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(SemanticIndexBuildOutcome {
        metadata: stats.metadata,
        privacy_rule_id,
    })
}

fn load_candidates(
    tx: &rusqlite::Transaction<'_>,
    filter: &SearchFilter,
) -> CoreResult<Vec<Candidate>> {
    let required_tags = normalized_tags(&filter.tags);
    Ok(db::load_source_candidates(tx, filter)?
        .into_iter()
        .filter(|candidate| tags_match(&required_tags, &filter.tag_match_mode, &candidate.tags))
        .collect())
}

fn replace_entries(
    repo: &Path,
    tx: &rusqlite::Transaction<'_>,
    candidates: Vec<Candidate>,
    route: &SemanticSearchRoute,
    privacy: &PrivacyEvaluator,
    stats: &mut IndexStats,
) -> CoreResult<Option<String>> {
    let mut first_privacy_rule_id = None;
    for candidate in candidates {
        if let Some(rule_id) = metadata_privacy_blocking_rule(&candidate, route, privacy) {
            stats.privacy_skipped += 1;
            first_privacy_rule_id.get_or_insert(rule_id);
            continue;
        }
        let field_terms = candidate.field_terms(repo)?;
        if field_terms.content_failed {
            stats.metadata.failed_count += 1;
            continue;
        }
        if field_terms.fields.is_empty() {
            stats.skipped += 1;
            continue;
        }
        if field_terms.content_inspected {
            if let Some(rule_id) =
                field_privacy_blocking_rule(&candidate, route, privacy, &field_terms.fields)
            {
                stats.privacy_skipped += 1;
                first_privacy_rule_id.get_or_insert(rule_id);
                continue;
            }
        }
        db::insert_index_entry(tx, candidate.entry.id, &field_terms.fields, &candidate.tags)?;
        stats.processed += 1;
    }
    stats.finish();
    Ok(first_privacy_rule_id)
}

fn metadata_privacy_blocking_rule(
    candidate: &Candidate,
    route: &SemanticSearchRoute,
    privacy: &PrivacyEvaluator,
) -> Option<String> {
    let metadata_terms = candidate.metadata_field_terms();
    let metadata_texts = field_sources(&metadata_terms);
    privacy.blocking_rule(&candidate.privacy_input(route, &metadata_texts))
}

fn field_privacy_blocking_rule(
    candidate: &Candidate,
    route: &SemanticSearchRoute,
    privacy: &PrivacyEvaluator,
    fields: &[SemanticFieldTerms],
) -> Option<String> {
    let texts = field_sources(fields);
    privacy.blocking_rule(&candidate.privacy_input(route, &texts))
}

fn field_sources(fields: &[SemanticFieldTerms]) -> Vec<&str> {
    fields.iter().map(|field| field.source.as_str()).collect()
}

fn query_terms(value: &str) -> Vec<String> {
    let mut terms = Vec::new();
    for term in value.split(|ch: char| !ch.is_alphanumeric()) {
        let normalized = term.trim().to_lowercase();
        if !normalized.is_empty() && !terms.contains(&normalized) {
            terms.push(normalized);
        }
    }
    terms
}

fn sort_indexed_files(files: &mut [SemanticIndexedFile]) {
    files.sort_by(|left, right| {
        right
            .matched_token_count
            .cmp(&left.matched_token_count)
            .then_with(|| right.matched_fields.len().cmp(&left.matched_fields.len()))
            .then_with(|| right.entry.imported_at.cmp(&left.entry.imported_at))
            .then_with(|| left.entry.id.cmp(&right.entry.id))
    });
}

fn page_indexed_files(
    files: Vec<SemanticIndexedFile>,
    pagination: &SearchPagination,
) -> CoreResult<Vec<SemanticIndexedFile>> {
    let start = usize::try_from(pagination.offset)
        .map_err(|_| CoreError::config("semantic search pagination is invalid"))?;
    let take = usize::try_from(pagination.limit)
        .map_err(|_| CoreError::config("semantic search pagination is invalid"))?;
    Ok(files.into_iter().skip(start).take(take).collect())
}

fn normalized_tags(tags: &[String]) -> Vec<String> {
    tags.iter().map(|tag| tag.to_lowercase()).collect()
}

fn tags_match(
    required_tags: &[String],
    mode: &crate::SearchTagMatchMode,
    actual_tags: &[String],
) -> bool {
    if required_tags.is_empty() {
        return true;
    }
    match mode {
        crate::SearchTagMatchMode::Any => required_tags
            .iter()
            .any(|tag| value_matches_tag(tag, actual_tags)),
        crate::SearchTagMatchMode::All => required_tags
            .iter()
            .all(|tag| value_matches_tag(tag, actual_tags)),
    }
}

fn value_matches_tag(required: &str, actual_tags: &[String]) -> bool {
    actual_tags
        .iter()
        .any(|tag| tag.to_lowercase().contains(required))
}

fn serialize_index(metadata: StoredSemanticIndex) -> CoreResult<String> {
    serde_json::to_string(&metadata)
        .map_err(|_| CoreError::db("semantic index metadata is invalid"))
}

fn deserialize_index(serialized: &str) -> CoreResult<Option<StoredSemanticIndex>> {
    serde_json::from_str(serialized)
        .map(Some)
        .map_err(|_| CoreError::db("semantic index metadata is invalid"))
}

fn push_field_terms(
    fields: &mut Vec<SemanticFieldTerms>,
    field: SemanticSearchInputField,
    source: String,
) {
    let terms = query_terms(&source);
    if !terms.is_empty() {
        fields.push(SemanticFieldTerms {
            field,
            source: types::excerpt(&source),
            terms,
        });
    }
}
