use std::{
    collections::HashSet,
    fs::File,
    io::{ErrorKind, Read},
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use crate::{CoreError, CoreResult, FileEntry, StorageMode};

use super::super::{
    privacy::PrivacyInput, SemanticIndexStatus, SemanticSearchInputField, SemanticSearchRoute,
};

const MAX_CONTENT_READ_BYTES: u64 = 64 * 1024;
const MAX_EXCERPT_CHARS: usize = 512;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(in crate::semantic_search) struct StoredSemanticIndex {
    pub(in crate::semantic_search) status: SemanticIndexStatus,
    pub(in crate::semantic_search) route: SemanticSearchRoute,
    pub(in crate::semantic_search) total_count: i64,
    pub(in crate::semantic_search) processed_count: i64,
    pub(in crate::semantic_search) skipped_count: i64,
    pub(in crate::semantic_search) failed_count: i64,
    pub(in crate::semantic_search) privacy_skipped_count: i64,
    #[serde(default)]
    pub(in crate::semantic_search) privacy_rule_id: Option<String>,
    pub(in crate::semantic_search) updated_at: i64,
}

#[derive(Clone, Debug)]
pub(in crate::semantic_search) struct SemanticIndexedFile {
    pub(in crate::semantic_search) entry: FileEntry,
    pub(in crate::semantic_search) field_terms: Vec<SemanticFieldTerms>,
    pub(in crate::semantic_search) matched_fields: Vec<SemanticFieldMatch>,
    pub(in crate::semantic_search) matched_token_count: usize,
    pub(in crate::semantic_search) query_token_count: usize,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub(in crate::semantic_search) struct SemanticFieldTerms {
    pub(in crate::semantic_search) field: SemanticSearchInputField,
    pub(in crate::semantic_search) source: String,
    pub(in crate::semantic_search) terms: Vec<String>,
}

#[derive(Clone, Debug)]
pub(in crate::semantic_search) struct SemanticFieldMatch {
    pub(in crate::semantic_search) field: SemanticSearchInputField,
    pub(in crate::semantic_search) source: String,
    pub(in crate::semantic_search) matched_terms: Vec<String>,
}

#[derive(Clone, Debug)]
pub(in crate::semantic_search) struct SemanticIndexBuildOutcome {
    pub(in crate::semantic_search) metadata: StoredSemanticIndex,
    pub(in crate::semantic_search) privacy_rule_id: Option<String>,
}

#[derive(Clone, Debug)]
pub(super) struct Candidate {
    pub(super) entry: FileEntry,
    pub(super) note: String,
    pub(super) tags: Vec<String>,
    pub(super) field_terms: Vec<SemanticFieldTerms>,
}

pub(super) struct IndexStats {
    pub(super) metadata: StoredSemanticIndex,
    pub(super) processed: i64,
    pub(super) skipped: i64,
    pub(super) privacy_skipped: i64,
}

impl Candidate {
    pub(super) fn field_terms(&self, repo: &Path) -> Vec<SemanticFieldTerms> {
        if !self.field_terms.is_empty() {
            return self.field_terms.clone();
        }
        let mut fields = self.metadata_field_terms();
        if let Some(content) = readable_file_excerpt(repo, &self.entry) {
            super::push_field_terms(
                &mut fields,
                SemanticSearchInputField::ExtractedTextExcerpt,
                content,
            );
        }
        fields
    }

    pub(super) fn metadata_field_terms(&self) -> Vec<SemanticFieldTerms> {
        let mut fields = Vec::new();
        super::push_field_terms(
            &mut fields,
            SemanticSearchInputField::FileName,
            self.entry.current_name.clone(),
        );
        super::push_field_terms(
            &mut fields,
            SemanticSearchInputField::RepoRelativePath,
            self.entry.path.clone(),
        );
        super::push_field_terms(
            &mut fields,
            SemanticSearchInputField::Category,
            self.entry.category.clone(),
        );
        super::push_field_terms(
            &mut fields,
            SemanticSearchInputField::NoteSummary,
            self.note.clone(),
        );
        fields
    }

    pub(super) fn field_terms_without_reading(&self) -> Vec<SemanticFieldTerms> {
        if self.field_terms.is_empty() {
            self.metadata_field_terms()
        } else {
            self.field_terms.clone()
        }
    }

    pub(super) fn privacy_input<'a>(
        &'a self,
        route: &'a SemanticSearchRoute,
        searchable_texts: &'a [&'a str],
    ) -> PrivacyInput<'a> {
        PrivacyInput {
            route,
            path: &self.entry.path,
            name: &self.entry.current_name,
            category: &self.entry.category,
            extension: extension(&self.entry.current_name),
            tags: &self.tags,
            searchable_texts,
        }
    }

    pub(super) fn match_query(&self, query_tokens: &[String]) -> Option<SemanticIndexedFile> {
        let field_terms = self.field_terms_without_reading();
        let matched_fields = field_terms
            .iter()
            .filter_map(|field| field.match_query(query_tokens))
            .collect::<Vec<_>>();
        if matched_fields.is_empty() {
            return None;
        }
        let matched_token_count = matched_token_count(&matched_fields);
        Some(SemanticIndexedFile {
            entry: self.entry.clone(),
            field_terms,
            matched_fields,
            matched_token_count,
            query_token_count: query_tokens.len(),
        })
    }
}

impl SemanticFieldTerms {
    fn match_query(&self, query_tokens: &[String]) -> Option<SemanticFieldMatch> {
        let matched_terms = query_tokens
            .iter()
            .filter(|token| self.terms.iter().any(|term| term.contains(*token)))
            .cloned()
            .collect::<Vec<_>>();
        if matched_terms.is_empty() {
            return None;
        }
        Some(SemanticFieldMatch {
            field: self.field.clone(),
            source: self.source.clone(),
            matched_terms,
        })
    }
}

impl IndexStats {
    pub(super) fn new(route: SemanticSearchRoute, total_count: usize, updated_at: i64) -> Self {
        Self {
            metadata: StoredSemanticIndex {
                status: SemanticIndexStatus::Building,
                route,
                total_count: i64::try_from(total_count).unwrap_or(i64::MAX),
                processed_count: 0,
                skipped_count: 0,
                failed_count: 0,
                privacy_skipped_count: 0,
                privacy_rule_id: None,
                updated_at,
            },
            processed: 0,
            skipped: 0,
            privacy_skipped: 0,
        }
    }

    pub(super) fn finish(&mut self, privacy_rule_set_empty: bool) {
        self.metadata.processed_count = self.processed;
        self.metadata.privacy_skipped_count = self.privacy_skipped;
        self.metadata.skipped_count = self.skipped + self.privacy_skipped;
        self.metadata.status = if self.processed == self.metadata.total_count {
            SemanticIndexStatus::Ready
        } else if self.processed > 0 {
            SemanticIndexStatus::Partial
        } else if self.privacy_skipped > 0 && !privacy_rule_set_empty {
            SemanticIndexStatus::NotReady
        } else {
            SemanticIndexStatus::NotReady
        };
    }
}

pub(super) fn excerpt(value: &str) -> String {
    value.chars().take(MAX_EXCERPT_CHARS).collect()
}

fn matched_token_count(matches: &[SemanticFieldMatch]) -> usize {
    matches
        .iter()
        .flat_map(|field| field.matched_terms.iter().map(String::as_str))
        .collect::<HashSet<_>>()
        .len()
}

fn readable_file_excerpt(repo: &Path, entry: &FileEntry) -> Option<String> {
    read_limited_utf8(&entry_path(repo, entry))
        .ok()
        .filter(|text| !text.trim().is_empty())
}

fn read_limited_utf8(path: &Path) -> CoreResult<String> {
    let file = File::open(path).map_err(|error| map_content_read_error(path, error.kind()))?;
    let mut bytes = Vec::new();
    file.take(MAX_CONTENT_READ_BYTES)
        .read_to_end(&mut bytes)
        .map_err(|error| map_content_read_error(path, error.kind()))?;
    String::from_utf8(bytes)
        .map(|value| excerpt(&value))
        .map_err(|_| CoreError::db("semantic input is not utf-8"))
}

fn entry_path(repo: &Path, entry: &FileEntry) -> PathBuf {
    if matches!(entry.storage_mode, StorageMode::Indexed) {
        if let Some(source_path) = entry.source_path.as_deref() {
            return PathBuf::from(source_path);
        }
    }
    repo.join(&entry.path)
}

fn map_content_read_error(path: &Path, kind: ErrorKind) -> CoreError {
    match kind {
        ErrorKind::NotFound => CoreError::file_not_found(path.to_string_lossy()),
        ErrorKind::PermissionDenied => CoreError::permission_denied(path.to_string_lossy()),
        _ => CoreError::db("semantic input cannot be read"),
    }
}

fn extension(name: &str) -> Option<&str> {
    Path::new(name).extension().and_then(|value| value.to_str())
}
