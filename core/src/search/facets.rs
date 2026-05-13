use std::{collections::BTreeMap, path::Path};

use crate::{
    CoreError, CoreResult, SearchDateFacetBounds, SearchFacetCount, SearchFacetQuery, SearchFacets,
    SearchFilter, SearchStorageModeFacetCount, SearchTagMatchMode, StorageMode,
};

use super::{
    parser::{has_error_diagnostic, parse_query},
    ranking::row_matches_terms,
    repo::{query_rows, validated_repo_path, SearchRow},
    validation::validate_facet_query,
};

pub(super) fn list_filter_facets(
    repo_path: String,
    query: SearchFacetQuery,
) -> CoreResult<SearchFacets> {
    validate_facet_query(&query)?;
    let parsed = parse_query(query.query.clone());
    if has_error_diagnostic(&parsed.diagnostics) {
        return Err(CoreError::config("facet query contains parser diagnostics"));
    }

    let repo = validated_repo_path(&repo_path)
        .map_err(|_| CoreError::config("repository path is invalid for facets"))?;
    let search_filter = facet_query_search_filter(&query);
    let rows = query_rows(&repo, &search_filter)?
        .into_iter()
        .filter(|row| row_matches_terms(row, &parsed.terms))
        .collect::<Vec<_>>();

    Ok(SearchFacets {
        query: query.query.clone(),
        total_count: count_rows(&rows, &query, FilterMask::all())?,
        categories: category_facets(&rows, &query)?,
        file_kinds: file_kind_facets(&rows, &query)?,
        tags: tag_facets(&rows, &query)?,
        storage_modes: storage_mode_facets(&rows, &query)?,
        date_bounds: date_bounds(&rows, &query),
        active_filter_count: active_filter_count(&query),
    })
}

fn facet_query_search_filter(query: &SearchFacetQuery) -> SearchFilter {
    SearchFilter {
        scope: query.scope.clone(),
        current_path: query.current_path.clone(),
        category: None,
        file_kind: None,
        tags: Vec::new(),
        tag_match_mode: query.tag_match_mode.clone(),
        imported_after: None,
        imported_before: None,
        modified_after: None,
        modified_before: None,
        storage_mode: None,
        include_deleted: query.include_deleted,
    }
}

#[derive(Clone, Copy)]
struct FilterMask {
    category: bool,
    file_kind: bool,
    tags: bool,
    imported_date: bool,
    modified_date: bool,
    storage_mode: bool,
}

impl FilterMask {
    fn all() -> Self {
        Self {
            category: true,
            file_kind: true,
            tags: true,
            imported_date: true,
            modified_date: true,
            storage_mode: true,
        }
    }

    fn without_category(self) -> Self {
        Self {
            category: false,
            ..self
        }
    }

    fn without_file_kind(self) -> Self {
        Self {
            file_kind: false,
            ..self
        }
    }

    fn without_tags(self) -> Self {
        Self {
            tags: false,
            ..self
        }
    }

    fn without_storage_mode(self) -> Self {
        Self {
            storage_mode: false,
            ..self
        }
    }

    fn without_dates(self) -> Self {
        Self {
            imported_date: false,
            modified_date: false,
            ..self
        }
    }
}

fn category_facets(
    rows: &[SearchRow],
    query: &SearchFacetQuery,
) -> CoreResult<Vec<SearchFacetCount>> {
    let counts = string_counts(rows, query, FilterMask::all().without_category(), |row| {
        Some(row.entry.category.clone())
    })?;
    let mut facets = string_facets(counts, query.category.as_deref());
    ensure_selected_string(&mut facets, query.category.as_deref());
    Ok(facets)
}

fn file_kind_facets(
    rows: &[SearchRow],
    query: &SearchFacetQuery,
) -> CoreResult<Vec<SearchFacetCount>> {
    let counts = string_counts(rows, query, FilterMask::all().without_file_kind(), |row| {
        file_kind_value(&row.entry.current_name)
    })?;
    let mut facets = string_facets(counts, query.file_kind.as_deref());
    ensure_selected_string(&mut facets, query.file_kind.as_deref());
    Ok(facets)
}

fn tag_facets(rows: &[SearchRow], query: &SearchFacetQuery) -> CoreResult<Vec<SearchFacetCount>> {
    let mut counts = BTreeMap::new();
    for row in rows_matching(rows, query, FilterMask::all().without_tags()) {
        for tag in &row.tags {
            let normalized = normalized_text(tag);
            *counts.entry(normalized).or_insert(0_i64) += 1;
        }
    }

    let selected = query.tags.iter().map(String::as_str).collect::<Vec<_>>();
    let mut facets = string_facets_multi_selected(counts, &selected);
    for tag in &query.tags {
        ensure_selected_string(&mut facets, Some(tag));
    }
    Ok(facets)
}

fn storage_mode_facets(
    rows: &[SearchRow],
    query: &SearchFacetQuery,
) -> CoreResult<Vec<SearchStorageModeFacetCount>> {
    let mut counts = BTreeMap::new();
    for row in rows_matching(rows, query, FilterMask::all().without_storage_mode()) {
        *counts
            .entry(storage_mode_key(&row.entry.storage_mode))
            .or_insert(0_i64) += 1;
    }

    Ok(storage_modes()
        .into_iter()
        .map(|mode| {
            let count = *counts.get(storage_mode_key(&mode)).unwrap_or(&0);
            let selected = query.storage_mode.as_ref() == Some(&mode);
            SearchStorageModeFacetCount {
                label: storage_mode_label(&mode).to_owned(),
                value: mode,
                count,
                selected,
                disabled: count == 0 && !selected,
            }
        })
        .collect())
}

fn date_bounds(rows: &[SearchRow], query: &SearchFacetQuery) -> SearchDateFacetBounds {
    let mut bounds = DateBoundsAccumulator::default();
    for row in rows_matching(rows, query, FilterMask::all().without_dates()) {
        bounds.add(row.entry.imported_at, row.entry.updated_at);
    }
    bounds.into_bounds()
}

fn count_rows(rows: &[SearchRow], query: &SearchFacetQuery, mask: FilterMask) -> CoreResult<i64> {
    i64::try_from(rows_matching(rows, query, mask).count())
        .map_err(|error| CoreError::db(error.to_string()))
}

fn string_counts<F>(
    rows: &[SearchRow],
    query: &SearchFacetQuery,
    mask: FilterMask,
    value: F,
) -> CoreResult<BTreeMap<String, i64>>
where
    F: Fn(&SearchRow) -> Option<String>,
{
    let mut counts = BTreeMap::new();
    for row in rows_matching(rows, query, mask) {
        if let Some(value) = value(row) {
            *counts.entry(value).or_insert(0_i64) += 1;
        }
    }
    Ok(counts)
}

fn rows_matching<'a>(
    rows: &'a [SearchRow],
    query: &'a SearchFacetQuery,
    mask: FilterMask,
) -> impl Iterator<Item = &'a SearchRow> {
    rows.iter()
        .filter(move |row| row_matches_filter(row, query, mask))
}

fn row_matches_filter(row: &SearchRow, query: &SearchFacetQuery, mask: FilterMask) -> bool {
    matches_optional_text(
        mask.category,
        query.category.as_deref(),
        &row.entry.category,
    ) && matches_file_kind(
        mask.file_kind,
        query.file_kind.as_deref(),
        &row.entry.current_name,
    ) && matches_tags(mask.tags, &query.tags, &query.tag_match_mode, &row.tags)
        && matches_range(
            mask.imported_date,
            row.entry.imported_at,
            query.imported_after,
            query.imported_before,
        )
        && matches_range(
            mask.modified_date,
            row.entry.updated_at,
            query.modified_after,
            query.modified_before,
        )
        && matches_storage_mode(
            mask.storage_mode,
            query.storage_mode.as_ref(),
            &row.entry.storage_mode,
        )
}

fn matches_optional_text(enabled: bool, expected: Option<&str>, actual: &str) -> bool {
    if !enabled {
        return true;
    }
    expected.map_or(true, |expected| {
        normalized_text(expected) == normalized_text(actual)
    })
}

fn matches_file_kind(enabled: bool, expected: Option<&str>, filename: &str) -> bool {
    if !enabled {
        return true;
    }
    expected.map_or(true, |expected| {
        file_kind_value(filename)
            .as_deref()
            .is_some_and(|actual| normalized_text(expected) == actual)
    })
}

fn matches_tags(
    enabled: bool,
    expected: &[String],
    mode: &SearchTagMatchMode,
    actual: &[String],
) -> bool {
    if !enabled || expected.is_empty() {
        return true;
    }
    let actual = actual
        .iter()
        .map(|tag| normalized_text(tag))
        .collect::<Vec<_>>();
    match mode {
        SearchTagMatchMode::Any => expected
            .iter()
            .map(|tag| normalized_text(tag))
            .any(|tag| actual.contains(&tag)),
        SearchTagMatchMode::All => expected
            .iter()
            .map(|tag| normalized_text(tag))
            .all(|tag| actual.contains(&tag)),
    }
}

fn matches_range(enabled: bool, value: i64, after: Option<i64>, before: Option<i64>) -> bool {
    if !enabled {
        return true;
    }
    after.map_or(true, |after| value >= after) && before.map_or(true, |before| value < before)
}

fn matches_storage_mode(
    enabled: bool,
    expected: Option<&StorageMode>,
    actual: &StorageMode,
) -> bool {
    !enabled || expected.map_or(true, |expected| expected == actual)
}

fn string_facets(counts: BTreeMap<String, i64>, selected: Option<&str>) -> Vec<SearchFacetCount> {
    counts
        .into_iter()
        .map(|(value, count)| string_facet(value, count, selected))
        .collect()
}

fn string_facets_multi_selected(
    counts: BTreeMap<String, i64>,
    selected: &[&str],
) -> Vec<SearchFacetCount> {
    counts
        .into_iter()
        .map(|(value, count)| {
            let selected = selected
                .iter()
                .any(|selected| normalized_text(selected) == value);
            SearchFacetCount {
                label: value.clone(),
                value,
                count,
                selected,
                disabled: count == 0 && !selected,
            }
        })
        .collect()
}

fn string_facet(value: String, count: i64, selected: Option<&str>) -> SearchFacetCount {
    let selected = selected.is_some_and(|selected| normalized_text(selected) == value);
    SearchFacetCount {
        label: value.clone(),
        value,
        count,
        selected,
        disabled: count == 0 && !selected,
    }
}

fn ensure_selected_string(facets: &mut Vec<SearchFacetCount>, selected: Option<&str>) {
    let Some(selected) = selected else {
        return;
    };
    let normalized = normalized_text(selected);
    if facets.iter().any(|facet| facet.value == normalized) {
        return;
    }
    facets.push(SearchFacetCount {
        value: normalized.clone(),
        label: normalized,
        count: 0,
        selected: true,
        disabled: false,
    });
    facets.sort_by(|left, right| left.value.cmp(&right.value));
}

fn file_kind_value(filename: &str) -> Option<String> {
    Path::new(filename)
        .extension()
        .and_then(|extension| extension.to_str())
        .map(normalized_text)
        .filter(|extension| !extension.is_empty())
}

fn active_filter_count(query: &SearchFacetQuery) -> i64 {
    i64::from(query.category.is_some())
        + i64::from(query.file_kind.is_some())
        + i64::from(!query.tags.is_empty())
        + i64::from(query.imported_after.is_some() || query.imported_before.is_some())
        + i64::from(query.modified_after.is_some() || query.modified_before.is_some())
        + i64::from(query.storage_mode.is_some())
        + i64::from(query.include_deleted.unwrap_or(false))
}

#[derive(Default)]
struct DateBoundsAccumulator {
    oldest_imported_at: Option<i64>,
    newest_imported_at: Option<i64>,
    oldest_modified_at: Option<i64>,
    newest_modified_at: Option<i64>,
}

impl DateBoundsAccumulator {
    fn add(&mut self, imported_at: i64, modified_at: i64) {
        self.oldest_imported_at = min_option(self.oldest_imported_at, imported_at);
        self.newest_imported_at = max_option(self.newest_imported_at, imported_at);
        self.oldest_modified_at = min_option(self.oldest_modified_at, modified_at);
        self.newest_modified_at = max_option(self.newest_modified_at, modified_at);
    }

    fn into_bounds(self) -> SearchDateFacetBounds {
        SearchDateFacetBounds {
            oldest_imported_at: self.oldest_imported_at,
            newest_imported_at: self.newest_imported_at,
            oldest_modified_at: self.oldest_modified_at,
            newest_modified_at: self.newest_modified_at,
        }
    }
}

fn min_option(current: Option<i64>, value: i64) -> Option<i64> {
    Some(current.map_or(value, |current| current.min(value)))
}

fn max_option(current: Option<i64>, value: i64) -> Option<i64> {
    Some(current.map_or(value, |current| current.max(value)))
}

fn storage_modes() -> [StorageMode; 3] {
    [
        StorageMode::Copied,
        StorageMode::Moved,
        StorageMode::Indexed,
    ]
}

fn storage_mode_key(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "Moved",
        StorageMode::Copied => "Copied",
        StorageMode::Indexed => "Indexed",
    }
}

fn storage_mode_label(mode: &StorageMode) -> &'static str {
    storage_mode_key(mode)
}

fn normalized_text(value: &str) -> String {
    value.trim().to_lowercase()
}
