use std::{collections::HashSet, path::Path};

use crate::{
    db, ApplyTagSuggestionItem, ApplyTagSuggestionsRequest, CoreError, CoreResult, TagSuggestion,
    TagSuggestionApplyReport, TagSuggestionMatch, TagSuggestionReport, TagSuggestionRequest,
    TagSuggestionSource, TagSuggestionStatus,
};

use super::{
    normalize_tag_metadata_error, validate_apply_suggestions, validate_file_id,
    validate_suggestion_context, validate_suggestion_limit, validate_tag_suggestion_repo_path,
};

const MIN_SUGGESTION_LEN: usize = 2;

pub(super) fn suggest_tags_for_file(
    repo_path: String,
    request: TagSuggestionRequest,
) -> CoreResult<TagSuggestionReport> {
    let repo = validate_tag_suggestion_repo_path(&repo_path)?;
    validate_file_id(request.file_id)?;
    validate_suggestion_limit(request.limit)?;
    validate_suggestion_context(request.context.as_ref())?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;

    let snapshot = db::load_tag_suggestion_snapshot(&repo, request.file_id)
        .map_err(normalize_tag_metadata_error)?;
    let suggestions = build_suggestions(&snapshot, &request)?;

    Ok(TagSuggestionReport {
        file_id: request.file_id,
        suggestions,
        tag_set: snapshot.tag_set,
        contents_read: false,
        ai_used: false,
        network_used: false,
    })
}

pub(super) fn apply_tag_suggestions(
    repo_path: String,
    request: ApplyTagSuggestionsRequest,
) -> CoreResult<TagSuggestionApplyReport> {
    let repo = validate_tag_suggestion_repo_path(&repo_path)?;
    validate_file_id(request.file_id)?;
    let slugs = validate_apply_suggestions(&request.suggestions)?;
    db::ensure_initialized(&repo).map_err(normalize_tag_metadata_error)?;

    let rows = request
        .suggestions
        .iter()
        .zip(slugs)
        .map(|(item, slug)| db::TagSuggestionApplyRow {
            suggestion_id: item.suggestion_id.trim().to_owned(),
            slug,
            display_name: display_name(item),
        })
        .collect::<Vec<_>>();
    db::apply_tag_suggestion_rows(&repo, request.file_id, &rows)
        .map_err(normalize_tag_metadata_error)
}

fn build_suggestions(
    snapshot: &db::TagSuggestionSnapshot,
    request: &TagSuggestionRequest,
) -> CoreResult<Vec<TagSuggestion>> {
    if snapshot.file.current_name.trim().is_empty() || snapshot.file.path.trim().is_empty() {
        return Err(CoreError::conflict(format!("file:{}", request.file_id)));
    }

    let registry = TagRegistry::new(snapshot);
    let mut builder = SuggestionBuilder::new(registry);
    for seed in suggestion_seeds(snapshot, request) {
        builder.push_seed(seed);
        if builder.len() >= request.limit as usize {
            return Ok(builder.into_suggestions());
        }
    }
    builder.push_existing_patterns(snapshot);
    Ok(builder.into_suggestions_limited(request.limit as usize))
}

fn suggestion_seeds(
    snapshot: &db::TagSuggestionSnapshot,
    request: &TagSuggestionRequest,
) -> Vec<SuggestionSeed> {
    let mut seeds = Vec::new();
    push_text_seeds(
        &mut seeds,
        &file_stem(&snapshot.file.current_name),
        TagSuggestionSource::FileName,
        format!("Matched file name: {}", snapshot.file.current_name),
    );
    push_path_seeds(&mut seeds, &snapshot.file.path);

    if let Some(source_path) = snapshot.file.source_path.as_deref() {
        if let Some(parent) = Path::new(source_path).parent() {
            push_source_folder_seeds(&mut seeds, &parent.to_string_lossy());
        }
    }
    if let Some(context) = request.context.as_ref() {
        if let Some(source_folder) = context.source_folder.as_deref() {
            push_source_folder_seeds(&mut seeds, source_folder);
        }
        for keyword in &context.source_keywords {
            push_text_seeds(
                &mut seeds,
                keyword,
                TagSuggestionSource::SourceFolder,
                format!("Matched source keyword: {}", keyword.trim()),
            );
        }
    }
    seeds
}

fn push_path_seeds(seeds: &mut Vec<SuggestionSeed>, relative_path: &str) {
    let path = Path::new(relative_path);
    let Some(parent) = path.parent() else {
        return;
    };
    for component in parent.components() {
        let value = component.as_os_str().to_string_lossy();
        if value == "." || value == ".." {
            continue;
        }
        push_text_seeds(
            seeds,
            &value,
            TagSuggestionSource::Path,
            format!("Matched path: {value}"),
        );
    }
}

fn push_source_folder_seeds(seeds: &mut Vec<SuggestionSeed>, source_folder: &str) {
    for component in Path::new(source_folder).components() {
        let value = component.as_os_str().to_string_lossy();
        if value == "." || value == ".." {
            continue;
        }
        push_text_seeds(
            seeds,
            &value,
            TagSuggestionSource::SourceFolder,
            format!("Matched source folder: {value}"),
        );
    }
}

fn push_text_seeds(
    seeds: &mut Vec<SuggestionSeed>,
    value: &str,
    source: TagSuggestionSource,
    reason: String,
) {
    if let Some(slug) = slug_from_text(value) {
        seeds.push(SuggestionSeed {
            slug,
            source: source.clone(),
            reason: reason.clone(),
        });
    }
    for word in token_words(value) {
        if let Some(slug) = slug_from_text(&word) {
            seeds.push(SuggestionSeed {
                slug,
                source: source.clone(),
                reason: reason.clone(),
            });
        }
    }
}

fn token_words(value: &str) -> Vec<String> {
    value
        .split(|ch: char| !(ch.is_alphanumeric() || ch == '-'))
        .filter(|part| !part.trim().is_empty())
        .map(str::to_owned)
        .collect()
}

fn file_stem(name: &str) -> String {
    Path::new(name)
        .file_stem()
        .map(|stem| stem.to_string_lossy().into_owned())
        .unwrap_or_else(|| name.to_owned())
}

fn slug_from_text(value: &str) -> Option<String> {
    let mut slug = String::new();
    let mut last_was_separator = false;
    for ch in value.trim().chars() {
        if ch.is_alphanumeric() {
            for lower in ch.to_lowercase() {
                slug.push(lower);
            }
            last_was_separator = false;
        } else if !last_was_separator {
            slug.push('-');
            last_was_separator = true;
        }
    }
    let slug = slug.trim_matches('-').to_owned();
    let len = slug.chars().count();
    if !(MIN_SUGGESTION_LEN..=super::MAX_TAG_LEN).contains(&len) {
        return None;
    }
    slug.chars().any(char::is_alphabetic).then_some(slug)
}

fn display_name(item: &ApplyTagSuggestionItem) -> String {
    let trimmed = item.display_name.trim();
    if trimmed.is_empty() {
        item.slug.trim().to_owned()
    } else {
        trimmed.to_owned()
    }
}

#[derive(Clone)]
struct SuggestionSeed {
    slug: String,
    source: TagSuggestionSource,
    reason: String,
}

struct SuggestionBuilder {
    registry: TagRegistry,
    seen: HashSet<String>,
    suggestions: Vec<TagSuggestion>,
}

impl SuggestionBuilder {
    fn new(registry: TagRegistry) -> Self {
        Self {
            registry,
            seen: HashSet::new(),
            suggestions: Vec::new(),
        }
    }

    fn len(&self) -> usize {
        self.suggestions.len()
    }

    fn push_seed(&mut self, seed: SuggestionSeed) {
        let Some(tag) = self.registry.existing_value(&seed.slug) else {
            self.push(
                seed.slug,
                seed.source,
                TagSuggestionMatch::Weak,
                seed.reason,
            );
            return;
        };
        self.push(tag, seed.source, TagSuggestionMatch::Strong, seed.reason);
    }

    fn push_existing_patterns(&mut self, snapshot: &db::TagSuggestionSnapshot) {
        let haystack = suggestion_haystack(snapshot);
        for tag in self.registry.existing_values() {
            let Some(comparable) = slug_from_text(&tag) else {
                continue;
            };
            if haystack.contains(&comparable) {
                self.push(
                    tag,
                    TagSuggestionSource::ExistingTagPattern,
                    TagSuggestionMatch::Weak,
                    format!("Matched existing tag pattern: {comparable}"),
                );
            }
        }
    }

    fn push(
        &mut self,
        slug: String,
        source: TagSuggestionSource,
        match_strength: TagSuggestionMatch,
        reason: String,
    ) {
        let comparable = comparable_tag(&slug);
        if !self.seen.insert(comparable.clone()) {
            return;
        }
        let already_added = self.registry.file_has(&slug);
        let already_exists = self.registry.exists(&slug);
        let status = if already_added {
            TagSuggestionStatus::AlreadyAdded
        } else {
            TagSuggestionStatus::NewTag
        };
        self.suggestions.push(TagSuggestion {
            suggestion_id: format!("suggestion:{}:{comparable}", source_key(&source)),
            slug: slug.clone(),
            display_name: slug,
            reason,
            source,
            selected_by_default: match_strength == TagSuggestionMatch::Strong && !already_added,
            match_strength,
            already_exists,
            needs_create: !already_exists,
            status,
            disabled_reason: already_added.then(|| "Already added".to_owned()),
        });
    }

    fn into_suggestions(self) -> Vec<TagSuggestion> {
        self.suggestions
    }

    fn into_suggestions_limited(mut self, limit: usize) -> Vec<TagSuggestion> {
        self.suggestions.truncate(limit);
        self.suggestions
    }
}

struct TagRegistry {
    available: Vec<String>,
    available_comparable: HashSet<String>,
    selected_comparable: HashSet<String>,
}

impl TagRegistry {
    fn new(snapshot: &db::TagSuggestionSnapshot) -> Self {
        let available = snapshot
            .tag_set
            .available_tags
            .iter()
            .map(|record| record.value.clone())
            .collect::<Vec<_>>();
        let available_comparable = available.iter().map(|tag| comparable_tag(tag)).collect();
        let selected_comparable = snapshot
            .tag_set
            .file_tags
            .iter()
            .map(|record| comparable_tag(&record.value))
            .collect();
        Self {
            available,
            available_comparable,
            selected_comparable,
        }
    }

    fn existing_values(&self) -> Vec<String> {
        self.available.clone()
    }

    fn existing_value(&self, slug: &str) -> Option<String> {
        let comparable = comparable_tag(slug);
        self.available
            .iter()
            .find(|tag| comparable_tag(tag) == comparable)
            .cloned()
    }

    fn exists(&self, slug: &str) -> bool {
        self.available_comparable.contains(&comparable_tag(slug))
    }

    fn file_has(&self, slug: &str) -> bool {
        self.selected_comparable.contains(&comparable_tag(slug))
    }
}

fn comparable_tag(value: &str) -> String {
    slug_from_text(value).unwrap_or_else(|| value.trim().to_lowercase())
}

fn suggestion_haystack(snapshot: &db::TagSuggestionSnapshot) -> String {
    [
        file_stem(&snapshot.file.current_name),
        snapshot.file.path.clone(),
        snapshot.file.source_path.clone().unwrap_or_default(),
    ]
    .iter()
    .filter_map(|value| slug_from_text(value))
    .collect::<Vec<_>>()
    .join("-")
}

fn source_key(source: &TagSuggestionSource) -> &'static str {
    match source {
        TagSuggestionSource::FileName => "file-name",
        TagSuggestionSource::Path => "path",
        TagSuggestionSource::SourceFolder => "source-folder",
        TagSuggestionSource::ExistingTagPattern => "existing-tag-pattern",
    }
}
