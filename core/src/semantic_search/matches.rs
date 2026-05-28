use std::collections::HashSet;

use crate::{CoreResult, SearchFileResult, SearchMatch, SearchMatchField, SearchMatchKind};

use super::{
    store::{SemanticFieldMatch, SemanticIndexedFile},
    SemanticNormalSearchMatch, SemanticSearchInputField, SemanticSearchMatch, SemanticSearchRoute,
};

const LOW_CONFIDENCE_THRESHOLD: f32 = 0.45;

pub(super) struct SemanticGroups {
    pub(super) semantic_matches: Vec<SemanticSearchMatch>,
    pub(super) normal_matches: Vec<SemanticNormalSearchMatch>,
    pub(super) deduped_normal_count: i64,
    pub(super) semantic_total_count: i64,
    pub(super) low_confidence: bool,
}

pub(super) fn build_index_groups(
    semantic_total_count: i64,
    indexed_files: Vec<SemanticIndexedFile>,
    normal_results: Vec<SearchFileResult>,
    route: SemanticSearchRoute,
    call_log_id: Option<i64>,
) -> CoreResult<SemanticGroups> {
    let normal_ids = normal_results
        .iter()
        .map(|row| row.entry.id)
        .collect::<HashSet<_>>();
    let semantic_matches = indexed_files
        .into_iter()
        .map(|indexed| indexed_match(indexed, route.clone(), call_log_id, &normal_ids))
        .collect::<Vec<_>>();
    let semantic_ids = semantic_matches
        .iter()
        .map(|row| row.result.entry.id)
        .collect::<HashSet<_>>();
    let deduped_normal_count = i64::try_from(
        normal_results
            .iter()
            .filter(|row| semantic_ids.contains(&row.entry.id))
            .count(),
    )
    .map_err(|error| crate::CoreError::db(error.to_string()))?;
    Ok(SemanticGroups {
        low_confidence: semantic_matches
            .iter()
            .any(|row| row.relevance < LOW_CONFIDENCE_THRESHOLD),
        semantic_matches,
        normal_matches: normal_matches(normal_results, &semantic_ids),
        deduped_normal_count,
        semantic_total_count,
    })
}

pub(super) fn normal_matches(
    results: Vec<SearchFileResult>,
    semantic_ids: &HashSet<i64>,
) -> Vec<SemanticNormalSearchMatch> {
    results
        .into_iter()
        .map(|result| SemanticNormalSearchMatch {
            deduped_by_semantic: semantic_ids.contains(&result.entry.id),
            result,
        })
        .collect()
}

fn indexed_match(
    indexed: SemanticIndexedFile,
    route: SemanticSearchRoute,
    call_log_id: Option<i64>,
    normal_ids: &HashSet<i64>,
) -> SemanticSearchMatch {
    let file_id = indexed.entry.id;
    let used_fields = used_fields(&indexed.matched_fields);
    let relevance = relevance(&indexed);
    let matches = search_matches(&indexed.matched_fields);
    let note_snippet = note_snippet(&indexed.matched_fields);
    SemanticSearchMatch {
        result: SearchFileResult {
            entry: indexed.entry,
            score: relevance,
            matches,
            note_snippet,
        },
        relevance,
        matched_reason: matched_reason(&indexed.matched_fields, relevance),
        used_fields,
        route,
        also_matched_normal_search: normal_ids.contains(&file_id),
        call_log_id,
        privacy_rule_id: None,
    }
}

fn relevance(indexed: &SemanticIndexedFile) -> f32 {
    let token_ratio = ratio(indexed.matched_token_count, indexed.query_token_count);
    let field_ratio = ratio(indexed.matched_fields.len(), indexed.field_terms.len());
    (0.15 + token_ratio * 0.65 + field_ratio * 0.20).clamp(0.0, 1.0)
}

fn ratio(numerator: usize, denominator: usize) -> f32 {
    if denominator == 0 {
        return 0.0;
    }
    numerator as f32 / denominator as f32
}

fn used_fields(matches: &[SemanticFieldMatch]) -> Vec<SemanticSearchInputField> {
    let mut fields = Vec::new();
    for matched in matches {
        if !fields.contains(&matched.field) {
            fields.push(matched.field.clone());
        }
    }
    fields
}

fn search_matches(matches: &[SemanticFieldMatch]) -> Vec<SearchMatch> {
    matches
        .iter()
        .map(|matched| SearchMatch {
            field: search_field(&matched.field),
            kind: SearchMatchKind::Exact,
            snippet: matched.source.clone(),
            start: first_start(matched),
            end: first_end(matched),
        })
        .collect()
}

fn note_snippet(matches: &[SemanticFieldMatch]) -> Option<String> {
    matches
        .iter()
        .find(|matched| matched.field == SemanticSearchInputField::NoteSummary)
        .map(|matched| matched.source.clone())
}

fn matched_reason(matches: &[SemanticFieldMatch], relevance: f32) -> String {
    let fields = matches
        .iter()
        .map(|matched| field_label(&matched.field))
        .collect::<Vec<_>>()
        .join(", ");
    let terms = matches
        .iter()
        .flat_map(|matched| matched.matched_terms.iter().map(String::as_str))
        .collect::<HashSet<_>>()
        .into_iter()
        .collect::<Vec<_>>()
        .join(", ");
    format!(
        "Matched {fields} with terms {terms}; relevance {:.2}",
        relevance
    )
}

fn search_field(field: &SemanticSearchInputField) -> SearchMatchField {
    match field {
        SemanticSearchInputField::FileName => SearchMatchField::Name,
        SemanticSearchInputField::RepoRelativePath => SearchMatchField::Path,
        SemanticSearchInputField::Category => SearchMatchField::Category,
        SemanticSearchInputField::NoteSummary
        | SemanticSearchInputField::AiSummary
        | SemanticSearchInputField::ExtractedTextExcerpt => SearchMatchField::Note,
    }
}

fn field_label(field: &SemanticSearchInputField) -> &'static str {
    match field {
        SemanticSearchInputField::FileName => "file name",
        SemanticSearchInputField::RepoRelativePath => "repo-relative path",
        SemanticSearchInputField::Category => "category",
        SemanticSearchInputField::NoteSummary => "note summary",
        SemanticSearchInputField::AiSummary => "AI summary",
        SemanticSearchInputField::ExtractedTextExcerpt => "extracted text excerpt",
    }
}

fn first_start(matched: &SemanticFieldMatch) -> Option<i64> {
    let source = matched.source.to_lowercase();
    matched
        .matched_terms
        .iter()
        .filter_map(|term| source.find(term))
        .min()
        .and_then(|index| i64::try_from(index).ok())
}

fn first_end(matched: &SemanticFieldMatch) -> Option<i64> {
    let start = first_start(matched)?;
    let source = matched.source.to_lowercase();
    let term = matched
        .matched_terms
        .iter()
        .filter(|term| source.find(*term) == usize::try_from(start).ok())
        .max_by_key(|term| term.len())?;
    i64::try_from(term.len()).ok().map(|length| start + length)
}
