//! AreaMatrix platform-neutral core library.

// UniFFI 0.28 generated scaffolding currently trips this lint.
#![allow(clippy::empty_line_after_doc_comments)]

uniffi::include_scaffolding!("area_matrix");

mod ai_call_log;
mod ai_classification_suggestion;
mod ai_settings;
pub mod api;
mod batch_category;
mod batch_delete;
mod batch_rename;
mod classifier_correction;
mod classifier_impact;
mod classifier_rule_editor;
mod classifier_rules;
pub mod classify;
mod command_index;
pub mod config;
pub mod db;
pub mod domain;
pub mod error;
mod icloud_conflicts;
mod import_conflict_batch;
mod local_model_status;
mod note;
pub mod overview;
mod recovery;
mod redo;
mod remote_provider_config;
mod repair;
mod repo_entries;
mod repo_init;
mod repo_path;
mod repo_scan;
pub mod search;
pub mod storage;
pub mod sync;
mod tags;
pub mod tree;
pub mod undo;

pub use ai_call_log::{
    AiCallLogClearReport, AiCallLogClearRequest, AiCallLogClearScope, AiCallLogFeature,
    AiCallLogFilter, AiCallLogPage, AiCallLogPagination, AiCallLogRecord, AiCallLogRoute,
    AiCallLogSentField, AiCallLogStatus,
};
pub use ai_classification_suggestion::{
    AiCategorySuggestion, AiCategorySuggestionContextField, AiCategorySuggestionContextPolicy,
    AiCategorySuggestionRequest, AiCategorySuggestionRoute, AiCategorySuggestionSkipReason,
    AiCategorySuggestionStatus,
};
pub use ai_settings::{
    AiCapabilityState, AiConfig, AiConfigSnapshot, AiFeatureConfig, AiFeatureKind,
    AiProviderPreference,
};
pub use api::*;
pub use batch_category::{
    batch_move_to_category, preview_batch_move_to_category, BatchCategoryChangeItemResult,
    BatchCategoryChangeReport, BatchCategoryPreviewItem, BatchCategoryPreviewReport,
    BatchCategoryPreviewStatus, BatchCategoryResultStatus, CategoryDistributionItem,
};
pub use batch_delete::{
    batch_delete_to_trash, preview_batch_delete, BatchDeleteItemResult, BatchDeleteMode,
    BatchDeletePreviewItem, BatchDeletePreviewReport, BatchDeletePreviewStatus, BatchDeleteReport,
    BatchDeleteResultStatus,
};
pub use batch_rename::{
    batch_rename, preview_batch_rename, BatchRenameConflict, BatchRenameDateSource,
    BatchRenameItemResult, BatchRenameMode, BatchRenamePreviewItem, BatchRenamePreviewReport,
    BatchRenamePreviewStatus, BatchRenameReport, BatchRenameResultStatus, BatchRenameRule,
};
pub use classifier_correction::{
    correct_file_category, ClassifierCorrectionResult, ClassifierRuleDraft,
};
pub use classifier_impact::{
    preview_classifier_rule_impact, ClassifierImpactPreviewMode, ClassifierImpactPreviewRequest,
    RuleImpactConflict, RuleImpactConflictKind, RuleImpactMatchReason, RuleImpactReport,
    RuleImpactSample, RuleImpactStatus,
};
pub use classifier_rule_editor::{
    create_classifier_rule, delete_classifier_rule, list_classifier_rules, update_classifier_rule,
    ClassifierRuleCreateRequest, ClassifierRuleDeleteRequest, ClassifierRuleEditorSnapshot,
    ClassifierRuleRecord, ClassifierRuleUpdate,
};
pub use classifier_rules::{save_classifier_rule, ClassifierRule};
pub use command_index::{
    list_command_targets, CommandIndex, CommandIndexContext, CommandTarget, CommandTargetAction,
    CommandTargetGroup, CommandTargetKind,
};
pub use domain::*;
pub use error::{
    map_core_error, CoreError, CoreResult, ErrorKind, ErrorMapping, ErrorMappingInput,
    ErrorRecoverability, ErrorSeverity,
};
pub use import_conflict_batch::{
    apply_import_conflict_batch, preview_import_conflict_batch, ImportConflictBatchApplyReport,
    ImportConflictBatchApplyRequest, ImportConflictBatchConflictType,
    ImportConflictBatchItemResult, ImportConflictBatchPreviewItem,
    ImportConflictBatchPreviewReport, ImportConflictBatchPreviewRequest,
    ImportConflictBatchPreviewStatus, ImportConflictBatchResultStatus, ImportConflictBatchStrategy,
};
pub use local_model_status::{
    LocalModelAvailability, LocalModelCachedStatus, LocalModelFeatureStatus,
    LocalModelFolderLocation, LocalModelFolderRequest, LocalModelRecommendedAction,
    LocalModelStatusRequest, LocalModelStatusSnapshot,
};
pub use redo::{
    list_redo_actions, redo_action, RedoActionRecord, RedoActionResult, RedoActionStatus,
};
pub use remote_provider_config::{
    RemoteAiProviderKind, RemoteProviderConfigSnapshot, RemoteProviderDisableRequest,
    RemoteProviderEnableRequest, RemoteProviderTestRequest, RemoteProviderTestResult,
    RemoteProviderTestStatus,
};
pub use search::*;
pub use tags::{
    add_tag, apply_tag_suggestions, batch_add_tags, list_tags, remove_tag, suggest_tags_for_file,
    ApplyTagSuggestionItem, ApplyTagSuggestionsRequest, BatchMutationItemResult,
    BatchMutationReport, BatchMutationStatus, TagRecord, TagSet, TagSuggestion,
    TagSuggestionApplyItemResult, TagSuggestionApplyReport, TagSuggestionApplyStatus,
    TagSuggestionContext, TagSuggestionMatch, TagSuggestionReport, TagSuggestionRequest,
    TagSuggestionSource, TagSuggestionStatus,
};
pub use undo::{
    list_undo_actions, undo_action, UndoActionRecord, UndoActionResult, UndoActionStatus,
};
