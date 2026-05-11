use std::path::Path;

use chrono::NaiveDate;

use crate::{
    CoreError, CoreResult, SearchFileResult, SearchFilter, SearchMatch, SearchMatchField,
    SearchMatchKind, SearchPagination, SearchSort,
};

use super::{
    parser::{edit_distance, QueryField, QueryTerm},
    pinyin,
    repo::SearchRow,
};

const MAX_LIMIT: i64 = 1000;
const DEFAULT_LIMIT: i64 = 50;

pub(super) struct RankedSearchRow {
    row: SearchRow,
    score: f32,
    matches: Vec<SearchMatch>,
    note_snippet: Option<String>,
}

pub(super) fn rank_rows(
    rows: Vec<SearchRow>,
    terms: &[QueryTerm],
    filter: &SearchFilter,
) -> CoreResult<Vec<RankedSearchRow>> {
    let required_tags = normalize_terms(&filter.tags);
    let mut ranked = Vec::new();
    for row in rows {
        if !required_tags
            .iter()
            .all(|tag| value_matches_any(tag, &row.tags))
        {
            continue;
        }
        if let Some(result) = rank_row(row, terms) {
            ranked.push(result);
        }
    }
    Ok(ranked)
}

pub(super) fn row_matches_terms(row: &SearchRow, terms: &[QueryTerm]) -> bool {
    terms.is_empty() || terms.iter().all(|term| match_term(row, term).is_some())
}

pub(super) fn sort_ranked_rows(rows: &mut [RankedSearchRow], sort: &SearchSort) {
    match sort {
        SearchSort::Relevance => sort_by_relevance(rows),
        SearchSort::NewestImported => sort_by_imported(rows),
        SearchSort::NewestModified => sort_by_modified(rows),
        SearchSort::NameAsc => sort_by_name(rows),
    }
}

pub(super) fn page_results(
    ranked: Vec<RankedSearchRow>,
    pagination: SearchPagination,
) -> CoreResult<Vec<SearchFileResult>> {
    let limit = normalized_limit(pagination.limit);
    let offset = pagination.offset.max(0);
    let start = usize::try_from(offset).map_err(|_| CoreError::config("configuration error"))?;
    let take = usize::try_from(limit).map_err(|_| CoreError::config("configuration error"))?;

    Ok(ranked
        .into_iter()
        .skip(start)
        .take(take)
        .map(search_file_result)
        .collect())
}

fn rank_row(row: SearchRow, terms: &[QueryTerm]) -> Option<RankedSearchRow> {
    if terms.is_empty() {
        return Some(RankedSearchRow {
            row,
            score: 1.0,
            matches: Vec::new(),
            note_snippet: None,
        });
    }

    let mut score = 0.0_f32;
    let mut matches = Vec::new();
    let mut note_snippet = None;
    for term in terms {
        let (term_score, mut term_matches, matched_note) = match_term(&row, term)?;
        score += term_score;
        matches.append(&mut term_matches);
        note_snippet = note_snippet.or(matched_note);
    }

    Some(RankedSearchRow {
        row,
        score,
        matches,
        note_snippet,
    })
}

fn match_term(
    row: &SearchRow,
    term: &QueryTerm,
) -> Option<(f32, Vec<SearchMatch>, Option<String>)> {
    match term.field {
        Some(QueryField::Kind) => match_file_kind(row, &term.value),
        Some(QueryField::Category) => match_category(row, &term.value),
        Some(QueryField::After) => match_date_after(row, &term.value),
        Some(QueryField::Before) => match_date_before(row, &term.value),
        Some(QueryField::Tag) => match_tag(row, &term.value),
        Some(QueryField::Note) => match_note(row, &term.value),
        None => match_keyword(row, &term.value),
    }
}

fn match_file_kind(
    row: &SearchRow,
    value: &str,
) -> Option<(f32, Vec<SearchMatch>, Option<String>)> {
    let normalized = normalized_text(value);
    let extension = Path::new(&row.entry.current_name)
        .extension()
        .and_then(|value| value.to_str())
        .map(normalized_text)
        .unwrap_or_default();
    (extension == normalized).then(|| {
        let matched = field_match(
            SearchMatchField::Name,
            SearchMatchKind::Exact,
            row.entry.current_name.clone(),
            &normalized,
        );
        (4.0, vec![matched], None)
    })
}

fn match_category(row: &SearchRow, value: &str) -> Option<(f32, Vec<SearchMatch>, Option<String>)> {
    let normalized = normalized_text(value);
    normalized_text(&row.entry.category)
        .contains(&normalized)
        .then(|| {
            let matched = field_match(
                SearchMatchField::Category,
                SearchMatchKind::Exact,
                row.entry.category.clone(),
                &normalized,
            );
            (3.0, vec![matched], None)
        })
}

fn match_tag(row: &SearchRow, value: &str) -> Option<(f32, Vec<SearchMatch>, Option<String>)> {
    let normalized = normalized_text(value);
    value_matches_any(&normalized, &row.tags).then_some((2.0, Vec::new(), None))
}

fn match_note(row: &SearchRow, value: &str) -> Option<(f32, Vec<SearchMatch>, Option<String>)> {
    let normalized = normalized_text(value);
    first_field_match(
        row.notes.iter().map(String::as_str),
        &normalized,
        SearchMatchField::Note,
    )
    .map(|matched| {
        let snippet = matched.snippet.clone();
        (2.5, vec![matched], Some(snippet))
    })
}

fn match_date_after(
    row: &SearchRow,
    value: &str,
) -> Option<(f32, Vec<SearchMatch>, Option<String>)> {
    let timestamp = parse_date_start(value)?;
    (row.entry.updated_at.max(row.entry.imported_at) >= timestamp).then_some((
        0.0,
        Vec::new(),
        None,
    ))
}

fn match_date_before(
    row: &SearchRow,
    value: &str,
) -> Option<(f32, Vec<SearchMatch>, Option<String>)> {
    let timestamp = parse_date_start(value)?;
    (row.entry.updated_at.max(row.entry.imported_at) < timestamp).then_some((0.0, Vec::new(), None))
}

fn parse_date_start(value: &str) -> Option<i64> {
    let date = NaiveDate::parse_from_str(value, "%Y-%m-%d").ok()?;
    date.and_hms_opt(0, 0, 0)
        .map(|datetime| datetime.and_utc().timestamp())
}

fn match_keyword(row: &SearchRow, value: &str) -> Option<(f32, Vec<SearchMatch>, Option<String>)> {
    let normalized = normalized_text(value);
    let mut result = MatchAccumulator::default();
    add_name_match(row, &normalized, &mut result);
    add_field_match(
        [row.entry.path.as_str()],
        &normalized,
        SearchMatchField::Path,
        4.0,
        &mut result,
    );
    add_note_match(row, &normalized, &mut result);
    add_field_match(
        [row.entry.category.as_str()],
        &normalized,
        SearchMatchField::Category,
        2.5,
        &mut result,
    );
    add_field_match(
        row.changes.iter().map(String::as_str),
        &normalized,
        SearchMatchField::ChangeLog,
        2.0,
        &mut result,
    );
    result.into_match()
}

#[derive(Default)]
struct MatchAccumulator {
    score: f32,
    matches: Vec<SearchMatch>,
    note_snippet: Option<String>,
}

impl MatchAccumulator {
    fn add(&mut self, score: f32, matched: SearchMatch) {
        self.score += score;
        self.matches.push(matched);
    }

    fn into_match(self) -> Option<(f32, Vec<SearchMatch>, Option<String>)> {
        (self.score > 0.0).then_some((self.score, self.matches, self.note_snippet))
    }
}

fn add_name_match(row: &SearchRow, normalized: &str, result: &mut MatchAccumulator) {
    let name_values = [
        row.entry.current_name.as_str(),
        row.entry.original_name.as_str(),
    ];
    if let Some(matched) = first_field_match(name_values, normalized, SearchMatchField::Name) {
        result.add(5.0, matched);
    } else if let Some(fuzzy) = fuzzy_name_match(row, normalized) {
        result.add(2.0, fuzzy);
    }
}

fn add_note_match(row: &SearchRow, normalized: &str, result: &mut MatchAccumulator) {
    if let Some(matched) = first_field_match(
        row.notes.iter().map(String::as_str),
        normalized,
        SearchMatchField::Note,
    ) {
        result.note_snippet = Some(matched.snippet.clone());
        result.add(3.0, matched);
    }
}

fn add_field_match<'a, I>(
    values: I,
    normalized: &str,
    field: SearchMatchField,
    score: f32,
    result: &mut MatchAccumulator,
) where
    I: IntoIterator<Item = &'a str>,
{
    if let Some(matched) = first_field_match(values, normalized, field) {
        result.add(score, matched);
    }
}

fn first_field_match<'a, I>(
    values: I,
    normalized_needle: &str,
    field: SearchMatchField,
) -> Option<SearchMatch>
where
    I: IntoIterator<Item = &'a str>,
{
    values
        .into_iter()
        .filter(|value| !value.is_empty())
        .find_map(|value| exact_match(value, normalized_needle, field.clone()))
}

fn exact_match(
    value: &str,
    normalized_needle: &str,
    field: SearchMatchField,
) -> Option<SearchMatch> {
    let normalized_value = normalized_text(value);
    normalized_value.contains(normalized_needle).then(|| {
        field_match(
            field,
            SearchMatchKind::Exact,
            value.to_owned(),
            normalized_needle,
        )
    })
}

fn fuzzy_name_match(row: &SearchRow, normalized_needle: &str) -> Option<SearchMatch> {
    if fuzzy_keyword_matches(&row.entry.current_name, normalized_needle) {
        return fuzzy_match(row, normalized_needle, SearchMatchKind::Fuzzy);
    }
    initials_match(
        [&row.entry.current_name, &row.entry.original_name],
        normalized_needle,
    )
    .then(|| fuzzy_match(row, normalized_needle, SearchMatchKind::PinyinInitials))
    .flatten()
}

fn fuzzy_keyword_matches(value: &str, normalized_needle: &str) -> bool {
    if normalized_needle.len() < 3 {
        return false;
    }
    let threshold = if normalized_needle.chars().count() > 5 {
        2
    } else {
        1
    };
    normalized_text(value)
        .split(|character: char| !character.is_alphanumeric())
        .any(|word| edit_distance(word, normalized_needle) <= threshold)
}

fn fuzzy_match(
    row: &SearchRow,
    normalized_needle: &str,
    kind: SearchMatchKind,
) -> Option<SearchMatch> {
    Some(field_match(
        SearchMatchField::Name,
        kind,
        row.entry.current_name.clone(),
        normalized_needle,
    ))
}

fn initials_match<'a, I>(values: I, normalized_needle: &str) -> bool
where
    I: IntoIterator<Item = &'a String>,
{
    values.into_iter().any(|value| {
        let initials = pinyin::initials_for(value);
        !initials.is_empty() && initials.contains(normalized_needle)
    })
}

fn value_matches_any(normalized_needle: &str, values: &[String]) -> bool {
    values
        .iter()
        .any(|value| normalized_text(value).contains(normalized_needle))
}

fn normalize_terms(values: &[String]) -> Vec<String> {
    values.iter().map(|value| normalized_text(value)).collect()
}

fn normalized_text(value: &str) -> String {
    value.to_lowercase()
}

fn field_match(
    field: SearchMatchField,
    kind: SearchMatchKind,
    snippet: String,
    normalized_needle: &str,
) -> SearchMatch {
    let normalized_snippet = normalized_text(&snippet);
    let start = normalized_snippet
        .find(normalized_needle)
        .and_then(|index| i64::try_from(index).ok());
    let end = start.and_then(|start| {
        i64::try_from(normalized_needle.len())
            .ok()
            .map(|length| start + length)
    });
    SearchMatch {
        field,
        kind,
        snippet,
        start,
        end,
    }
}

fn sort_by_relevance(rows: &mut [RankedSearchRow]) {
    rows.sort_by(|left, right| {
        right
            .score
            .total_cmp(&left.score)
            .then_with(|| right.row.entry.imported_at.cmp(&left.row.entry.imported_at))
            .then_with(|| left.row.entry.id.cmp(&right.row.entry.id))
    });
}

fn sort_by_imported(rows: &mut [RankedSearchRow]) {
    rows.sort_by(|left, right| {
        right
            .row
            .entry
            .imported_at
            .cmp(&left.row.entry.imported_at)
            .then_with(|| left.row.entry.id.cmp(&right.row.entry.id))
    });
}

fn sort_by_modified(rows: &mut [RankedSearchRow]) {
    rows.sort_by(|left, right| {
        right
            .row
            .entry
            .updated_at
            .cmp(&left.row.entry.updated_at)
            .then_with(|| left.row.entry.id.cmp(&right.row.entry.id))
    });
}

fn sort_by_name(rows: &mut [RankedSearchRow]) {
    rows.sort_by(|left, right| {
        normalized_text(&left.row.entry.current_name)
            .cmp(&normalized_text(&right.row.entry.current_name))
            .then_with(|| left.row.entry.id.cmp(&right.row.entry.id))
    });
}

fn normalized_limit(limit: i64) -> i64 {
    if limit <= 0 {
        DEFAULT_LIMIT
    } else {
        limit.min(MAX_LIMIT)
    }
}

fn search_file_result(ranked_row: RankedSearchRow) -> SearchFileResult {
    SearchFileResult {
        entry: ranked_row.row.entry,
        score: ranked_row.score,
        matches: ranked_row.matches,
        note_snippet: ranked_row.note_snippet,
    }
}
