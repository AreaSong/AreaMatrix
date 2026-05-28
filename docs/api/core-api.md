# Core API（UDL 接口规范）

> AreaMatrix Core 暴露给 Swift / Kotlin / Python 的所有函数与类型，权威定义。任何对外接口变化必须先改本文档与 `area_matrix.udl`。
>
> 阅读时长：约 16 分钟。

---

## 接口稳定性约定

| Stage | 状态 | 含义 |
|---|---|---|
| 1 (MVP) | unstable | 每个版本可能调整，使用方自担风险 |
| 2 起 | stable | 破坏性变化只在 MAJOR 版本发生 |
| 弃用流程 | — | 标记 `[Deprecated]` 至少保留一个 MINOR 版本 |

详见 [../architecture/ffi-design.md](../architecture/ffi-design.md)。

---

## 完整 UDL 文件

```idl
// core/src/area_matrix.udl
namespace area_matrix {
    string get_version();

    [Throws=CoreError]
    void init_logging(string level);

    [Throws=CoreError]
    RepoPathValidation validate_repo_path(string repo_path);

    [Throws=CoreError]
    RepoPathValidation validate_initialized_repo_path(string repo_path);

    [Throws=CoreError]
    void init_repo(string repo_path, RepoInitOptions options);

    [Throws=CoreError]
    RepoConfig load_config(string repo_path);

    [Throws=CoreError]
    void update_config(string repo_path, RepoConfig new_config);

    [Throws=CoreError]
    AiConfigSnapshot load_ai_config(string repo_path);

    [Throws=CoreError]
    AiConfigSnapshot update_ai_config(string repo_path, AiConfig new_config);

    [Throws=CoreError]
    LocalModelStatusSnapshot get_local_model_status(
        string repo_path, LocalModelStatusRequest request
    );

    [Throws=CoreError]
    LocalModelFolderLocation locate_local_model_folder(
        string repo_path, LocalModelFolderRequest request
    );

    [Throws=CoreError]
    RemoteProviderTestResult test_remote_ai_provider(
        string repo_path, RemoteProviderTestRequest request
    );

    [Throws=CoreError]
    RemoteProviderConfigSnapshot load_remote_ai_provider_config(string repo_path);

    [Throws=CoreError]
    RemoteProviderConfigSnapshot enable_remote_ai_provider(
        string repo_path, RemoteProviderEnableRequest request
    );

    [Throws=CoreError]
    RemoteProviderConfigSnapshot disable_remote_ai_provider(
        string repo_path, RemoteProviderDisableRequest request
    );

    [Throws=CoreError]
    AiCategorySuggestion suggest_category_with_ai(
        string repo_path, AiCategorySuggestionRequest request
    );

    [Throws=CoreError]
    AiCallLogPage list_ai_calls(
        string repo_path, AiCallLogFilter filter, AiCallLogPagination pagination
    );

    [Throws=CoreError]
    AiCallLogClearReport clear_ai_call_log(
        string repo_path, AiCallLogClearRequest request
    );

    [Throws=CoreError]
    AiSummaryDraft generate_ai_summary(
        string repo_path, AiSummaryGenerationRequest request
    );

    [Throws=CoreError]
    AiSummarySaveReport save_ai_summary(
        string repo_path, AiSummarySaveRequest request
    );

    [Throws=CoreError]
    AiSummaryClearReport clear_ai_summary(
        string repo_path, AiSummaryClearRequest request
    );

    [Throws=CoreError]
    RecoveryReport recover_on_startup(string repo_path);

    [Throws=CoreError]
    ReindexReport reindex_from_filesystem(string repo_path);

    [Throws=CoreError]
    DiagnosticsSnapshot create_diagnostics_snapshot(string repo_path);

    [Throws=CoreError]
    RepairReport repair_metadata(string repo_path, RepairOptions options);

    [Throws=CoreError]
    ScanSession? get_latest_scan_session(string repo_path);

    [Throws=CoreError]
    ReindexReport resume_scan_session(string repo_path, i64 scan_session_id);

    [Throws=CoreError]
    ClassifyResult predict_category(string repo_path, string filename);

    [Throws=CoreError]
    FileEntry import_file(
        string repo_path, string source_path, ImportOptions options
    );

    [Throws=CoreError]
    void delete_file(string repo_path, i64 file_id);

    [Throws=CoreError]
    void remove_index_entry(string repo_path, i64 file_id);

    [Throws=CoreError]
    FileEntry rename_file(string repo_path, i64 file_id, string new_name);

    [Throws=CoreError]
    MoveToCategoryPreview preview_move_to_category(
        string repo_path, i64 file_id, string new_category
    );

    [Throws=CoreError]
    FileEntry move_to_category(string repo_path, i64 file_id, string new_category);

    [Throws=CoreError]
    BatchCategoryPreviewReport preview_batch_move_to_category(
        string repo_path,
        sequence<i64> file_ids,
        string target_category,
        boolean move_repo_owned_files
    );

    [Throws=CoreError]
    BatchCategoryChangeReport batch_move_to_category(
        string repo_path,
        sequence<i64> file_ids,
        string target_category,
        boolean move_repo_owned_files,
        string preview_token
    );

    [Throws=CoreError]
    BatchDeletePreviewReport preview_batch_delete(
        string repo_path,
        sequence<i64> file_ids,
        BatchDeleteMode delete_mode
    );

    [Throws=CoreError]
    BatchDeleteReport batch_delete_to_trash(
        string repo_path,
        sequence<i64> file_ids,
        BatchDeleteMode delete_mode,
        string preview_token
    );

    [Throws=CoreError]
    BatchRenamePreviewReport preview_batch_rename(
        string repo_path,
        sequence<i64> file_ids,
        BatchRenameRule rule
    );

    [Throws=CoreError]
    BatchRenameReport batch_rename(
        string repo_path,
        sequence<i64> file_ids,
        BatchRenameRule rule,
        string preview_token
    );

    [Throws=CoreError]
    ClassifierCorrectionResult correct_file_category(
        string repo_path,
        i64 file_id,
        string category,
        boolean move_file,
        boolean remember
    );

    [Throws=CoreError]
    ClassifierRule save_classifier_rule(string repo_path, ClassifierRule rule);

    [Throws=CoreError]
    RuleImpactReport preview_classifier_rule_impact(
        string repo_path,
        ClassifierImpactPreviewRequest request
    );

    [Throws=CoreError]
    ClassifierRuleEditorSnapshot list_classifier_rules(string repo_path);

    [Throws=CoreError]
    ClassifierRuleEditorSnapshot create_classifier_rule(
        string repo_path,
        ClassifierRuleCreateRequest request
    );

    [Throws=CoreError]
    ClassifierRuleEditorSnapshot update_classifier_rule(
        string repo_path,
        ClassifierRuleUpdate request
    );

    [Throws=CoreError]
    ClassifierRuleEditorSnapshot delete_classifier_rule(
        string repo_path,
        ClassifierRuleDeleteRequest request
    );

    [Throws=CoreError]
    FileEntry restore_file(string repo_path, i64 file_id);

    [Throws=CoreError]
    sequence<FileEntry> list_files(string repo_path, FileFilter filter);

    [Throws=CoreError]
    SearchResultPage search_files(
        string repo_path,
        string query,
        SearchFilter filter,
        SearchSort sort,
        SearchPagination pagination
    );

    [Throws=CoreError]
    SearchFacets list_filter_facets(string repo_path, SearchFacetQuery query);

    [Throws=CoreError]
    SavedSearch create_saved_search(string repo_path, CreateSavedSearchRequest request);

    [Throws=CoreError]
    SavedSearch update_saved_search(string repo_path, UpdateSavedSearchRequest request);

    [Throws=CoreError]
    void delete_saved_search(string repo_path, i64 saved_search_id);

    [Throws=CoreError]
    sequence<SavedSearch> list_saved_searches(string repo_path);

    [Throws=CoreError]
    SearchResultPage run_smart_list(
        string repo_path,
        i64 saved_search_id,
        SearchPagination pagination
    );

    [Throws=CoreError]
    CommandIndex list_command_targets(string repo_path, CommandIndexContext context);

    [Throws=CoreError]
    TagSet add_tag(string repo_path, i64 file_id, string tag);

    [Throws=CoreError]
    TagSet remove_tag(string repo_path, i64 file_id, string tag);

    [Throws=CoreError]
    TagSet list_tags(string repo_path, i64 file_id);

    [Throws=CoreError]
    BatchMutationReport batch_add_tags(
        string repo_path, sequence<i64> file_ids, sequence<string> tags
    );

    [Throws=CoreError]
    TagSuggestionReport suggest_tags_for_file(
        string repo_path, TagSuggestionRequest request
    );

    [Throws=CoreError]
    TagSuggestionApplyReport apply_tag_suggestions(
        string repo_path, ApplyTagSuggestionsRequest request
    );

    [Throws=CoreError]
    sequence<UndoActionRecord> list_undo_actions(string repo_path);

    [Throws=CoreError]
    UndoActionResult undo_action(string repo_path, string action_id);

    [Throws=CoreError]
    sequence<RedoActionRecord> list_redo_actions(string repo_path);

    [Throws=CoreError]
    RedoActionResult redo_action(string repo_path, string action_id);

    [Throws=CoreError]
    FileEntry get_file(string repo_path, i64 file_id);

    [Throws=CoreError]
    sequence<ChangeLogEntry> list_changes(string repo_path, ChangeFilter filter);

    [Throws=CoreError]
    string list_tree_json(string repo_path, string locale);

    [Throws=CoreError]
    sequence<ICloudConflictPair> list_icloud_conflicts(string repo_path);

    [Throws=CoreError]
    ICloudConflictPreviewReport preview_conflict_versions(
        string repo_path, string conflict_id
    );

    [Throws=CoreError]
    ICloudConflictResolveReport resolve_icloud_conflict(
        string repo_path,
        string conflict_id,
        ICloudConflictResolution resolution
    );

    [Throws=CoreError]
    ImportConflictBatchPreviewReport preview_import_conflict_batch(
        string repo_path,
        ImportConflictBatchPreviewRequest request
    );

    [Throws=CoreError]
    ImportConflictBatchApplyReport apply_import_conflict_batch(
        string repo_path,
        ImportConflictBatchApplyRequest request,
        string preview_token
    );

    [Throws=CoreError]
    string? read_note(string repo_path, i64 file_id);

    [Throws=CoreError]
    void write_note(string repo_path, i64 file_id, string content_md);

    [Throws=CoreError]
    SyncResult sync_external_changes(string repo_path, sequence<ExternalEvent> events);

    [Throws=CoreError]
    i64? get_fs_event_cursor(string repo_path);

    [Throws=CoreError]
    void set_fs_event_cursor(string repo_path, i64 last_event_id);

    ErrorMapping map_core_error(ErrorMappingInput input);
};

dictionary RepoConfig {
    string repo_path;
    StorageMode default_mode;
    OverviewOutput overview_output;
    boolean ai_enabled;
    string locale;
    boolean icloud_warn;
    boolean enable_extension_rules;
    boolean enable_keyword_rules;
    boolean fallback_to_inbox;
    boolean allow_replace_during_import;
};

dictionary AiFeatureConfig {
    AiFeatureKind feature;
    boolean enabled;
    boolean allow_remote;
};

dictionary AiConfig {
    string repo_path;
    boolean ai_enabled;
    AiProviderPreference provider_preference;
    boolean local_ai_enabled;
    boolean remote_ai_allowed;
    boolean privacy_gate_enabled;
    string? privacy_policy_ref;
    sequence<AiFeatureConfig> feature_toggles;
};

dictionary AiCapabilityState {
    AiFeatureKind feature;
    boolean enabled;
    boolean local_allowed;
    boolean remote_allowed;
    string? disabled_reason;
};

dictionary AiConfigSnapshot {
    AiConfig config;
    sequence<AiCapabilityState> capabilities;
    i64? updated_at;
};

dictionary LocalModelFeatureStatus {
    AiFeatureKind feature;
    boolean available;
    string? unavailable_reason;
};

dictionary LocalModelCachedStatus {
    string model_id;
    string storage_location;
    LocalModelAvailability availability;
    string? version;
    i64? size_bytes;
    string? last_error;
    LocalModelRecommendedAction recommended_action;
    i64? last_checked_at;
    string diagnostics_summary;
};

dictionary LocalModelStatusRequest {
    string model_id;
    string storage_location;
    LocalModelCachedStatus? cached_status;
};

dictionary LocalModelStatusSnapshot {
    string model_id;
    string storage_location;
    LocalModelAvailability availability;
    string? version;
    i64? size_bytes;
    string? last_error;
    LocalModelRecommendedAction recommended_action;
    i64? last_checked_at;
    string diagnostics_summary;
    sequence<LocalModelFeatureStatus> feature_statuses;
};

dictionary LocalModelFolderRequest {
    string model_id;
    string storage_location;
};

dictionary LocalModelFolderLocation {
    string model_id;
    string folder_path;
    boolean exists;
    boolean readable;
    boolean openable;
    string? unavailable_reason;
};

dictionary RemoteProviderTestRequest {
    RemoteAiProviderKind provider;
    string model_id;
    string? endpoint_url;
    string key_reference;
};

dictionary RemoteProviderEnableRequest {
    RemoteAiProviderKind provider;
    string model_id;
    string? endpoint_url;
    string key_reference;
    sequence<AiFeatureKind> feature_scope;
    string verification_token;
    boolean data_flow_confirmed;
};

dictionary RemoteProviderDisableRequest {
    boolean remove_stored_credential;
};

dictionary RemoteProviderConfigSnapshot {
    boolean provider_configured;
    boolean provider_verified;
    boolean remote_provider_enabled;
    RemoteAiProviderKind? provider;
    string? model_id;
    string? endpoint_url;
    boolean credential_configured;
    sequence<AiFeatureKind> feature_scope;
    i64? updated_at;
    string? disabled_reason;
};

dictionary RemoteProviderTestResult {
    RemoteAiProviderKind provider;
    string model_id;
    string? endpoint_url;
    RemoteProviderTestStatus status;
    boolean provider_verified;
    string? verification_token;
    string sanitized_message;
};

dictionary AiCategorySuggestionRequest {
    i64 file_id;
    AiCategorySuggestionContextPolicy context_policy;
    string? privacy_policy_ref;
};

dictionary AiCategorySuggestion {
    i64 file_id;
    AiCategorySuggestionStatus status;
    string? current_category;
    string? suggested_category;
    f32 confidence;
    string? reason;
    AiCategorySuggestionRoute? route;
    sequence<AiCategorySuggestionContextField> used_context;
    AiCategorySuggestionSkipReason? skipped_reason;
    string? privacy_rule_id;
    i64? call_log_id;
    boolean requires_user_confirmation;
};

dictionary AiSummaryGenerationRequest {
    i64 file_id;
    AiSummaryProviderScope provider_scope;
    AiSummaryContextPolicy context_policy;
    string? privacy_policy_ref;
    boolean regenerate_existing;
};

dictionary AiSummaryDraft {
    i64 file_id;
    string? draft_id;
    AiSummaryDraftStatus status;
    string? summary_text;
    AiSummaryRoute? route;
    string? model_name;
    i64? generated_at;
    sequence<AiSummaryInputField> used_context;
    AiSummarySkipReason? skipped_reason;
    string? privacy_rule_id;
    i64? call_log_id;
    boolean requires_user_save;
    i64 character_count;
};

dictionary AiSummarySaveRequest {
    i64 file_id;
    string summary_text;
    string? draft_id;
    AiSummaryRoute? route;
    string? model_name;
    i64? generated_at;
    sequence<AiSummaryInputField> used_context;
    string? privacy_rule_id;
    i64? call_log_id;
    boolean edited_by_user;
};

dictionary AiSummarySaveReport {
    i64 file_id;
    string saved_summary;
    i64 saved_at;
    AiSummaryRoute? route;
    string? model_name;
    i64? generated_at;
    sequence<AiSummaryInputField> used_context;
    string? privacy_rule_id;
    i64? call_log_id;
    boolean edited_by_user;
    i64 character_count;
};

dictionary AiSummaryClearRequest {
    i64 file_id;
    boolean confirmed;
};

dictionary AiSummaryClearReport {
    i64 file_id;
    boolean cleared;
    i64 cleared_at;
};

dictionary AiCallLogFilter {
    AiCallLogFeature? feature;
    AiCallLogRoute? route;
    AiCallLogStatus? status;
    i64? occurred_after;
    i64? occurred_before;
    string? search_query;
};

dictionary AiCallLogPagination {
    i64 limit;
    i64 offset;
};

dictionary AiCallLogRecord {
    i64 id;
    i64 occurred_at;
    AiCallLogFeature feature;
    i64? file_id;
    string? file_display_name;
    string? batch_id;
    string? scope;
    AiCallLogRoute? route;
    string? provider_name;
    string? model_name;
    AiCallLogStatus status;
    i64? duration_ms;
    sequence<AiCallLogSentField> sent_fields;
    boolean privacy_rules_checked;
    string? privacy_rule_id;
    string? privacy_rule_name;
    AiCallLogSentField? matched_field_type;
    string result_summary;
    string? error_code;
};

dictionary AiCallLogPage {
    i64 total_count;
    sequence<AiCallLogRecord> records;
    i64 limit;
    i64 offset;
    boolean has_more;
    i64 retention_days;
    string redaction_policy;
};

dictionary AiCallLogClearRequest {
    AiCallLogClearScope scope;
    sequence<i64> entry_ids;
    i64? older_than;
};

dictionary AiCallLogClearReport {
    i64 deleted_count;
    i64 remaining_count;
    i64 cleared_at;
};

dictionary RepoInitOptions {
    RepoInitMode mode;
    boolean create_default_categories;
    OverviewOutput overview_output;
};

dictionary RepoPathValidation {
    string repo_path;
    boolean exists;
    boolean is_directory;
    boolean is_readable;
    boolean is_writable;
    boolean is_empty;
    boolean is_initialized;
    boolean is_inside_area_matrix;
    boolean is_icloud_path;
    boolean has_unfinished_scan_session;
    RepoInitMode? recommended_mode;
    sequence<RepoPathIssue> issues;
};

dictionary ImportOptions {
    StorageMode mode;
    ImportDestination destination;
    string? target_directory;
    string? override_category;
    string? override_filename;
    DuplicateStrategy duplicate_strategy;
};

dictionary FileFilter {
    string? category;
    boolean? include_deleted;
    i64? imported_after;
    i64? imported_before;
    i64 limit;
    i64 offset;
};

dictionary SearchFilter {
    SearchScope scope;
    string? current_path;
    string? category;
    string? file_kind;
    sequence<string> tags;
    SearchTagMatchMode tag_match_mode;
    i64? imported_after;
    i64? imported_before;
    i64? modified_after;
    i64? modified_before;
    StorageMode? storage_mode;
    boolean? include_deleted;
};

dictionary SearchFacetQuery {
    string query;
    SearchScope scope;
    string? current_path;
    string? category;
    string? file_kind;
    sequence<string> tags;
    SearchTagMatchMode tag_match_mode;
    i64? imported_after;
    i64? imported_before;
    i64? modified_after;
    i64? modified_before;
    StorageMode? storage_mode;
    boolean? include_deleted;
};

dictionary SearchFacetCount {
    string value;
    string label;
    i64 count;
    boolean selected;
    boolean disabled;
};

dictionary SearchStorageModeFacetCount {
    StorageMode value;
    string label;
    i64 count;
    boolean selected;
    boolean disabled;
};

dictionary SearchDateFacetBounds {
    i64? oldest_imported_at;
    i64? newest_imported_at;
    i64? oldest_modified_at;
    i64? newest_modified_at;
};

dictionary SearchFacets {
    string query;
    i64 total_count;
    sequence<SearchFacetCount> categories;
    sequence<SearchFacetCount> file_kinds;
    sequence<SearchFacetCount> tags;
    sequence<SearchStorageModeFacetCount> storage_modes;
    SearchDateFacetBounds date_bounds;
    i64 active_filter_count;
};

dictionary SearchPagination {
    i64 limit;
    i64 offset;
};

dictionary SearchMatch {
    SearchMatchField field;
    SearchMatchKind kind;
    string snippet;
    i64? start;
    i64? end;
};

dictionary SearchFileResult {
    FileEntry entry;
    f32 score;
    sequence<SearchMatch> matches;
    string? note_snippet;
};

dictionary SearchQueryDiagnostic {
    SearchDiagnosticKind kind;
    SearchDiagnosticSeverity severity;
    string message;
    string? token;
    i64? start;
    i64? end;
    string? suggestion;
};

dictionary SearchResultPage {
    string query;
    i64 total_count;
    sequence<SearchFileResult> results;
    sequence<SearchQueryDiagnostic> diagnostics;
    SearchIndexStatus index_status;
};

dictionary SavedSearchQuery {
    string query;
    SearchFilter filter;
    SearchSort sort;
};

dictionary CreateSavedSearchRequest {
    string name;
    SavedSearchQuery query;
    string? icon;
    string? color;
    boolean pinned;
};

dictionary UpdateSavedSearchRequest {
    i64 id;
    string name;
    SavedSearchQuery query;
    string? icon;
    string? color;
    boolean pinned;
};

dictionary SavedSearch {
    i64 id;
    string name;
    SavedSearchQuery query;
    string? icon;
    string? color;
    boolean pinned;
    i64 created_at;
    i64 updated_at;
};

dictionary CommandIndexContext {
    string? query;
    sequence<i64> selected_file_ids;
    string? current_path;
    boolean include_file_candidates;
};

dictionary CommandTarget {
    string id;
    string title;
    string? subtitle;
    CommandTargetGroup group;
    CommandTargetKind kind;
    CommandTargetAction action;
    string? route;
    string? shortcut;
    boolean disabled;
    string? disabled_reason;
    boolean requires_confirmation;
    i64? file_id;
    i64? saved_search_id;
};

dictionary CommandIndex {
    sequence<CommandTarget> commands;
    sequence<CommandTarget> navigation_targets;
    sequence<CommandTarget> current_selection_targets;
    sequence<CommandTarget> recent_targets;
    sequence<CommandTarget> smart_lists;
    sequence<CommandTarget> file_candidates;
    i64 generated_at;
};

dictionary TagRecord {
    string value;
    string label;
    i64 file_count;
    boolean selected;
    boolean disabled;
    i64 updated_at;
};

dictionary TagSet {
    i64 file_id;
    sequence<TagRecord> file_tags;
    sequence<TagRecord> available_tags;
    sequence<TagRecord> recent_tags;
    i64 updated_at;
};

dictionary BatchMutationItemResult {
    i64 file_id;
    string tag;
    BatchMutationStatus status;
    string? error;
};

dictionary BatchMutationReport {
    i64 requested_file_count;
    i64 requested_tag_count;
    i64 added_count;
    i64 skipped_count;
    i64 failed_count;
    sequence<BatchMutationItemResult> item_results;
    string? undo_token;
};

dictionary TagSuggestionContext {
    string? source_folder;
    sequence<string> source_keywords;
};

dictionary TagSuggestionRequest {
    i64 file_id;
    TagSuggestionContext? context;
    i64 limit;
};

dictionary TagSuggestion {
    string suggestion_id;
    string slug;
    string display_name;
    string reason;
    TagSuggestionSource source;
    TagSuggestionMatch match_strength;
    boolean already_exists;
    boolean needs_create;
    TagSuggestionStatus status;
    boolean selected_by_default;
    string? disabled_reason;
};

dictionary TagSuggestionReport {
    i64 file_id;
    sequence<TagSuggestion> suggestions;
    TagSet tag_set;
    boolean contents_read;
    boolean ai_used;
    boolean network_used;
};

dictionary ApplyTagSuggestionItem {
    string suggestion_id;
    string slug;
    string display_name;
};

dictionary ApplyTagSuggestionsRequest {
    i64 file_id;
    sequence<ApplyTagSuggestionItem> suggestions;
};

dictionary TagSuggestionApplyItemResult {
    string suggestion_id;
    string slug;
    TagSuggestionApplyStatus status;
    string? error;
};

dictionary TagSuggestionApplyReport {
    i64 file_id;
    i64 requested_count;
    i64 applied_count;
    i64 skipped_count;
    i64 failed_count;
    sequence<TagSuggestionApplyItemResult> item_results;
    TagSet tag_set;
    string? undo_token;
    sequence<string> refresh_targets;
};

dictionary CategoryDistributionItem {
    string category;
    i64 count;
};

dictionary BatchCategoryPreviewItem {
    i64 file_id;
    string? from_category;
    string to_category;
    string? current_path;
    string? target_path;
    string? target_name;
    StorageMode? storage_mode;
    boolean index_only;
    boolean will_move_file;
    BatchCategoryPreviewStatus status;
    string? reason;
};

dictionary BatchCategoryPreviewReport {
    i64 requested_file_count;
    string target_category;
    boolean move_repo_owned_files;
    string preview_token;
    sequence<CategoryDistributionItem> category_distribution;
    i64 will_move_count;
    i64 metadata_only_count;
    i64 unchanged_count;
    i64 skipped_count;
    i64 blocked_count;
    sequence<BatchCategoryPreviewItem> items;
    boolean can_apply;
    string? apply_blocked_reason;
};

dictionary BatchCategoryChangeItemResult {
    i64 file_id;
    string? from_category;
    string to_category;
    string? final_path;
    BatchCategoryResultStatus status;
    string? error;
};

dictionary BatchCategoryChangeReport {
    i64 requested_file_count;
    string target_category;
    i64 moved_count;
    i64 metadata_only_count;
    i64 unchanged_count;
    i64 skipped_count;
    i64 failed_count;
    sequence<BatchCategoryChangeItemResult> item_results;
    sequence<FileEntry> updated_files;
    string? undo_token;
};

dictionary BatchDeletePreviewItem {
    i64 file_id;
    string? current_path;
    string? current_name;
    StorageMode? storage_mode;
    BatchDeleteMode delete_mode;
    boolean will_move_to_trash;
    boolean will_remove_index;
    BatchDeletePreviewStatus status;
    string? reason;
};

dictionary BatchDeletePreviewReport {
    i64 requested_file_count;
    BatchDeleteMode delete_mode;
    string preview_token;
    boolean trash_available;
    boolean undo_available;
    i64 will_trash_count;
    i64 index_only_count;
    i64 missing_count;
    i64 skipped_count;
    i64 blocked_count;
    sequence<BatchDeletePreviewItem> items;
    boolean can_apply;
    string? apply_blocked_reason;
};

dictionary BatchDeleteItemResult {
    i64 file_id;
    string? final_path;
    BatchDeleteResultStatus status;
    string? error;
};

dictionary BatchDeleteReport {
    i64 requested_file_count;
    BatchDeleteMode delete_mode;
    i64 moved_to_trash_count;
    i64 removed_from_index_count;
    i64 skipped_count;
    i64 failed_count;
    sequence<BatchDeleteItemResult> item_results;
    sequence<i64> affected_file_ids;
    string? undo_token;
};

dictionary BatchRenameRule {
    BatchRenameMode mode;
    string? prefix;
    BatchRenameDateSource? date_source;
    string? date_format;
    string? separator;
    i64? start_number;
    i64? padding;
    string? find;
    string? replacement;
    boolean case_sensitive;
};

dictionary BatchRenameConflict {
    i64 file_id;
    i64? conflicting_file_id;
    string? conflict_path;
    string reason;
};

dictionary BatchRenamePreviewItem {
    i64 file_id;
    string? current_path;
    string? original_name;
    string? new_name;
    string? target_path;
    StorageMode? storage_mode;
    boolean index_only;
    boolean will_rename_file;
    BatchRenamePreviewStatus status;
    string? reason;
};

dictionary BatchRenamePreviewReport {
    i64 requested_file_count;
    BatchRenameRule rule;
    string preview_token;
    i64 will_rename_count;
    i64 display_only_count;
    i64 unchanged_count;
    i64 blocked_count;
    i64 conflict_count;
    sequence<BatchRenamePreviewItem> items;
    sequence<BatchRenameConflict> conflicts;
    boolean can_apply;
    string? apply_blocked_reason;
};

dictionary BatchRenameItemResult {
    i64 file_id;
    string? original_name;
    string? final_name;
    string? final_path;
    BatchRenameResultStatus status;
    string? error;
};

dictionary BatchRenameReport {
    i64 requested_file_count;
    i64 renamed_count;
    i64 display_name_updated_count;
    i64 unchanged_count;
    i64 skipped_count;
    i64 failed_count;
    sequence<BatchRenameItemResult> item_results;
    sequence<FileEntry> updated_files;
    string? undo_token;
};

dictionary ClassifierRuleDraft {
    i64 source_file_id;
    string target_category;
    sequence<string> keyword_candidates;
    sequence<string> extension_candidates;
    i64 priority;
};

dictionary ClassifierCorrectionResult {
    FileEntry updated_file;
    ClassifierRuleDraft? rule_draft;
    boolean move_file_requested;
    boolean remember_requested;
    boolean rule_confirmation_required;
};

dictionary ClassifierRule {
    string target_category;
    sequence<string> keywords;
    sequence<string> extensions;
    i64 priority;
    boolean preview_confirmed;
};

dictionary ClassifierRuleRecord {
    string rule_id;
    string slug;
    string display_name;
    string description;
    sequence<string> extensions;
    sequence<string> keywords;
    i64 priority;
    string? naming_template;
    boolean is_default;
};

dictionary ClassifierRuleEditorSnapshot {
    sequence<ClassifierRuleRecord> rules;
    string default_rule_id;
    string? updated_rule_id;
    string? warning;
};

dictionary ClassifierRuleCreateRequest {
    string slug;
    string display_name;
    string description;
    sequence<string> extensions;
    sequence<string> keywords;
    i64 priority;
    string? naming_template;
};

dictionary ClassifierRuleUpdate {
    string rule_id;
    string slug;
    string display_name;
    string description;
    sequence<string> extensions;
    sequence<string> keywords;
    i64 priority;
    string? naming_template;
    boolean preview_confirmed;
};

dictionary ClassifierRuleDeleteRequest {
    string rule_id;
    string? replacement_category;
    boolean preview_confirmed;
};

dictionary ClassifierImpactPreviewRequest {
    ClassifierImpactPreviewMode mode;
    ClassifierRule rule;
    boolean move_files;
    string? replacement_category;
};

dictionary RuleImpactSample {
    i64 file_id;
    string path;
    string current_category;
    string new_category;
    sequence<RuleImpactMatchReason> match_reasons;
    RuleImpactStatus status;
    string? reason;
};

dictionary RuleImpactConflict {
    i64 file_id;
    string? path;
    string? conflicting_path;
    RuleImpactConflictKind kind;
    string reason;
};

dictionary RuleImpactReport {
    ClassifierImpactPreviewRequest request;
    i64 affected_file_count;
    i64 will_update_count;
    i64 already_correct_count;
    i64 needs_review_count;
    i64 conflict_count;
    i64 sample_limit;
    sequence<RuleImpactSample> samples;
    sequence<RuleImpactConflict> conflicts;
    boolean needs_review;
    boolean warning_required;
    string? warning;
    boolean can_apply;
    string? apply_blocked_reason;
};

dictionary UndoActionRecord {
    string action_id;
    string kind;
    string summary;
    i64 affected_count;
    sequence<string> affected_file_names;
    UndoActionStatus status;
    boolean can_undo;
    string? disabled_reason;
    i64 created_at;
    i64 updated_at;
};

dictionary UndoActionResult {
    string action_id;
    UndoActionStatus status;
    string summary;
    i64 affected_count;
    sequence<string> refresh_targets;
    i64 completed_at;
};

dictionary RedoActionRecord {
    string action_id;
    string kind;
    string summary;
    i64 affected_count;
    sequence<string> affected_file_names;
    RedoActionStatus status;
    boolean can_redo;
    string? disabled_reason;
    string source_undo_action_id;
    i64 created_at;
    i64 updated_at;
};

dictionary RedoActionResult {
    string action_id;
    RedoActionStatus status;
    string summary;
    i64 affected_count;
    sequence<string> refresh_targets;
    string? undo_token;
    i64 completed_at;
};

dictionary ChangeFilter {
    i64? file_id;
    string? category;
    string? action;
    i64? since;
    i64? until;
    i64 limit;
    i64 offset;
};

dictionary FileEntry {
    i64 id;
    string path;
    string original_name;
    string current_name;
    string category;
    i64 size_bytes;
    string hash_sha256;
    StorageMode storage_mode;
    FileOrigin origin;
    string? source_path;
    i64 imported_at;
    i64 updated_at;
};

dictionary MoveToCategoryPreview {
    i64 file_id;
    string from_category;
    string to_category;
    string current_path;
    string target_path;
    string target_name;
    StorageMode storage_mode;
    boolean index_only;
    boolean name_conflict_resolved;
    boolean will_move_file;
};

dictionary ICloudConflictPair {
    string conflict_id;
    string? original_path;
    string conflicted_copy_path;
    i64? original_modified_at;
    i64 conflicted_modified_at;
    ICloudConflictStatus status;
    string? uncertainty_reason;
};

dictionary ICloudConflictVersionMetadata {
    string version_id;
    ICloudConflictVersionRole role;
    string path;
    i64? modified_at;
    i64? size_bytes;
    string? hash_sha256;
    string? preview_summary;
    ICloudConflictPreviewStatus preview_status;
};

dictionary ICloudConflictResolutionOption {
    ICloudConflictResolution resolution;
    boolean destructive;
    boolean requires_trash;
    boolean enabled;
    string? disabled_reason;
};

dictionary ICloudConflictPreviewReport {
    string conflict_id;
    sequence<ICloudConflictVersionMetadata> versions;
    ICloudConflictResolution default_resolution;
    sequence<ICloudConflictResolutionOption> resolution_options;
    boolean metadata_complete;
    boolean trash_available;
    boolean can_keep_both;
    boolean can_resolve_destructive;
    string? blocked_reason;
};

dictionary ICloudConflictResolveReport {
    string conflict_id;
    ICloudConflictResolution resolution;
    ICloudConflictStatus status;
    sequence<string> kept_paths;
    sequence<string> trashed_paths;
    string? undo_token;
    string change_log_action;
};

dictionary ImportConflictBatchPreviewRequest {
    string import_session_id;
    sequence<string> conflict_ids;
    ImportConflictBatchStrategy duplicate_strategy;
    ImportConflictBatchStrategy same_name_strategy;
    boolean apply_to_all_similar_conflicts;
};

dictionary ImportConflictBatchPreviewItem {
    string conflict_id;
    ImportConflictBatchConflictType conflict_type;
    i64? existing_file_id;
    string? existing_path;
    string incoming_path;
    string? target_path;
    ImportConflictBatchStrategy selected_strategy;
    ImportConflictBatchPreviewStatus status;
    boolean will_replace;
    boolean will_keep_both;
    boolean will_skip;
    boolean will_ask_per_item;
    boolean index_only;
    string risk_summary;
    string? reason;
};

dictionary ImportConflictBatchPreviewReport {
    string import_session_id;
    string preview_token;
    boolean apply_to_all_similar_conflicts;
    i64 requested_conflict_count;
    i64 duplicate_conflict_count;
    i64 same_name_conflict_count;
    i64 included_count;
    i64 pending_count;
    i64 blocked_count;
    i64 replace_count;
    i64 skip_count;
    i64 keep_both_count;
    i64 ask_per_item_count;
    boolean trash_available;
    boolean undo_available;
    boolean can_apply;
    string? apply_blocked_reason;
    boolean replace_confirmation_required;
    string? replace_confirmation_summary;
    sequence<ImportConflictBatchPreviewItem> items;
};

dictionary ImportConflictBatchApplyRequest {
    string import_session_id;
    sequence<string> conflict_ids;
    ImportConflictBatchStrategy duplicate_strategy;
    ImportConflictBatchStrategy same_name_strategy;
    boolean apply_to_all_similar_conflicts;
    boolean replace_confirmed;
};

dictionary ImportConflictBatchItemResult {
    string conflict_id;
    ImportConflictBatchConflictType conflict_type;
    ImportConflictBatchStrategy applied_strategy;
    ImportConflictBatchResultStatus status;
    i64? file_id;
    string? final_path;
    string? error;
};

dictionary ImportConflictBatchApplyReport {
    string import_session_id;
    i64 requested_conflict_count;
    i64 resolved_count;
    i64 skipped_count;
    i64 kept_both_count;
    i64 replaced_count;
    i64 queued_for_per_item_count;
    i64 pending_count;
    i64 failed_count;
    sequence<ImportConflictBatchItemResult> item_results;
    sequence<i64> affected_file_ids;
    string? undo_token;
    sequence<string> change_log_actions;
    string? failure_summary;
};

dictionary ChangeLogEntry {
    i64 id;
    i64? file_id;
    string filename;
    string category;
    string action;
    string detail_json;
    i64 occurred_at;
};

dictionary ClassifyResult {
    string category;
    string suggested_name;
    ClassifyReason reason;
    f32 confidence;
};

dictionary RecoveryReport {
    i64 cleaned_staging_files;
    i64 reverted_staging_db_rows;
    sequence<string> warnings;
};

dictionary ReindexReport {
    i64? scan_session_id;
    i64 inserted;
    i64 updated;
    i64 skipped;
    sequence<string> errors;
};

dictionary RepairOptions {
    boolean full_rescan;
    boolean preserve_diagnostics_snapshot;
};

dictionary DiagnosticsSnapshot {
    string snapshot_path;
    i64 created_at;
    sequence<string> warnings;
};

dictionary RepairReport {
    i64? scan_session_id;
    string? diagnostics_snapshot_path;
    i64 inserted;
    i64 updated;
    i64 skipped;
    sequence<string> errors;
};

dictionary ScanSession {
    i64 id;
    ScanSessionKind kind;
    ScanSessionStatus status;
    string? last_path;
    i64 inserted;
    i64 updated;
    i64 skipped;
    i64 started_at;
    i64 updated_at;
    i64? finished_at;
    sequence<string> errors;
};

dictionary ExternalEvent {
    string path;
    ExternalEventKind kind;
    i64 fs_event_id;
};

dictionary SyncResult {
    i64 detected_creates;
    i64 detected_renames;
    i64 detected_deletes;
    i64 detected_modifies;
    sequence<string> errors;
};

dictionary ErrorMappingInput {
    ErrorKind kind;
    string? path;
    string? reason;
    string? message;
};

dictionary ErrorMapping {
    ErrorKind kind;
    string user_message;
    ErrorSeverity severity;
    string suggested_action;
    ErrorRecoverability recoverability;
    string raw_context;
};

enum StorageMode { "Moved", "Copied", "Indexed" };
enum FileOrigin { "Imported", "Adopted", "External" };
enum RepoInitMode { "CreateEmpty", "AdoptExisting" };
enum RepoPathIssue {
    "MissingPath", "NotDirectory", "NotReadable", "NotWritable",
    "NonEmptyDirectory", "AlreadyInitialized", "InsideAreaMatrix",
    "ICloudPath", "UnfinishedScanSession"
};
enum OverviewOutput { "GeneratedOnly", "RootAreaMatrixFile" };
enum AiProviderPreference { "LocalFirst", "LocalOnly", "RemoteFirst" };
enum AiFeatureKind {
    "ClassificationSuggestions", "AutoSummaries", "AutoTags", "SemanticSearch"
};
enum RemoteAiProviderKind { "OpenAi", "Anthropic", "Other" };
enum RemoteProviderTestStatus {
    "Succeeded", "ProviderRejected", "ConnectionFailed", "UnsupportedProvider"
};
enum AiCategorySuggestionContextPolicy {
    "FileNameOnly", "FileNameAndPath", "LimitedTextSummary"
};
enum AiCategorySuggestionContextField {
    "FileName", "Extension", "RepoRelativePath", "LimitedTextSummary"
};
enum AiCategorySuggestionRoute { "Local", "Remote" };
enum AiCategorySuggestionStatus {
    "Suggested", "NoSuggestion", "Skipped", "Unavailable"
};
enum AiCategorySuggestionSkipReason {
    "AiDisabled", "FeatureDisabled", "RuleResultConfident",
    "NoEligibleContext", "PrivacyRule", "ProviderUnavailable"
};
enum AiSummaryProviderScope { "LocalOnly", "LocalPreferred", "RemoteAllowed" };
enum AiSummaryContextPolicy {
    "MetadataOnly", "MetadataAndExtractedText", "MetadataTextAndNotes"
};
enum AiSummaryInputField {
    "FileName", "RepoRelativePath", "ExtractedTextExcerpt",
    "ExistingAiSummary", "NoteSummary", "TagCategoryContext"
};
enum AiSummaryRoute { "Local", "Remote" };
enum AiSummaryDraftStatus { "Draft", "Skipped", "Unavailable" };
enum AiSummarySkipReason {
    "AiDisabled", "FeatureDisabled", "ProviderUnavailable",
    "PrivacyRule", "NoEligibleInput", "CallLogUnavailable"
};
enum AiCallLogFeature {
    "Classification", "Summary", "Tags", "SemanticSearch", "ProviderTest"
};
enum AiCallLogRoute { "Local", "Remote" };
enum AiCallLogStatus { "Success", "Failed", "Skipped", "Unavailable" };
enum AiCallLogSentField {
    "FileName", "RepoRelativePath", "Extension", "ExtractedTextExcerpt",
    "AiSummary", "NoteSummary", "TagCategoryContext"
};
enum AiCallLogClearScope { "All", "SelectedEntries", "OlderThan" };
enum LocalModelAvailability {
    "Unknown", "Ready", "NotInstalled", "PathUnreadable",
    "VersionIncompatible", "Checking", "Verifying", "Loading",
    "Corrupted", "RuntimeFailed", "Error"
};
enum LocalModelRecommendedAction {
    "None", "CheckStatus", "RetryStatusCheck", "OpenInstallHelp",
    "OpenModelLocation", "RunHealthCheck", "RepairMetadata",
    "OpenDiagnostics", "UseNonAiFallback"
};
enum ImportDestination { "AutoClassify", "SelectedDirectory", "Category" };
enum ScanSessionKind { "Adopt", "Reindex" };
enum ScanSessionStatus { "Running", "Completed", "Paused", "Failed", "Interrupted" };
enum DuplicateStrategy { "Skip", "Overwrite", "KeepBoth", "Ask" };
enum ClassifyReason { "Keyword", "Extension", "AiPredicted", "Default" };
enum SearchScope { "AllRepo", "CurrentNode" };
enum SearchTagMatchMode { "Any", "All" };
enum SearchSort { "Relevance", "NewestImported", "NewestModified", "NameAsc" };
enum SearchMatchKind { "Exact", "Fuzzy", "PinyinInitials" };
enum SearchMatchField { "Name", "Path", "Note", "Category", "ChangeLog" };
enum SearchDiagnosticKind {
    "UnclosedQuote", "UnknownField", "InvalidDate",
    "UnbalancedParentheses", "InvalidOperator"
};
enum SearchDiagnosticSeverity { "Info", "Warning", "Error" };
enum SearchIndexStatus { "Ready", "Indexing", "Unavailable" };
enum CommandTargetGroup {
    "Commands", "Navigation", "CurrentSelection",
    "Recent", "SmartLists", "FileCandidates"
};
enum CommandTargetKind {
    "Command", "Navigation", "SmartList",
    "FileCandidate", "RecentCommand"
};
enum CommandTargetAction {
    "Navigate", "OpenSheet", "OpenConfirmation", "RunSmartList",
    "FocusFile", "OpenSearch", "LowRiskAction"
};
enum ICloudConflictStatus { "NeedsReview", "Resolved" };
enum ICloudConflictVersionRole { "Original", "ConflictedCopy" };
enum ICloudConflictPreviewStatus { "Available", "MetadataOnly", "Unavailable" };
enum ICloudConflictResolution { "KeepBoth", "KeepOriginal", "KeepConflictedCopy" };
enum ImportConflictBatchConflictType { "DuplicateHash", "SameNameDifferentContent" };
enum ImportConflictBatchStrategy { "Skip", "KeepBoth", "Replace", "AskPerItem" };
enum ImportConflictBatchPreviewStatus {
    "Ready", "Pending", "NeedsConfirmation", "Blocked", "Failed"
};
enum ImportConflictBatchResultStatus {
    "Skipped", "KeptBoth", "Replaced", "QueuedForPerItem", "Pending", "Failed"
};
enum ExternalEventKind { "Created", "Removed", "Modified", "Renamed" };
enum BatchMutationStatus { "Added", "AlreadyHadTag", "Failed" };
enum TagSuggestionSource { "FileName", "Path", "SourceFolder", "ExistingTagPattern" };
enum TagSuggestionMatch { "Strong", "Weak" };
enum TagSuggestionStatus { "NewTag", "AlreadyAdded", "Invalid", "Blocked" };
enum TagSuggestionApplyStatus { "Applied", "AlreadyAdded", "Failed" };
enum BatchCategoryPreviewStatus { "WillMove", "MetadataOnly", "Unchanged", "Skipped", "Blocked" };
enum BatchCategoryResultStatus { "Moved", "MetadataUpdated", "Unchanged", "Skipped", "Failed" };
enum BatchDeleteMode { "MoveToTrash", "RemoveFromIndex" };
enum BatchDeletePreviewStatus { "WillMoveToTrash", "IndexOnly", "Missing", "Skipped", "Blocked" };
enum BatchDeleteResultStatus { "MovedToTrash", "RemovedFromIndex", "Skipped", "Failed" };
enum BatchRenameMode { "Prefix", "DatePrefix", "KeepBaseSequence", "ReplaceText" };
enum BatchRenameDateSource { "Imported", "Modified", "Today" };
enum BatchRenamePreviewStatus {
    "Ok", "Error", "NameConflict", "Missing", "ReadOnly",
    "DisplayOnly", "Unchanged", "ExternalChange"
};
enum BatchRenameResultStatus { "Renamed", "DisplayNameUpdated", "Unchanged", "Skipped", "Failed" };
enum ClassifierImpactPreviewMode {
    "RuleDraft", "RemoveKeyword", "RemoveExtension", "RemoveCategory"
};
enum RuleImpactMatchReason { "Keyword", "Extension", "Category" };
enum RuleImpactStatus {
    "WillUpdate", "AlreadyCorrect", "NeedsReview",
    "Conflict", "Missing", "IndexOnly"
};
enum RuleImpactConflictKind { "NameConflict", "MissingFile", "UnsupportedStorage", "RuleConflict" };
enum UndoActionStatus { "Pending", "Executed", "Expired", "Blocked" };
enum RedoActionStatus { "Available", "Cleared", "Blocked", "Expired", "Executed" };
enum ErrorKind {
    "Io", "Db", "Config", "Validation", "Classify", "Conflict", "DuplicateFile",
    "FileNotFound", "ExpiredAction", "RepoNotInitialized", "InvalidPath",
    "ICloudPlaceholder", "StagingRecoveryRequired", "PermissionDenied", "Internal"
};
enum ErrorSeverity { "Low", "Medium", "High", "Critical" };
enum ErrorRecoverability {
    "Retryable", "UserActionRequired", "RefreshRequired", "Fatal"
};

[Error]
interface CoreError {
    Io(string message);
    Db(string message);
    Config(string reason);
    Validation(string reason);
    Classify(string reason);
    Conflict(string path);
    DuplicateFile(string existing_path);
    FileNotFound(string path);
    ExpiredAction(string action_id);
    RepoNotInitialized(string path);
    InvalidPath(string path);
    ICloudPlaceholder(string path);
    StagingRecoveryRequired(string path);
    PermissionDenied(string path);
    Internal(string message);
};
```

详细错误体系：[error-codes.md](error-codes.md)。

---

## 类型映射表

| Rust | UDL | Swift | Kotlin |
|---|---|---|---|
| `String` | `string` | `String` | `String` |
| `Option<String>` | `string?` | `String?` | `String?` |
| `i64` | `i64` | `Int64` | `Long` |
| `f32` | `f32` | `Float` | `Float` |
| `bool` | `boolean` | `Bool` | `Boolean` |
| `Vec<T>` | `sequence<T>` | `[T]` | `List<T>` |
| `HashMap<K,V>` | `record<K,V>` | `[K: V]` | `Map<K,V>` |
| `enum E` | `enum E` | `enum E` | `enum class E` |
| `struct S` | `dictionary S` | `struct S` | `data class S` |
| `Result<T, E>` | `[Throws=E] T` | `func() throws -> T` | `@Throws fun ... ` |

---

## 函数总览

| 函数 | 类别 | Throws | 主要错误 |
|---|---|---|---|
| `get_version()` | meta | × | — |
| `init_logging(level)` | meta | √ | Config |
| `validate_repo_path(repo)` | repo | √ | InvalidPath / PermissionDenied / ICloudPlaceholder |
| `validate_initialized_repo_path(repo)` | repo | √ | InvalidPath / PermissionDenied / ICloudPlaceholder / RepoNotInitialized |
| `init_repo(path, options)` | repo | √ | Io / Config / PermissionDenied |
| `load_config(repo)` | repo | √ | Config / PermissionDenied / Io / Db |
| `update_config(repo, cfg)` | repo | √ | Config / PermissionDenied / Io / Db |
| `load_ai_config(repo)` | ai | √ | Config / PermissionDenied / Io |
| `update_ai_config(repo, cfg)` | ai | √ | Config / PermissionDenied / Io |
| `get_local_model_status(repo, request)` | ai | √ | Config / PermissionDenied / Io |
| `locate_local_model_folder(repo, request)` | ai | √ | Config / PermissionDenied / Io |
| `test_remote_ai_provider(repo, request)` | ai | √ | Config / PermissionDenied / Internal |
| `load_remote_ai_provider_config(repo)` | ai | √ | Config / Internal |
| `enable_remote_ai_provider(repo, request)` | ai | √ | Config / PermissionDenied / Internal |
| `disable_remote_ai_provider(repo, request)` | ai | √ | Config / Internal |
| `suggest_category_with_ai(repo, request)` | ai | √ | Config / PermissionDenied / Internal |
| `list_ai_calls(repo, filter, pagination)` | ai | √ | Db / PermissionDenied |
| `clear_ai_call_log(repo, request)` | ai | √ | Db / PermissionDenied |
| `generate_ai_summary(repo, request)` | ai | √ | Config / FileNotFound / PermissionDenied / Db |
| `save_ai_summary(repo, request)` | ai | √ | Config / FileNotFound / PermissionDenied / Db |
| `clear_ai_summary(repo, request)` | ai | √ | Config / FileNotFound / PermissionDenied / Db |
| `recover_on_startup(repo)` | repo | √ | Db |
| `reindex_from_filesystem(repo)` | repo | √ | Io / Db |
| `create_diagnostics_snapshot(repo)` | repo | √ | Db / PermissionDenied / Io / Internal |
| `repair_metadata(repo, options)` | repo | √ | Db / PermissionDenied / Io / Internal |
| `get_latest_scan_session(repo)` | repo | √ | Db |
| `resume_scan_session(repo, id)` | repo | √ | Io / Db |
| `predict_category(repo, name)` | classify | √ | Config / Classify |
| `import_file(repo, src, options)` | storage | √ | Io / Db / DuplicateFile / InvalidPath |
| `delete_file(repo, file_id)` | storage | √ | Io / Db / FileNotFound / PermissionDenied / Internal |
| `remove_index_entry(repo, file_id)` | storage | √ | Db / FileNotFound / PermissionDenied / Internal |
| `rename_file(repo, file_id, new_name)` | storage | √ | Io / Db / Config / InvalidPath / Conflict / FileNotFound / PermissionDenied |
| `preview_move_to_category(repo, file_id, cat)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |
| `move_to_category(repo, file_id, cat)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |
| `restore_file(repo, file_id)` | storage | √ | FileNotFound |
| `list_files(repo, filter)` | query | √ | Db |
| `search_files(repo, query, filter, sort, pagination)` | search | √ | Db / Config / InvalidPath |
| `list_filter_facets(repo, query)` | search | √ | Db / Config |
| `create_saved_search(repo, request)` | search | √ | Db / Config |
| `update_saved_search(repo, request)` | search | √ | Db / Config |
| `delete_saved_search(repo, saved_search_id)` | search | √ | Db / Config |
| `list_saved_searches(repo)` | search | √ | Db / Config |
| `run_smart_list(repo, saved_search_id, pagination)` | search | √ | Db / Config / FileNotFound |
| `list_command_targets(repo, context)` | command | √ | Db |
| `add_tag(repo, file_id, tag)` | tags | √ | FileNotFound / Db / InvalidPath |
| `remove_tag(repo, file_id, tag)` | tags | √ | FileNotFound / Db / InvalidPath |
| `list_tags(repo, file_id)` | tags | √ | FileNotFound / Db / InvalidPath |
| `batch_add_tags(repo, file_ids, tags)` | tags | √ | FileNotFound / Db |
| `suggest_tags_for_file(repo, request)` | tags | √ | FileNotFound / Validation / Conflict / Db |
| `apply_tag_suggestions(repo, request)` | tags | √ | FileNotFound / Validation / Conflict / Db |
| `preview_batch_move_to_category(repo, file_ids, category, move)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |
| `batch_move_to_category(repo, file_ids, category, move, preview_token)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |
| `preview_batch_delete(repo, file_ids, delete_mode)` | storage | √ | PermissionDenied / FileNotFound / Conflict / Io / Db |
| `batch_delete_to_trash(repo, file_ids, delete_mode, preview_token)` | storage | √ | PermissionDenied / FileNotFound / Conflict / Io / Db |
| `preview_batch_rename(repo, file_ids, rule)` | storage | √ | InvalidPath / Conflict / FileNotFound / PermissionDenied / Io / Db |
| `batch_rename(repo, file_ids, rule, preview_token)` | storage | √ | InvalidPath / Conflict / FileNotFound / PermissionDenied / Io / Db |
| `correct_file_category(repo, file_id, category, move_file, remember)` | classify | √ | Classify / Conflict / Io / Db |
| `save_classifier_rule(repo, rule)` | classify | √ | Config / PermissionDenied / Io |
| `preview_classifier_rule_impact(repo, request)` | classify | √ | Config / Db |
| `list_classifier_rules(repo)` | classify | √ | Config / PermissionDenied / Io |
| `create_classifier_rule(repo, request)` | classify | √ | Config / PermissionDenied / Io |
| `update_classifier_rule(repo, request)` | classify | √ | Config / PermissionDenied / Io |
| `delete_classifier_rule(repo, request)` | classify | √ | Config / PermissionDenied / Io |
| `list_undo_actions(repo)` | undo | √ | Db / Io |
| `undo_action(repo, action_id)` | undo | √ | Conflict / FileNotFound / PermissionDenied / Db / Io |
| `list_redo_actions(repo)` | redo | √ | Db / Io |
| `redo_action(repo, action_id)` | redo | √ | Conflict / FileNotFound / ExpiredAction / PermissionDenied / Db / Io |
| `get_file(repo, file_id)` | query | √ | FileNotFound |
| `list_changes(repo, filter)` | query | √ | Db |
| `list_tree_json(repo, locale)` | query | √ | RepoNotInitialized / Db / Io |
| `list_icloud_conflicts(repo)` | query | √ | ICloudPlaceholder / PermissionDenied / Io / Db |
| `preview_conflict_versions(repo, conflict_id)` | conflict | √ | ICloudPlaceholder / PermissionDenied / Conflict / Io / Db |
| `resolve_icloud_conflict(repo, conflict_id, resolution)` | conflict | √ | ICloudPlaceholder / PermissionDenied / Conflict / Io / Db |
| `preview_import_conflict_batch(repo, request)` | conflict | √ | Conflict / FileNotFound / PermissionDenied / StagingRecoveryRequired / Io / Db |
| `apply_import_conflict_batch(repo, request, preview_token)` | conflict | √ | Conflict / FileNotFound / PermissionDenied / StagingRecoveryRequired / Io / Db |
| `read_note(repo, file_id)` | note | √ | Io |
| `write_note(repo, file_id, content)` | note | √ | Io |
| `sync_external_changes(repo, events)` | sync | √ | Db |
| `get_fs_event_cursor(repo)` | sync | √ | Db |
| `set_fs_event_cursor(repo, id)` | sync | √ | Db |

---

## Stage 1 API 缺口

> 本节记录 UX 页面已经需要、但当前 UDL 尚未完全表达的接口意图。实现前必须先更新本文档，再落到 `core/area_matrix.udl`。

| 缺口 | 消费页面 | 对应能力 | 意图 | 当前替代 |
|---|---|---|---|---|
| `preview_import(repo_path, source_path, options) -> ImportPreview` | S1-16, S1-17, S1-18, S1-19, S1-22, S1-23 | C1-05, C1-09, C1-10 | 在导入前返回分类建议、目标路径、重复 hash、同名冲突和 iCloud 状态 | `predict_category` 只能给分类，`import_file` 会直接产生副作用 |
| 导入进度 / 队列语义 | S1-18, S1-19, S1-20, S1-21 | C1-06, C1-07, C1-08 | 支撑多文件/文件夹导入的逐项状态、取消和结果摘要 | Stage 1 可先由 Swift 队列包装多次 `import_file`，Core 暂不提供流式回调 |
| 详情聚合 DTO | S1-12, S1-13, S1-14 | C1-12, C1-13, C1-14 | 一次拿到文件元数据、日志和笔记，降低 UI 调用编排 | Stage 1 先用 `get_file` + `list_changes` + `read_note` 组合 |
| 已初始化 repo 元数据摘要 | S1-03, S1-11 | C1-01, C1-21 | 已存在完整 repo 分支需要展示 `schema_version` 和 last opened，用于区分可打开、需修复和不可兼容状态 | S1-03 先用 macOS app 的只读 metadata inspector 读取 `.areamatrix/index.db` 中的 `schema_version`，last opened 无记录时显示未记录；不得伪造静态值。S1-11 仍需要后续 Core summary API 提升 |
| 错误映射元数据 | S1-03, S1-06, S1-11, S1-25, S1-32 | C1-21 | 每个错误返回 severity、suggested_action、recoverability，避免 UI 解析字符串 | `map_core_error` 返回 Core 侧稳定映射元数据，Swift `AppError` 包装层只负责本地化与展示编排 |

这些缺口不得被 UI 静态 mock 掩盖。若某个 UI 任务进入真实闭环验收，而所需缺口尚未实现或没有明确替代路径，验收应判定不通过。

### Stage 2-4 API 规划入口

Stage 2-4 尚未提升的后续接口先以 capability specs 作为合同来源，不直接落 UDL：

- Stage 2：C2-01 `search_files`、C2-02 `list_filter_facets` 和 C2-03 saved search
  CRUD（`create_saved_search`、`update_saved_search`、`delete_saved_search`、
  `list_saved_searches`），C2-04 `run_smart_list`，以及 C2-05 tag CRUD
  （`add_tag`、`remove_tag`、`list_tags`）和 C2-06 `batch_add_tags`
  以及 C2-07 undo action log（`list_undo_actions`、`undo_action`）、C2-08
  批量改分类（`preview_batch_move_to_category`、`batch_move_to_category`）
  C2-09 批量删除（`preview_batch_delete`、`batch_delete_to_trash`）、C2-10
  批量重命名（`preview_batch_rename`、`batch_rename`）和 C2-11
  命令索引（`list_command_targets`）、C2-13 分类规则保存
  （`save_classifier_rule`）、C2-14 规则影响预览
  （`preview_classifier_rule_impact`）以及 C2-15 分类规则编辑器
  （`list_classifier_rules`、`create_classifier_rule`、`update_classifier_rule`、`delete_classifier_rule`）、
  C2-19 非 AI 标签建议（`suggest_tags_for_file`、`apply_tag_suggestions`）
  已提升为本文与 `core/area_matrix.udl` 的稳定合同；
  Redo 和导入冲突批量决策仍见
  [../core/capability-specs/stage-2-experience.md](../core/capability-specs/stage-2-experience.md)。
- Stage 3：C3-01 AI 配置（`load_ai_config`、`update_ai_config`）已提升为本文与
  `core/area_matrix.udl` 的稳定合同；C3-02 本地模型状态
  （`get_local_model_status`、`locate_local_model_folder`）和 C3-03 远程 provider 配置
  （`test_remote_ai_provider`、`enable_remote_ai_provider`）以及 C3-04 AI 分类建议
  （`suggest_category_with_ai`）、C3-05 AI 调用日志（`list_ai_calls`、
  `clear_ai_call_log`）以及 C3-06 AI 摘要（`generate_ai_summary`、
  `save_ai_summary`、`clear_ai_summary`）已提升为本文与 `core/area_matrix.udl` 的稳定合同；
  语义搜索、隐私规则和 fallback 仍见
  [../core/capability-specs/stage-3-ai/](../core/capability-specs/stage-3-ai/)。
- Stage 4：iOS/Windows/Linux repo 连接、平台能力、watcher、跨平台导入、同步冲突、缺失恢复、手动重扫，见 [../core/capability-specs/stage-4-multiplatform.md](../core/capability-specs/stage-4-multiplatform.md)。

进入对应阶段前，应从能力规格中提升确定 API 到本文和 `core/area_matrix.udl`；未提升前不得让 UI 依赖临时 mock 通过最终验收。

---

## meta API

### `get_version() -> String`

```swift
let version = AreaMatrix.getVersion()
print("AreaMatrix Core \(version)")
```

返回 `Cargo.toml` 中的版本，形如 `"0.1.0"`。永不抛错。

### `init_logging(level: String) throws`

```swift
do {
    try AreaMatrix.initLogging(level: "info")
} catch let error as CoreError {
    print("logging init failed: \(error)")
}
```

`level`：`"trace" | "debug" | "info" | "warn" | "error"`。

应用最早调用，避免初始化中间状态丢日志。

---

## repo API

### `validate_repo_path(repoPath: String) throws -> RepoPathValidation`

```swift
let validation = try AreaMatrix.validateRepoPath(repoPath: selectedURL.path)
switch validation.recommendedMode {
case .createEmpty:
    await showCreateEmptyConfirm()
case .adoptExisting:
    await showAdoptExistingConfirm(issues: validation.issues)
case nil:
    await showPathIssues(validation.issues)
}
```

输入：

- `repoPath`：用户选择的候选资料库目录路径。

输出：

- `exists` / `isDirectory`：路径是否存在且是否为目录。
- `isReadable` / `isWritable`：Core 是否可读取目录内容、是否具备后续初始化写入能力。
- `isEmpty`：目录是否没有用户可见条目。
- `isInitialized`：目录下是否已有 `.areamatrix/` 元数据。
- `isInsideAreaMatrix`：选择位置是否为 `.areamatrix/` 或其子路径。
- `isIcloudPath`：是否疑似 iCloud 管理路径。
- `hasUnfinishedScanSession`：是否存在未完成的 adopt / reindex scan session。
- `recommendedMode`：路径可用于初始化时推荐 `CreateEmpty` 或 `AdoptExisting`，不可用时为 `nil`。
- `issues`：结构化问题列表，UI 不需要解析错误字符串即可展示风险。

错误：

- `InvalidPath`：路径为空、不是可接受的文件系统路径、或位于 `.areamatrix/` 内部。
- `PermissionDenied`：无法读取目录 metadata、列出目录内容或确认写权限。
- `ICloudPlaceholder`：候选路径或关键 metadata 仍是未下载的 iCloud 占位符。
- `RepoNotInitialized`：不由本入口返回；调用方要求已初始化语义时使用
  `validate_initialized_repo_path`。

副作用边界：

- 只读检查：metadata、权限、子项数量、`.areamatrix/` 探测、scan session 状态读取。
- 不创建、不删除、不移动、不重命名、不覆盖任何文件。
- 不触发 iCloud 占位符下载。
- 不执行 `init_repo`，非空目录只返回 `AdoptExisting` 推荐和结构化风险。

### `validate_initialized_repo_path(repoPath: String) throws -> RepoPathValidation`

```swift
let validation = try AreaMatrix.validateInitializedRepoPath(repoPath: lastKnownRepoPath)
if validation.isInitialized {
    await reopenRepository()
}
```

用于主窗口打开既有 repo、Retry、Reconnect folder 等调用方已经要求“这是一个已初始化资料库”的场景。
它复用 `validate_repo_path` 的只读检查，不创建 `.areamatrix/`，也不接管非空目录。

错误：

- `RepoNotInitialized`：候选目录存在且可检查，但没有 `.areamatrix/` 元数据。
- `InvalidPath`：路径为空、不是可接受的文件系统路径、或位于 `.areamatrix/` 内部。
- `PermissionDenied`：无法读取目录 metadata、列出目录内容或确认写权限。
- `ICloudPlaceholder`：候选路径或关键 metadata 仍是未下载的 iCloud 占位符。

### `init_repo(repoPath: String, options: RepoInitOptions) throws`

```swift
let options = RepoInitOptions(
    mode: .adoptExisting,
    createDefaultCategories: false,
    overviewOutput: .generatedOnly
)
do {
    try AreaMatrix.initRepo(repoPath: selectedURL.path, options: options)
} catch CoreError.Config(let reason) {
    if reason.contains("already managed") {
        await showAlert("这个目录已经是 AreaMatrix 资料库")
    }
} catch {
    throw error
}
```

执行：

- `CreateEmpty`：目录必须为空或仅包含系统隐藏文件；可按 `classifier.yaml` 创建分类目录
- `AdoptExisting`：目录可以非空；不移动、不重命名、不删除、不覆盖已有内容
- 创建 `.areamatrix/{staging, archives, generated}/`
- 复制默认 `classifier.yaml`
- 创建默认 `ignore.yaml`
- 创建 SQLite + 应用 schema v1
- `AdoptExisting` 模式下启动 `scan_sessions(kind=Adopt)` 并执行内部接管扫描
- 默认生成 `.areamatrix/generated/root.md`
- 仅当 `overview_output = RootAreaMatrixFile` 时写入/维护根目录 `AREAMATRIX.md`

约束：

- 永不写入或覆盖已有 `README.md`
- 选中 `.areamatrix/` 子目录 → `CoreError.InvalidPath`
- 目录不可写 → `CoreError.PermissionDenied`

### `load_config(repoPath: String) throws -> RepoConfig`

```swift
let cfg = try AreaMatrix.loadConfig(repoPath: repoPath)
print("default mode: \(cfg.defaultMode)")
print("locale: \(cfg.locale)")
```

`.areamatrix/index.db` 不存在时返回默认值（不抛错），且不创建 metadata、
配置文件或生成文件。metadata 存在但无法读取、解码或打开时，按
`Config`、`PermissionDenied`、`Io`、`Db` 传播。

### `update_config(repoPath: String, newConfig: RepoConfig) throws`

```swift
var cfg = try AreaMatrix.loadConfig(repoPath: repoPath)
cfg.defaultMode = .copied
cfg.overviewOutput = .generatedOnly
cfg.locale = "zh-Hans"
try AreaMatrix.updateConfig(repoPath: repoPath, newConfig: cfg)
```

通过 SQLite 事务更新 `repo_config` 中的
`repo_path`、`default_mode`、`overview_output`、`ai_enabled`、`locale`、
`icloud_warn`、`enable_extension_rules`、`enable_keyword_rules`、
`fallback_to_inbox`、`allow_replace_during_import`，并为每个键刷新
`updated_at`。该调用不写 tmp 文件、不
rename，也不创建或更新 `README.md`、`AREAMATRIX.md` 或
`.areamatrix/classifier.yaml`。

`enable_extension_rules`、`enable_keyword_rules` 与 `fallback_to_inbox`
支撑 `S1-28` 分类规则开关；`allow_replace_during_import` 支撑 `S1-30`
危险导入选项的默认关闭策略。它们只保存设置状态，不执行分类、导入或
替换行为。

`newConfig.repoPath` 必须等于 `repoPath`，`locale` 不能为空。任一校验、
权限、IO 或 DB 持久化失败时，事务回滚，旧配置保持可读；主要错误码为
`Config`、`PermissionDenied`、`Io`、`Db`。

### `load_ai_config(repoPath: String) throws -> AiConfigSnapshot`

```swift
let snapshot = try AreaMatrix.loadAiConfig(repoPath: repoPath)
if !snapshot.config.aiEnabled {
    print("AI is off")
}
```

C3-01 的 AI settings 读取入口，服务 `S3-01 ai-settings` 和 `S3-09
ai-privacy-rules` 对远程 gate 的只读状态展示。返回 `AiConfigSnapshot`：

- `config.ai_enabled`：AI 总开关，默认关闭；关闭时不得调用本地或远程模型。
- `config.provider_preference`：`LocalFirst`、`LocalOnly` 或 `RemoteFirst`，只表达
  设置偏好，不代表 provider 已可用。
- `config.local_ai_enabled` / `config.remote_ai_allowed`：本地和远程路线是否允许进入
  后续 provider gate。
- `config.privacy_gate_enabled` / `privacy_policy_ref`：S3-09 远程隐私 gate 状态和
  可选策略引用；不内嵌隐私规则列表。
- `config.feature_toggles`：`ClassificationSuggestions`、`AutoSummaries`、
  `AutoTags`、`SemanticSearch` 四个功能开关及是否允许远程路线。
- `capabilities`：每个功能的派生可用性、local/remote 允许状态和禁用原因，供 UI
  直接显示 provider 要求、远程 scope/gate 状态和 VoiceOver 文案。
- `updated_at`：实现持久化后返回最近更新时间；默认或未持久化状态可为 `nil`。

副作用边界：

- 读取配置不得启动本地模型、测试远程 provider、发起网络、写 AI 调用日志、读取用户文件内容、
  清理建议或写入用户文件。
- 不得传入或返回 API key；API key 只允许平台安全存储，C3-01 合同只引用状态或策略。
- 不返回 provider 连接测试结果、模型列表、AI 调用日志、隐私规则 CRUD 结果或语义索引状态；
  这些分别属于 C3-02、C3-03、C3-05、C3-09 和 C3-08。

错误：

- `Config`：`repoPath` 为空、位于 `.areamatrix/` 内部，或持久化配置结构无效。
- `PermissionDenied`：AI settings metadata 无法读取。
- `Io`：AI settings metadata inspection 失败。

页面消费状态：

- S3-01 可以从合同得到 AI 总开关、provider preference、本地/远程路线开关、功能开关、
  远程 gate 摘要、禁用原因和更新时间。
- S3-09 可以从合同得到 `privacy_gate_enabled`、`remote_ai_allowed`、功能远程允许状态和
  策略引用，用于判断本页是 privacy gate 而非 provider 禁用页。
- C3-01 不新增 control map 之外的页面能力；S3-03 仍负责 provider/key/scope/测试连接，
  S3-09 仍负责隐私规则 CRUD/evaluate。

### `update_ai_config(repoPath: String, newConfig: AiConfig) throws -> AiConfigSnapshot`

```swift
var snapshot = try AreaMatrix.loadAiConfig(repoPath: repoPath)
snapshot.config.aiEnabled = false
let updated = try AreaMatrix.updateAiConfig(
    repoPath: repoPath,
    newConfig: snapshot.config
)
```

C3-01 的 AI settings 更新入口，只保存 AI 设置元数据：总开关、provider preference、
本地/远程路线开关、privacy gate 引用和四个功能开关。成功后返回更新后的
`AiConfigSnapshot`，让 S3-01/S3-09 直接刷新设置状态和禁用原因。

约束：

- `newConfig.repo_path` 必须等于 `repoPath`。
- `feature_toggles` 必须包含且只包含 C3-01 四个功能：
  `ClassificationSuggestions`、`AutoSummaries`、`AutoTags`、`SemanticSearch`。
- 该 API 不接受 API key、provider endpoint、model id、prompt、用户文件路径列表或文件内容。
- 启用远程路线只表达“允许后续 gate 考虑远程”；不测试远程 provider、不启用远程 provider、
  不调用模型、不上传数据。
- Pause all AI 可通过 `ai_enabled = false` 表达；清除未采纳建议和草稿属于后续清理能力，
  不由 C3-01 更新入口隐式执行。

错误与回滚：

- `Config`：payload repo mismatch、缺失/重复功能开关、隐私策略引用无效、持久化 schema 无效。
- `PermissionDenied`：AI settings metadata 写入或 inspection 被权限阻断。
- `Io`：AI settings metadata 读写失败。
- 任一失败必须保留上一次成功配置；不得留下部分保存导致远程 gate 或功能开关与 UI 显示不一致。

副作用边界：

- 只允许写 AI settings metadata；不写用户文件，不写 `README.md` / `AREAMATRIX.md`，
  不写 generated overview，不修改 classifier、tags、notes、saved searches、change log、
  undo/redo、AI results 或 call log。
- 不删除 Keychain key，不保存 API key 明文，不把 key、key 片段、用户文件内容或完整路径写入
  日志、诊断、错误文案或返回值。
- 不实现 C3-02 本地模型状态、C3-03 远程 provider 配置、C3-05 调用日志、C3-09 隐私规则
  CRUD/evaluate、C3-10 fallback 或任何 AI 结果生成。

页面消费状态：

- S3-01 可以从返回快照更新总开关、功能开关、provider preference、远程 gate 摘要、
  禁用原因和保存失败后的回退基线。
- S3-09 可以更新 `privacy_gate_enabled` 并继续保持 provider 配置、Keychain key、
  `remote_provider_enabled` 和 `feature_scope` 不变；真正禁用 remote provider 只能走 S3-03。
- 本合同不新增 control map 之外的页面能力。

### `get_local_model_status(repoPath: String, request: LocalModelStatusRequest) throws -> LocalModelStatusSnapshot`

```swift
let status = try AreaMatrix.getLocalModelStatus(
    repoPath: repoPath,
    request: LocalModelStatusRequest(
        modelId: "areamatrix-local-classifier",
        storageLocation: modelFolder,
        cachedStatus: cachedStatus
    )
)
```

C3-02 的本地模型状态读取入口，服务 `S3-02 local-model-status`。输入
`LocalModelStatusRequest`：

- `model_id`：稳定本地模型标识，例如 `areamatrix-local-classifier`。
- `storage_location`：本地模型存储位置。该路径用于读取模型 manifest、目录 metadata、
  磁盘占用和 runtime 状态，不代表 Core 可以创建、下载、删除或训练模型。
- `cached_status`：可选缓存快照，用于首次打开、从失败提示进入和离线诊断展示。缓存必须属于
  同一 `model_id` 与 `storage_location`。

返回 `LocalModelStatusSnapshot`：

- `availability`：`Unknown`、`Ready`、`NotInstalled`、`PathUnreadable`、
  `VersionIncompatible`、`Checking`、`Verifying`、`Loading`、`Corrupted`、
  `RuntimeFailed` 或 `Error`。
- `version` / `size_bytes`：模型版本和磁盘占用，未知时为 `nil`。
- `last_error`：可展示的最后错误摘要；不得包含 API key、远程 provider 配置、用户文件正文或完整
  用户文件路径列表。
- `recommended_action`：`CheckStatus`、`RetryStatusCheck`、`OpenInstallHelp`、
  `OpenModelLocation`、`RunHealthCheck`、`RepairMetadata`、`OpenDiagnostics`、
  `UseNonAiFallback` 或 `None`。
- `last_checked_at`：最近检查时间，未知时为 `nil`。
- `diagnostics_summary`：本地诊断摘要，只包含模型 manifest 状态、runtime 启动状态、模型目录权限、
  磁盘空间和最后错误码；不得包含用户文件正文、完整文件路径列表、API key 或远程 provider 配置。
- `feature_statuses`：`ClassificationSuggestions`、`AutoTags`、`SemanticSearch` 等 S3-02 展示的
  本地模型功能支持状态。该字段只描述本地模型支持能力，不代表远程 provider 可用。

副作用边界：

- 状态检查只读本地模型 manifest、模型目录 metadata、磁盘占用、缓存状态和 runtime 健康 metadata。
- 不下载、安装、删除、训练模型，不改写模型权重，不读取用户文件内容，不调用远程 provider，
  不写 AI call log，不自动启用远程 fallback。
- 本地模型不可用时，调用方只能显示本地修复、安装帮助、诊断或非 AI 回退；不得把返回状态解释成
  允许启用远程 AI。
- 轻量 `RepairMetadata` 只是 UI 可展示的建议动作；实际 repair 行为必须由后续独立能力实现。

错误：

- `Config`：`repoPath`、`model_id`、`storage_location` 或 `cached_status` 无效，或本地模型
  metadata schema 不可用。
- `PermissionDenied`：模型目录、manifest、runtime 状态或 AreaMatrix-owned status cache 不可读。
- `Io`：读取模型 manifest、目录 metadata、磁盘占用或 runtime health metadata 失败。

页面消费状态：

- S3-02 可以从合同得到 Ready、Not installed、Path unreadable、Version incompatible、
  Checking、Verifying、Loading、Corrupted、Runtime failed、Error 和 Unknown 状态。
- S3-02 可以从 `recommended_action` 渲染 `Check status`、`Retry status check`、
  `Open install help`、`Open model location`、`Run health check`、`Repair`、`Open diagnostics`
  和非 AI 回退说明。
- S3-02 可以从 `diagnostics_summary` 打开本地诊断入口，但该入口只展示脱敏摘要，不提供远程
  provider、模型下载、删除缓存或训练能力。
- 本合同不新增 control map 之外的页面能力；S3-03 仍负责远程 provider/key/连接测试，C3-10 仍负责
  fallback 状态。

### `locate_local_model_folder(repoPath: String, request: LocalModelFolderRequest) throws -> LocalModelFolderLocation`

```swift
let location = try AreaMatrix.locateLocalModelFolder(
    repoPath: repoPath,
    request: LocalModelFolderRequest(
        modelId: "areamatrix-local-classifier",
        storageLocation: modelFolder
    )
)
```

C3-02 的本地模型目录定位入口，服务 S3-02 的 `Open model location`。返回
`LocalModelFolderLocation`：

- `folder_path`：平台层可尝试 reveal 的模型目录。
- `exists` / `readable` / `openable`：目录存在性、可读性和是否可由平台层打开。
- `unavailable_reason`：不可打开时的稳定原因，供按钮禁用文案和 VoiceOver 使用。

副作用边界：

- 该 API 只定位目录，不创建目录、不下载模型、不修复 metadata、不删除缓存、不训练模型、不读取
  用户文件内容，也不写入任何模型或 repository 文件。
- 路径不存在或不可读时返回结构化不可用原因或对应错误；调用方不得因为定位失败而创建、删除、
  移动、覆盖或重命名任何文件。

错误：

- `Config`：`repoPath`、`model_id` 或 `storage_location` 无效。
- `PermissionDenied`：模型目录无法 inspection。
- `Io`：目录 metadata 读取失败。

页面消费状态：

- S3-02 可以从 `exists`、`readable`、`openable` 和 `unavailable_reason` 决定
  `Open model location` 的启用、禁用和错误说明。
- 本合同不提供下载、删除、训练、远程 provider 或 fallback 能力。

### `test_remote_ai_provider(repoPath: String, request: RemoteProviderTestRequest) throws -> RemoteProviderTestResult`

```swift
let result = try AreaMatrix.testRemoteAiProvider(
    repoPath: repoPath,
    request: RemoteProviderTestRequest(
        provider: .openAi,
        modelId: "gpt-4.1-mini",
        endpointUrl: nil,
        keyReference: "keychain:remote-openai"
    )
)
```

C3-03 的远程 provider 连接测试入口，服务 S3-03 的 `Test connection`。输入只包含
provider、model、可选自定义 endpoint 和平台安全存储 key reference；不接受 API key 明文。

返回 `RemoteProviderTestResult`：

- `status`：`Succeeded`、`ProviderRejected`、`ConnectionFailed` 或 `UnsupportedProvider`。
- `provider_verified`：当前 provider/model/endpoint/key 组合是否通过测试。
- `verification_token`：测试成功后用于 enable 的不透明 token；不得包含 API key 或 key 片段。
- `sanitized_message`：可展示的脱敏结果说明；不得包含 provider 原始响应体、API key、用户文件正文
  或完整用户文件路径。

副作用边界：

- 测试连接只允许做最小 provider 可用性探测；不得发送文件名、repo-relative path、提取文本、
  note summary、tag/category context、prompt 或任何用户文件内容。
- 测试不得启用远程 provider，不保存 `feature_scope`，不修改 `privacy_gate_enabled`，不生成 AI 结果。
- 后续实现可按 C3-05 写脱敏 `Provider Test` 日志，sent fields 必须为 none；日志不得包含 key、
  key 片段或 provider 原始响应体。

错误：

- `Config`：`repoPath`、provider、model、endpoint 或 key reference 无效。
- `PermissionDenied`：平台安全存储中的 credential reference 不可访问。
- `Internal`：provider runtime 不可用或脱敏后的最小探测发生未归类失败。

页面消费状态：

- S3-03 可以从 `status`、`provider_verified` 和 `sanitized_message` 渲染连接成功、key 被拒绝、
  网络失败、unsupported provider 和 Enable 禁用原因。
- S3-09 不应从本合同开启 privacy gate；它只读取后续 enable 快照中的 provider 状态。

### `load_remote_ai_provider_config(repoPath: String) throws -> RemoteProviderConfigSnapshot`

```swift
let snapshot = try AreaMatrix.loadRemoteAiProviderConfig(repoPath: repoPath)
```

C3-03 的远程 provider 快照读取入口，服务 S3-03 打开 sheet 时读取已配置 provider，
也服务 S3-09 只读展示 provider consent 状态。

返回 `RemoteProviderConfigSnapshot`：

- `provider_configured`、`provider_verified`、`remote_provider_enabled`、`credential_configured`
  和 `feature_scope`：供 S3-03/S3-09 判断 provider gate。
- `provider`、`model_id`、`endpoint_url`：已保存的 provider metadata；不包含 API key 明文、
  key 片段或平台安全存储原始 secret。
- `disabled_reason`：远程不可用时供 S3-03/S3-09 展示的稳定原因。

副作用边界：

- 该 API 只读取 metadata，不测试 provider、不启用远程、不禁用远程、不修改 `privacy_gate_enabled`、
  不读取用户文件、不写 AI call log、不执行任何远程 AI 调用。
- 空配置返回 disabled 快照，不创建 provider、credential、scope 或 privacy rule。

错误：

- `Config`：`repoPath` 无效或持久化 metadata 无法解析。
- `Internal`：provider metadata 无法从已初始化仓库读取。

页面消费状态：

- S3-03 可以在打开配置 sheet 时恢复 provider/model/endpoint、credential presence、测试状态、
  enabled 状态和 scope。
- S3-09 可以只读展示 S3-03 的 provider 配置、测试状态、远程启用状态和 scope，但不得通过本合同
  开启或关闭 `privacy_gate_enabled`。

### `enable_remote_ai_provider(repoPath: String, request: RemoteProviderEnableRequest) throws -> RemoteProviderConfigSnapshot`

```swift
let snapshot = try AreaMatrix.enableRemoteAiProvider(
    repoPath: repoPath,
    request: RemoteProviderEnableRequest(
        provider: .openAi,
        modelId: "gpt-4.1-mini",
        endpointUrl: nil,
        keyReference: "keychain:remote-openai",
        featureScope: [.autoSummaries, .autoTags],
        verificationToken: result.verificationToken!,
        dataFlowConfirmed: true
    )
)
```

C3-03 的远程 provider 显式启用入口，服务 S3-03 的 `Enable remote AI`。输入必须包含
provider/model/key reference、非空 `feature_scope`、成功测试产生的 `verification_token` 和用户
数据流向确认。

返回 `RemoteProviderConfigSnapshot`：

- `provider_configured`：provider、model 或 endpoint 已保存。
- `provider_verified`：当前 provider/model/endpoint/key 组合已经通过测试；任一字段变化后必须重置。
- `remote_provider_enabled`：用户显式启用后的 provider gate。
- `credential_configured`：是否存在安全存储引用；不返回 API key 明文或片段。
- `feature_scope`：允许使用远程 provider 的功能范围，包含
  `ClassificationSuggestions`、`AutoSummaries`、`AutoTags` 或 `SemanticSearch`。
- `disabled_reason`：远程不可用时供 S3-03/S3-09 展示的稳定原因。

副作用边界：

- 该 API 只保存远程 provider metadata、Keychain reference 和 scope；API key 明文只允许在平台安全
  存储中处理，不进入 Core 返回值、日志、诊断或错误文案。
- 启用远程不会执行 AI 调用、发送用户内容、修改 privacy rules、编辑字段过滤、生成建议、写用户文件、
  清理 AI 结果或实现 fallback。
- `privacy_gate_enabled` 由 C3-09 管理；S3-03 首次成功启用时可以请求默认打开 gate，但该 gate 的持久化
  和规则评估仍属于 C3-09，不由本合同替代。

错误与回滚：

- `Config`：provider settings 无效、scope 为空或重复、verification token 无效、未确认数据流向。
- `PermissionDenied`：credential reference 或 provider metadata 无法 inspection。
- `Internal`：provider metadata 持久化或启用状态写入失败。
- 任一失败必须保留上一次成功的 remote provider state；已写入但未被启用的 credential 必须保持
  unused credential 状态，供 S3-03 提供 retry 或 cleanup。

页面消费状态：

- S3-03 可以从返回快照得到 `provider_configured`、`provider_verified`、
  `remote_provider_enabled`、`feature_scope`、credential presence 和禁用原因。
- S3-09 可以只读展示 provider 配置、测试状态、远程启用状态和 scope，并继续把
  `privacy_gate_enabled`、字段过滤和规则匹配作为独立 gate。
- 本合同不新增 control map 之外的页面能力；AI 调用日志属于 C3-05，隐私规则/evaluate 属于 C3-09，
  fallback 属于 C3-10。

### `disable_remote_ai_provider(repoPath: String, request: RemoteProviderDisableRequest) throws -> RemoteProviderConfigSnapshot`

```swift
let snapshot = try AreaMatrix.disableRemoteAiProvider(
    repoPath: repoPath,
    request: RemoteProviderDisableRequest(removeStoredCredential: false)
)
```

C3-03 的远程 provider 禁用入口，服务 S3-03 的 `Disable remote AI`。输入只包含用户是否勾选
`Also remove stored API key`；不接受 API key 明文。

返回禁用后的 `RemoteProviderConfigSnapshot`：

- `remote_provider_enabled` 必须为 false。
- 未删除 credential 时保留 `provider_configured`、`provider_verified`、credential presence 和
  `feature_scope`，方便用户之后重新启用前仍能看到已配置状态。
- 删除 credential 时 `credential_configured` 为 false，`provider_verified` 为 false，且
  `disabled_reason` 稳定说明 provider 未配置或需要重新测试。

副作用边界：

- 该 API 只关闭 C3-03 provider gate，并在用户显式选择时忘记 Core 中的 credential reference；
  真正 Keychain 删除由平台安全存储层执行并回传新的 reference 状态。
- 禁用远程不会删除本地 AI 设置、privacy rules、字段过滤、AI call log、已有摘要/标签/建议或任何用户文件。
- 该 API 不修改 `privacy_gate_enabled`；S3-03 成功禁用后关闭 privacy gate 的持久化仍由 C3-09 入口负责。

错误与回滚：

- `Config`：`repoPath` 无效或持久化 metadata 无法解析。
- `Internal`：provider metadata 持久化或禁用状态写入失败。
- 任一失败必须保留上一次成功的 remote provider state，不能写入半禁用状态。

页面消费状态：

- S3-03 可以从返回快照立即刷新 Off 状态和 credential presence。
- S3-09 继续只读展示 provider gate 状态；`Block remote AI with privacy gate` 不能被实现为本 API。
- 本合同不新增 control map 之外的页面能力；隐私 gate、日志、fallback 和 AI 调用仍由各自 C3 能力覆盖。

### `suggest_category_with_ai(repoPath: String, request: AiCategorySuggestionRequest) throws -> AiCategorySuggestion`

```swift
let suggestion = try AreaMatrix.suggestCategoryWithAi(
    repoPath: repoPath,
    request: AiCategorySuggestionRequest(
        fileId: file.id,
        contextPolicy: .limitedTextSummary,
        privacyPolicyRef: snapshot.config.privacyPolicyRef
    )
)
```

C3-04 的 AI 分类建议入口，服务 `S3-04 ai-classification-suggestion` 的
`Ask AI for suggestion...`，并为 `S3-10 ai-fallback` 提供可展示的 skipped /
unavailable 状态。输入是已初始化 `repoPath` 和一个 `AiCategorySuggestionRequest`：

- `file_id`：一个 active file row。后续实现必须拒绝缺失、删除态或不可访问的 file id。
- `context_policy`：调用方允许的最大上下文提取范围：
  `FileNameOnly`、`FileNameAndPath` 或 `LimitedTextSummary`。
- `privacy_policy_ref`：可选稳定隐私策略引用。规则内容和 CRUD 属于 C3-09，不内嵌在本请求。

返回 `AiCategorySuggestion`：

- `status`：`Suggested`、`NoSuggestion`、`Skipped` 或 `Unavailable`。
- `current_category` / `suggested_category`：当前分类和建议目标分类。只有
  `Suggested` 状态可包含建议目标分类。
- `confidence`：0.0 到 1.0 的置信度；低置信建议由 S3-04 弱化展示并禁止批量一键采纳。
- `reason`：脱敏、可展示的建议理由；不得包含 provider 原始响应、API key 或完整文件内容。
- `route`：`Local` 或 `Remote`，用于 S3-04 badge 和 S3-05 追溯。
- `used_context`：实际使用或允许展示的字段，包含 filename、extension、repo-relative path
  或 limited text summary。
- `skipped_reason`：`AiDisabled`、`FeatureDisabled`、`RuleResultConfident`、
  `NoEligibleContext`、`PrivacyRule` 或 `ProviderUnavailable`。
- `privacy_rule_id` / `call_log_id`：供页面跳转隐私规则和调用日志；具体日志读写属于 C3-05，
  隐私规则详情属于 C3-09。
- `requires_user_confirmation`：必须为 true。后续采纳、修改、拒绝、移动确认或规则沉淀不由本 API
  隐式执行。

副作用边界：

- 本 API 只生成建议草稿；不得写 `files.category`，不得移动、删除、重命名、覆盖用户文件，
  不得保存 classifier rule，不得执行 S2-17/S2-18 规则沉淀，也不得替代分类纠错入口。
- 自动触发只能发生在规则分类失败、进入 inbox 兜底或低置信度时；高置信规则结果必须返回
  `NoSuggestion` / `RuleResultConfident`，而不是覆盖规则分类。
- 远程路线必须同时通过 C3-01 AI settings、C3-03 remote provider gate、C3-09 privacy gate、
  feature scope 和调用日志 gate；本 API 不启用远程 provider，不保存 API key，不绕过隐私规则。
- 隐私规则命中时必须返回 `Skipped` / `PrivacyRule`，`used_context` 为空或只包含允许展示字段，
  sent fields 由后续 C3-05 日志记录为 none。
- 失败或跳过不得改变文件、分类、标签、摘要、notes、saved searches、change log、undo/redo、
  generated overview 或任何用户文件。

错误：

- `Config`：`repoPath`、`file_id`、`context_policy`、`privacy_policy_ref` 或 AI gate 配置无效；
  AI 关闭或功能关闭也可返回结构化 `Skipped`，由实现阶段按 UX 需要选择。
- `PermissionDenied`：repository metadata、允许的上下文字段、本地模型状态或 provider credential
  reference 无法 inspection。
- `Internal`：AI runtime、provider adapter、脱敏后的模型执行或结果解析发生未归类失败。

页面消费状态：

- S3-04 可以从合同得到当前分类、建议分类、confidence、reason、local/remote route、
  used context、privacy skipped、call log id、privacy rule id 和“必须确认后才能写入”的状态。
- S3-10 可以从 `status`、`skipped_reason`、`route` 和 `call_log_id` 渲染 AI off、provider
  unavailable、privacy skipped、local/remote failure 和非 AI 回退入口。
- 本合同不新增 control map 之外的页面能力；AI 调用日志仍由 C3-05 覆盖，隐私规则由 C3-09
  覆盖，fallback reason matrix 由 C3-10 覆盖，分类采纳/移动仍复用对应分类与文件操作能力。

### `list_ai_calls(repoPath: String, filter: AiCallLogFilter, pagination: AiCallLogPagination) throws -> AiCallLogPage`

```swift
let page = try AreaMatrix.listAiCalls(
    repoPath: repoPath,
    filter: AiCallLogFilter(
        feature: .classification,
        route: .remote,
        status: nil,
        occurredAfter: nil,
        occurredBefore: nil,
        searchQuery: nil
    ),
    pagination: AiCallLogPagination(limit: 50, offset: 0)
)
```

C3-05 的 AI 调用日志读取入口，服务 `S3-05 ai-call-log` 的表格、详情、过滤、
从 `View AI call` 进入时的定位，以及导出前的脱敏数据来源。输入：

- `AiCallLogFilter.feature`：`Classification`、`Summary`、`Tags`、`SemanticSearch`、
  `ProviderTest` 或空值。
- `AiCallLogFilter.route`：`Local`、`Remote` 或空值。隐私 skipped、provider gate
  unavailable 等未选择 route 的记录仍可在空 route 过滤下返回。
- `AiCallLogFilter.status`：`Success`、`Failed`、`Skipped`、`Unavailable` 或空值。
- `occurred_after` / `occurred_before`：按调用时间过滤，前者 inclusive，后者 exclusive。
- `search_query`：仅匹配脱敏字段，例如文件显示名、provider、model 或错误码。
- `AiCallLogPagination.limit` / `offset`：分页；`limit` 必须在 1..200 内。

返回 `AiCallLogPage`：

- `records`：按 `occurred_at` 倒序排列的脱敏日志行。
- `total_count`、`limit`、`offset`、`has_more`：供表格分页和过滤空态使用。
- `retention_days`：默认本地保留策略，当前为 90 天。
- `redaction_policy`：导出确认 UI 可展示的脱敏规则摘要。

`AiCallLogRecord` 只暴露 S3-05 需要的状态：

- `feature`、`route`、`provider_name`、`model_name`、`status`、`duration_ms`、`error_code`。
- `file_id`、`file_display_name`、`batch_id`、`scope`。Provider Test 记录固定可表达
  `feature = ProviderTest`、`scope = Provider verification`、无文件或批次。
- `sent_fields` 只包含字段类型：`FileName`、`RepoRelativePath`、`Extension`、
  `ExtractedTextExcerpt`、`AiSummary`、`NoteSummary`、`TagCategoryContext`。
- `privacy_rules_checked`、`privacy_rule_id`、`privacy_rule_name`、`matched_field_type`。
- `result_summary` 是脱敏摘要，不得包含完整 prompt、完整输出或原始 provider 响应。

隐私和副作用边界：

- 不返回 API key、key 片段、Keychain 引用值、完整文件正文、完整 prompt、完整模型输出、
  完整用户 Note、provider 原始响应体、绝对路径用户名或未脱敏诊断。
- 读取日志不得执行 AI 调用、导出文件、打开 Finder、清除日志、修改 AI 设置、修改 provider
  配置、编辑隐私规则、删除 AI 结果或触碰用户文件。
- 隐私规则命中记录必须能表达 `Skipped`、sent fields none、rule id/name、feature、
  file/batch、provider gate 和 result `No AI call was made`。

错误：

- `Db`：filter/pagination 无效，`ai_call_log` schema 或 SQLite 查询失败。
- `PermissionDenied`：repository metadata 或 SQLite 文件不可读。

页面消费状态：

- S3-05 可以从合同得到加载成功后的表格、详情、过滤空态、远程标记、隐私 skipped 说明、
  Provider Test 详情和默认 90 天保留说明。
- S3-03/S3-04/S3-06/S3-07/S3-08/S3-09/S3-10 只能通过 `call_log_id` 或过滤条件跳转到
  S3-05；本合同不提供这些页面的 AI 生成、隐私规则 CRUD、fallback 或 provider enable 能力。
- 本合同不新增 control map 之外的页面能力。

### `clear_ai_call_log(repoPath: String, request: AiCallLogClearRequest) throws -> AiCallLogClearReport`

```swift
let report = try AreaMatrix.clearAiCallLog(
    repoPath: repoPath,
    request: AiCallLogClearRequest(scope: .all, entryIds: [], olderThan: nil)
)
```

C3-05 的 AI 调用日志清理入口，服务 S3-05 的 `Clear log...`、`Delete selected`
和本地保留策略执行。输入：

- `scope = All`：清除所有本地 AI 调用日志，`entry_ids` 必须为空，`older_than` 必须为空。
- `scope = SelectedEntries`：只删除选中的 log row id，`entry_ids` 必须非空、正数且最多 500 个。
- `scope = OlderThan`：删除早于 `older_than` 的日志，`entry_ids` 必须为空。

返回：

- `deleted_count`：删除的日志行数。
- `remaining_count`：清理后剩余日志行数。
- `cleared_at`：完成清理的 Unix 秒级时间。

副作用边界：

- 只删除 `ai_call_log` 或等价审计表中的本地日志行。
- 不删除、移动、重命名、Trash、覆盖或重新分类用户文件。
- 不删除 AI 结果、tags、summaries、notes、AI settings、provider metadata、Keychain/API key、
  privacy rules、classifier rules、change log、undo/redo、generated overview 或导出文件。
- 清理失败必须保留可观察错误，不得静默吞错；失败不得影响用户文件。

错误：

- `Db`：clear scope、selected ids 或 retention cutoff 无效，或 SQLite 删除失败。
- `PermissionDenied`：repository metadata 或 SQLite 文件不可写。

页面消费状态：

- S3-05 可以从 `deleted_count`、`remaining_count` 和 `cleared_at` 刷新空态、toast 和表格。
- 本合同不实现 redacted export、保存面板、Reveal file、AI 调用执行或相邻页面能力。

### `generate_ai_summary(repoPath: String, request: AiSummaryGenerationRequest) throws -> AiSummaryDraft`

```swift
let draft = try AreaMatrix.generateAiSummary(
    repoPath: repoPath,
    request: AiSummaryGenerationRequest(
        fileId: file.id,
        providerScope: .localPreferred,
        contextPolicy: .metadataAndExtractedText,
        privacyPolicyRef: snapshot.config.privacyPolicyRef,
        regenerateExisting: false
    )
)
```

C3-06 的 AI 摘要草稿生成入口，服务 `S3-06 ai-summary-editor` 的
`Generate summary` 和确认后的 `Regenerate...`。输入是已初始化 `repoPath` 和一个
`AiSummaryGenerationRequest`：

- `file_id`：一个 active file row。后续实现必须拒绝缺失、删除态或不可访问的 file id。
- `provider_scope`：`LocalOnly`、`LocalPreferred` 或 `RemoteAllowed`，只表达本次生成允许的
  provider 路线；远程仍必须经过 C3-01、C3-03 和 C3-09 gate。
- `context_policy`：`MetadataOnly`、`MetadataAndExtractedText` 或
  `MetadataTextAndNotes`，表示调用方允许的最大上下文字段集合。
- `privacy_policy_ref`：可选稳定隐私策略引用。规则内容和 CRUD 属于 C3-09，不内嵌在本请求。
- `regenerate_existing`：调用方已完成 Regenerate 二次确认时为 true；取消确认不得调用本 API。

返回 `AiSummaryDraft`：

- `status`：`Draft`、`Skipped` 或 `Unavailable`。
- `summary_text`：生成的摘要草稿。只有 `Draft` 状态可包含文本，用户点击 Save 前不得持久化。
- `draft_id`：不透明草稿 id，供 save 时关联同一生成结果；不得包含 prompt、文件内容或 provider
  原始响应。
- `route`：`Local` 或 `Remote`，用于来源 badge 和 AI 调用日志追溯。
- `model_name`：脱敏模型或 provider 展示名，不得包含 API key、key 片段或原始 provider 响应。
- `generated_at`：草稿生成时间，未知时为 nil。
- `used_context`：实际使用或允许展示的字段类型，包含 filename、repo-relative path、
  extracted text excerpt、existing AI summary、note summary、tag/category context。
- `skipped_reason`：`AiDisabled`、`FeatureDisabled`、`ProviderUnavailable`、`PrivacyRule`、
  `NoEligibleInput` 或 `CallLogUnavailable`。
- `privacy_rule_id` / `call_log_id`：供页面跳转隐私规则和调用日志；具体日志读写属于 C3-05，
  隐私规则详情属于 C3-09。
- `requires_user_save`：必须为 true。生成结果默认是草稿，不能直接写正式摘要。
- `character_count`：摘要长度，供 S3-06 字数提示和 VoiceOver 文案使用。

副作用边界：

- 本 API 只生成摘要草稿；不得保存正式摘要，不得覆盖用户 Note，不得写入或修改用户原文件，
  不得修改 tags、categories、saved searches、generated overview、change log 或 undo/redo。
- `Regenerate...` 只能在 UI 已确认后调用；若 gate 失败，必须保留现有草稿或已保存摘要。
- 远程路线必须同时通过 C3-01 AI settings、C3-03 remote provider gate、C3-09 privacy gate、
  feature scope 和 C3-05 call-log gate；本 API 不启用远程 provider，不保存 API key，不绕过隐私规则。
- 隐私规则命中时必须返回 `Skipped` / `PrivacyRule`，`used_context` 为空或只包含允许展示字段；
  sent fields 由后续 C3-05 日志记录为 none。
- 失败、跳过或取消不得改变文件、摘要、notes、tags、分类、AI settings、provider metadata、
  privacy rules、AI call log、generated overview 或任何用户文件。

错误：

- `Config`：`repoPath`、`file_id`、`provider_scope`、`context_policy`、`privacy_policy_ref` 或
  AI gate 配置无效；AI 关闭或功能关闭也可返回结构化 `Skipped`，由实现阶段按 UX 需要选择。
- `FileNotFound`：目标 file id 不存在、已删除或后续实现无法找到对应 active file metadata。
- `PermissionDenied`：repository metadata、允许的上下文字段、本地模型状态或 provider credential
  reference 无法 inspection。
- `Db`：summary metadata、AI call log gate 或相关 repository metadata 读取/写入失败。

页面消费状态：

- S3-06 可以从合同得到 Draft、Generated locally/remotely、model、generated time、used fields、
  skipped by privacy rule、call log id、privacy rule id、character count 和“必须 Save 才能持久化”的状态。
- S3-10 可以从 `status`、`skipped_reason`、`route` 和 `call_log_id` 渲染摘要生成的 AI off、
  provider unavailable、privacy skipped、local/remote failure 和非 AI 回退入口。
- 本合同不新增 control map 之外的页面能力；隐私规则由 C3-09 覆盖，AI 调用日志由 C3-05
  覆盖，fallback reason matrix 由 C3-10 覆盖，多文档摘要和知识库摘要属于后续阶段。

### `save_ai_summary(repoPath: String, request: AiSummarySaveRequest) throws -> AiSummarySaveReport`

```swift
let report = try AreaMatrix.saveAiSummary(
    repoPath: repoPath,
    request: AiSummarySaveRequest(
        fileId: file.id,
        summaryText: draftText,
        draftId: draft.draftId,
        route: draft.route,
        modelName: draft.modelName,
        generatedAt: draft.generatedAt,
        usedContext: draft.usedContext,
        privacyRuleId: draft.privacyRuleId,
        callLogId: draft.callLogId,
        editedByUser: true
    )
)
```

C3-06 的 AI 摘要保存入口，服务 S3-06 的 `Save`、`Retry save` 和保存后来源信息刷新。输入：

- `file_id`：一个 active file row。
- `summary_text`：要保存的摘要文本，可来自 AI 草稿或用户编辑后的草稿；不能为空，也不得超出实现
  定义的长度上限。
- `draft_id`：生成入口返回的不透明草稿 id；没有 AI 生成来源时可为空。
- `route` / `model_name` / `generated_at` / `used_context`：保存后的来源信息，只存脱敏 provenance。
- `privacy_rule_id` / `call_log_id`：用于跳转隐私规则和 AI 调用日志。
- `edited_by_user`：用户是否编辑过 AI 草稿，用于 `Edited by you` 状态。

返回 `AiSummarySaveReport`：

- `saved_summary`：持久化后的摘要文本，供编辑区刷新和失败恢复基线使用。
- `saved_at`：保存完成时间。
- `route`、`model_name`、`generated_at`、`used_context`、`privacy_rule_id`、`call_log_id`、
  `edited_by_user`：保存后的来源和追溯字段。
- `character_count`：保存摘要长度，供 S3-06 计数器、状态文案和 VoiceOver 使用。

副作用边界：

- 只允许保存 AreaMatrix-owned summary metadata；不得覆盖用户 Note，不得写入、删除、移动、重命名、
  Trash 或覆盖用户原文件。
- 不删除 extracted text、tags、AI call log、AI settings、provider metadata、Keychain/API key、
  privacy rules、classifier rules、change log、undo/redo 或 generated overview。
- 保存失败必须保留草稿内容和上一次已保存摘要；不得写入半成品导致 UI 无法恢复。
- 本 API 不生成摘要、不发起 AI 调用、不启用远程 provider、不编辑隐私规则、不实现多文档摘要。

错误：

- `Config`：`repoPath`、`file_id`、`summary_text`、`draft_id` 或 provenance 字段无效。
- `FileNotFound`：目标 file id 不存在、已删除或后续实现无法找到对应 active file metadata。
- `PermissionDenied`：summary metadata 不可写。
- `Db`：summary metadata 或相关 repository metadata 持久化失败。

页面消费状态：

- S3-06 可以从返回值刷新保存成功后的摘要文本、Saved/Edited by you 状态、来源信息、字符数、
  View AI call 和 View privacy rule 链接。
- 本合同不新增 control map 之外的页面能力。

### `clear_ai_summary(repoPath: String, request: AiSummaryClearRequest) throws -> AiSummaryClearReport`

```swift
let report = try AreaMatrix.clearAiSummary(
    repoPath: repoPath,
    request: AiSummaryClearRequest(fileId: file.id, confirmed: true)
)
```

C3-06 的 AI 摘要清除入口，服务 S3-06 的 `Clear summary...` 确认 sheet。输入：

- `file_id`：一个 active file row。
- `confirmed`：调用方已经展示并确认 `Clear AI summary?`；为 false 必须返回结构化 `Config` 错误。

返回：

- `cleared`：是否确实清除了已保存摘要。
- `cleared_at`：清除完成时间。

副作用边界：

- 只清除 AreaMatrix-owned AI summary metadata。
- 不删除、移动、重命名、Trash、覆盖或重新分类用户文件。
- 不删除用户 Note、extracted text、tags、AI call log、AI settings、provider metadata、Keychain/API key、
  privacy rules、classifier rules、change log、undo/redo 或 generated overview。
- 清除失败必须保留原已保存摘要和来源信息；不得静默吞错。

错误：

- `Config`：`repoPath`、`file_id` 无效，或缺少确认。
- `FileNotFound`：目标 file id 不存在、已删除或后续实现无法找到对应 active file metadata。
- `PermissionDenied`：summary metadata 不可写。
- `Db`：summary metadata 或相关 repository metadata 持久化失败。

页面消费状态：

- S3-06 可以从 `cleared` 和 `cleared_at` 刷新 `No AI summary yet.` 空态、toast 和来源信息隐藏。
- 本合同不实现 Note 清除、文件删除、日志清理、隐私规则编辑、AI 调用执行或相邻页面能力。

### `recover_on_startup(repoPath: String) throws -> RecoveryReport`

```swift
@MainActor
func bootstrap(repoPath: String) async throws {
    let report = try await Task.detached(priority: .userInitiated) {
        try AreaMatrix.recoverOnStartup(repoPath: repoPath)
    }.value

    if report.cleanedStagingFiles > 0 || report.revertedStagingDbRows > 0 {
        await showRecoveryNotice(
            cleaned: report.cleanedStagingFiles,
            reverted: report.revertedStagingDbRows
        )
    }
}
```

应用启动必调（在 UI 显示前）。耗时与残留 staging 文件数成正比。

### `reindex_from_filesystem(repoPath: String) throws -> ReindexReport`

```swift
let report = try await Task.detached(priority: .background) {
    try AreaMatrix.reindexFromFilesystem(repoPath: repoPath)
}.value
print("inserted: \(report.inserted), updated: \(report.updated), skipped: \(report.skipped)")
```

耗时与文件数成正比（1 万文件 ≈ 30s）。建议显示进度条。该 API 会跳过 `.areamatrix/`、系统临时文件、可配置忽略目录，以及 AreaMatrix 自身生成的概览文件。

实现要求：

- 创建或复用 `scan_sessions(kind=Reindex)` 行，并在 `ReindexReport.scan_session_id` 返回。
- 启动后的全量重建或外部补扫写入 `FileEntry.origin = .external`。
- 首次接管扫描由 `init_repo(mode=.adoptExisting)` 的内部流程触发，写入 `FileEntry.origin = .adopted`。
- `README.md` 作为普通用户文件索引；`AREAMATRIX.md` 与 `.areamatrix/generated/` 始终跳过。

错误与副作用边界：

- `Db`：scan session、`files` metadata 或诊断状态读写失败。
- `PermissionDenied`：资料库文件、目录 metadata 或 `.areamatrix/` 写入被阻断。
- `Io`：文件系统遍历、metadata 读取或 hash 计算失败。
- `Internal`：重建过程发现无法恢复的一致性不变量破坏。
- 只允许写 `.areamatrix/index.db` 与 scan session metadata。
- 不移动、不重命名、不删除、不覆盖、不 Trash 用户文件。
- 不覆盖 `README.md`，不触发 iCloud placeholder 下载，不上传诊断。

### `create_diagnostics_snapshot(repoPath: String) throws -> DiagnosticsSnapshot`

```swift
let snapshot = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.createDiagnosticsSnapshot(repoPath: repoPath)
}.value
print(snapshot.snapshotPath)
```

C1-26 的只创建诊断入口。调用方在用户确认修复后、任何 metadata 修复前调用，
用于保留损坏 DB 或 repair context 的 AreaMatrix-owned 引用。返回的
`snapshot_path` 必须位于 `.areamatrix/` 内，Swift 只展示引用，不解析用户文件。

输入：

- `repoPath`：已初始化资料库根目录。

输出：

- `DiagnosticsSnapshot.snapshot_path`：仓库相对路径，指向 `.areamatrix/` 下的诊断快照。
- `DiagnosticsSnapshot.created_at`：Unix 秒级时间戳。
- `DiagnosticsSnapshot.warnings`：无法完整采集但未破坏用户文件的诊断说明。

错误与副作用边界：

- `Db`：损坏 metadata 无法以诊断模式打开或读取。
- `PermissionDenied`：无法写入 `.areamatrix/` 诊断位置。
- `Io`：复制或读取诊断材料失败。
- `Internal`：诊断快照路径不在 `.areamatrix/` 内等不变量失败。
- 不修改 `files`、`scan_sessions` 或用户文件。
- 不写 `AREAMATRIX.md`、`README.md` 或 `.areamatrix/generated/`。
- 云端备份恢复和自动上传诊断不属于 Stage 1。

### `repair_metadata(repoPath: String, options: RepairOptions) throws -> RepairReport`

```swift
let report = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.repairMetadata(
        repoPath: repoPath,
        options: RepairOptions(
            fullRescan: true,
            preserveDiagnosticsSnapshot: true
        )
    )
}.value
```

C1-26 的用户确认后 metadata repair 入口。`RepairOptions.full_rescan = true`
表示执行全量 filesystem rescan 并返回 `scan_session_id`；`false` 只允许执行
metadata 层可恢复修复。`preserve_diagnostics_snapshot = true` 时，修复前必须先
保留诊断快照，并在 `RepairReport.diagnostics_snapshot_path` 返回引用。

输入：

- `repoPath`：已初始化资料库根目录。
- `RepairOptions.full_rescan`：是否执行全量重建。
- `RepairOptions.preserve_diagnostics_snapshot`：是否先保留损坏状态诊断引用。

输出：

- `RepairReport.scan_session_id`：全量重建对应的 scan session，非全扫可为空。
- `RepairReport.diagnostics_snapshot_path`：修复前保留的诊断快照引用，可为空。
- `inserted` / `updated` / `skipped` / `errors`：与 metadata 修复或全扫相关的结构化摘要。

错误与副作用边界：

- `Db`：SQLite 损坏、schema 读取、metadata upsert 或 scan session 持久化失败。
- `PermissionDenied`：`.areamatrix/` 诊断、DB 或 metadata 写入被阻断。
- `Io`：文件系统遍历、诊断材料复制或 metadata 读取失败。
- `Internal`：修复后 DB/FS 一致性检查无法满足。
- 修复只处理 `.areamatrix/` metadata；不移动、不重命名、不删除、不覆盖用户文件。
- 修复失败不得删除用户文件，也不得清空已生成的诊断信息。
- 成功后 Tree/List 可通过 `list_tree_json` / `list_files` 重新加载。

### `get_latest_scan_session(repoPath: String) throws -> ScanSession?`

返回最近一次未完成或刚完成的接管 / 重建扫描，用于首次启动向导恢复状态。

### `resume_scan_session(repoPath: String, scanSessionId: Int64) throws -> ReindexReport`

继续 `Paused` / `Interrupted` / `Failed` 的扫描。Core 需要按 `last_path` 与幂等 upsert 规则续扫；若 session 已 `Completed`，返回空 report。

---

## classify API

### `predict_category(repoPath: String, filename: String) throws -> ClassifyResult`

```swift
let result = try AreaMatrix.predictCategory(
    repoPath: repoPath,
    filename: "Invoice_2026Q1.pdf"
)
// result.category == "finance"
// result.reason == .keyword
// result.confidence == 0.9

importSheet.suggestedCategory = result.category
importSheet.confidence = result.confidence
```

无写入副作用：只读取 `.areamatrix/classifier.yaml`，不创建、不移动、
不删除文件，也不写 DB。UI 在拖入时调用以填充 ImportSheet。

错误：

- `Config`：`repoPath` / `filename` 为空，或 `classifier.yaml` 的 YAML 语法、
  schema、default category、slug、extension、keyword 无效。
- `Classify`：classifier 规则源无法作为文件读取，分类引擎无法产生可用预览。

---

## storage API

### `import_file(repoPath, sourcePath, options) throws -> FileEntry`

```swift
func importDroppedFile(_ url: URL) async {
    let options = ImportOptions(
        mode: appState.config.defaultMode,
        destination: .autoClassify,
        targetDirectory: nil,
        overrideCategory: nil,
        overrideFilename: nil,
        duplicateStrategy: .skip
    )

    do {
        let entry = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.importFile(
                repoPath: repoPath,
                sourcePath: url.path,
                options: options
            )
        }.value
        appState.appendFile(entry)
    } catch CoreError.DuplicateFile(let existing) {
        let choice = await showDuplicateDialog(existingPath: existing)
        if choice == .keepBoth {
            var opts = options
            opts.duplicateStrategy = .keepBoth
            try await Task.detached {
                try AreaMatrix.importFile(repoPath: repoPath, sourcePath: url.path, options: opts)
            }.value
        }
    } catch CoreError.InvalidPath(let p) {
        await showAlert("文件名不允许：\(p)")
    } catch CoreError.ICloudPlaceholder(let p) {
        await showICloudDownloadPrompt(path: p)
    } catch {
        await showAlert("导入失败：\(error.localizedDescription)")
    }
}
```

可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath` / `ICloudPlaceholder` / `Internal`。

`ImportOptions.destination` 语义：

| destination | 使用字段 | 目标规则 |
|---|---|---|
| `AutoClassify` | `override_category` 可选 | 根据 classifier 推断；低置信或无命中进 `inbox/` |
| `SelectedDirectory` | `target_directory` 必填 | 放入用户显式 drop 的目录，不再自动分类 |
| `Category` | `override_category` 必填 | 放入指定系统分类目录，必要时创建 `<slug>/` |

### `delete_file(repoPath, fileId) throws`

```swift
func deleteFile(_ entry: FileEntry) async {
    do {
        try await Task.detached {
            try AreaMatrix.deleteFile(
                repoPath: repoPath,
                fileId: entry.id
            )
        }.value
        appState.removeFile(id: entry.id)
    } catch CoreError.FileNotFound(let path) {
        appState.removeFile(id: entry.id)
        print("file already gone: \(path)")
    } catch {
        await showAlert("删除失败：\(error.localizedDescription)")
    }
}
```

`delete_file` 是用户确认后的 repo-owned 删除入口：仅用于 `Copied` / `Moved`
等 AreaMatrix 管理的 active 条目。成功时 Core 必须把目标文件移入系统 Trash，
将对应 metadata 标记为 `files.status = deleted`，刷新 `deleted_at` / `updated_at`，
并写入 `change_log.action = deleted`。

副作用边界：

- 不提供永久删除参数，不直接物理删除目标文件。
- 不删除、移动、重命名或覆盖任何其他用户文件。
- 不清空 notes / tags 等关联 metadata。
- Indexed、Adopted、External 或 Missing 条目的索引移除必须使用
  `remove_index_entry`。

错误：

- `FileNotFound`：`fileId` 对应的 active row 不存在，或 repo-owned 文件已消失。
- `PermissionDenied`：系统 Trash、目标文件或 metadata 写入被权限阻断。
- `Io`：Trash 或文件系统操作失败。
- `Db`：SQLite 查询、软删除或 change log 写入失败。
- `Internal`：Trash 适配或状态转换出现未预期错误。

### `remove_index_entry(repoPath, fileId) throws`

```swift
func removeIndexEntry(_ entry: FileEntry) async {
    do {
        try await Task.detached {
            try AreaMatrix.removeIndexEntry(
                repoPath: repoPath,
                fileId: entry.id
            )
        }.value
        appState.removeFile(id: entry.id)
    } catch CoreError.FileNotFound(let path) {
        appState.removeFile(id: entry.id)
        print("index entry already gone: \(path)")
    } catch {
        await showAlert("移除索引失败：\(error.localizedDescription)")
    }
}
```

`remove_index_entry` 是 index-only 删除入口：用于 Indexed / Adopted / External
或 Missing metadata，不移动、不删除、不重命名、不覆盖、不 Trash 外部源文件。
成功时 Core 只更新 metadata，使该条目不再出现在默认 list/detail 中，并写入
`change_log.action = removed_from_index`。

副作用边界：

- 不触碰外部源文件，即使 `files.source_path` 指向的文件存在。
- 不触发 iCloud placeholder 下载。
- 不删除 notes / tags 等关联 metadata，除非后续恢复/清理 task 明确扩展。
- 不替代 Finder/FSEvents 外部删除同步；外部 removed 仍属于
  `sync_external_changes`。

错误：

- `FileNotFound`：`fileId` 对应的 removable active row 不存在。
- `PermissionDenied`：metadata 写入被权限阻断。
- `Db`：SQLite 查询、索引移除或 change log 写入失败。
- `Internal`：状态转换出现未预期错误。

### `rename_file(repoPath, fileId, newName) throws -> FileEntry`

```swift
let updated = try await Task.detached {
    try AreaMatrix.renameFile(
        repoPath: repoPath,
        fileId: entry.id,
        newName: "新名字.pdf"
    )
}.value
appState.replaceFile(updated)
```

`newName` 是文件名而不是路径，使用与 `ImportOptions.override_filename` 相同的校验边界。
空名、路径分隔符、metadata 内部路径或禁用字符（`/ \\ : * ? " < > |`）会抛
`InvalidPath`。

副作用边界：

- Copy / Move 等 repo-owned 文件只在当前目录内执行安全 rename，更新
  `files.path`、`files.current_name`、`updated_at`，并写入 `change_log.action =
  renamed`。
- Indexed 文件只更新 `files.current_name` 和 change log，保留 `files.path`、
  `files.source_path`，且不移动、重命名或覆盖外部源文件。
- 成功 rename 不改变 `file_id`、category、tags、notes、hash、storage mode、origin
  或 source path。
- 同目录同名时复用 C1-10 的安全编号策略，不覆盖已有文件；只有编号耗尽或竞态无法
  解析时抛 `Conflict`。
- Copy / Move rename 成功后触发 C1-20 generated overview 再生成；默认只写
  `.areamatrix/generated/**`，仅当配置显式允许时维护根目录 `AREAMATRIX.md`，
  不触碰用户 `README.md`。Indexed display-name rename 不触发文件系统 rename，也不
  触碰外部源文件。

错误：

- `InvalidPath`：`repoPath` 或 `newName` 为空、不安全，或命中 metadata 内部路径。
- `FileNotFound`：`fileId` 对应的 active row 不存在，或 repo-owned 文件已消失。
- `Conflict`：安全目标名无法解析。
- `PermissionDenied`：文件系统 rename 或 metadata 写入被权限阻断。
- `Io`：文件系统读写失败。
- `Db`：SQLite 查询、更新或 change log 写入失败。
- `Config`：generated overview 输出配置无效。

### `preview_move_to_category(repoPath, fileId, newCategory) throws -> MoveToCategoryPreview`

```swift
let preview = try await Task.detached {
    try AreaMatrix.previewMoveToCategory(
        repoPath: repoPath,
        fileId: entry.id,
        newCategory: "finance"
    )
}.value
targetPathLabel = preview.targetPath
```

`preview_move_to_category` 是 C1-24 的确认前目标路径解析入口。输入与
`move_to_category` 相同，输出 `MoveToCategoryPreview`，包含原分类、目标分类、
当前路径、确认后最终路径、最终文件名、storage mode、是否 Index-only、是否因
C1-10 自动编号改名、确认后是否会移动 repo-owned 文件。

该函数只允许读取 classifier、DB 和文件系统状态。它必须复用
`move_to_category` 的目标路径解析、同名编号、repo-owned / Indexed 分流和
错误映射，但不得创建分类目录、移动文件、重命名文件、删除文件、更新
`files` 或写入 `change_log`。S1-35 的 `Cancel` 和目标分类下拉预检必须使用此
类无副作用路径，不能用会写入的 `move_to_category` 代替 preview。

副作用边界：

- Copy / Move 等 repo-owned 文件返回确认后将使用的 repository-relative
  `target_path` 和 `target_name`；目标分类目录尚不存在时也只计算路径，不创建目录。
- 同名目标按 C1-10 安全编号策略解析，`name_conflict_resolved = true` 时 UI 必须
  展示最终名称，不得假设原文件名会被保留。
- Indexed 文件返回原 `path` / `current_name`，`index_only = true` 且
  `will_move_file = false`；不得移动、重命名或覆盖外部源文件。
- 目标分类等于当前分类时返回当前路径，`will_move_file = false`，由 UI 禁用确认按钮。

错误：

- `Classify`：目标分类不存在或 classifier 规则不可用。
- `FileNotFound`：`fileId` 对应的 active row 不存在，或 repo-owned 文件已消失。
- `Conflict`：目标分类路径不是目录、note sidecar 冲突，或安全目标名无法解析。
- `PermissionDenied`：文件系统或 metadata inspection 被权限阻断。
- `Io`：文件系统读取、路径存在性检查或 note sidecar 读取失败。
- `Db`：SQLite 查询失败。

### `move_to_category(repoPath, fileId, newCategory) throws -> FileEntry`

```swift
let moved = try await Task.detached {
    try AreaMatrix.moveToCategory(
        repoPath: repoPath,
        fileId: entry.id,
        newCategory: "finance"
    )
}.value
```

`move_to_category` 是 C1-24 的单文件改分类入口。输入是初始化后的
`repoPath`、active `fileId` 和目标分类 slug `newCategory`；输出是同一个
`file_id` 更新后的 `FileEntry`。`newCategory` 必须存在于
`.areamatrix/classifier.yaml` 或内置默认 classifier，否则抛 `Classify`，Core
不得隐式创建新分类。

副作用边界：

- Copy / Move 等 repo-owned 文件移动到目标分类目录，更新 `files.category`、
  `files.path`、`updated_at`，并写入 `change_log.action = moved`。
- 目标分类目录不存在时可创建该分类目录；同名目标按 C1-10 安全编号策略解析，
  不覆盖已有文件，编号耗尽或竞态无法解析时抛 `Conflict`。
- Indexed 文件只更新 `files.category`、`updated_at` 和 `change_log.moved`，
  保留 `files.path` / `files.source_path`，不移动、重命名或覆盖外部源文件。
- 成功改分类不改变 `file_id`、`original_name`、`current_name`、hash、storage
  mode、origin、source path、tags 或 notes。

错误：

- `Classify`：目标分类不存在或 classifier 规则不可用。
- `FileNotFound`：`fileId` 对应的 active row 不存在，或 repo-owned 文件已消失。
- `Conflict`：目标同名安全路径无法解析。
- `PermissionDenied`：文件系统移动或 metadata 写入被权限阻断。
- `Io`：文件系统读写失败。
- `Db`：SQLite 查询、更新或 change log 写入失败。

### `restore_file(repoPath, fileId) throws -> FileEntry`

```swift
let restored = try AreaMatrix.restoreFile(repoPath: repoPath, fileId: deletedEntry.id)
```

恢复软删除的文件。如果 FS 中文件已被废纸篓清空，抛 `FileNotFound`。

---

## query API

### `list_files(repoPath, filter) throws -> [FileEntry]`

```swift
let recent = try AreaMatrix.listFiles(
    repoPath: repoPath,
    filter: FileFilter(
        category: "finance",
        includeDeleted: false,
        importedAfter: nil,
        importedBefore: nil,
        limit: 200,
        offset: 0
    )
)
print("got \(recent.count) files")
```

按 `imported_at DESC` 排序。`limit > 1000` 自动 clamp。

### `search_files(repoPath, query, filter, sort, pagination) throws -> SearchResultPage`

```swift
let page = try AreaMatrix.searchFiles(
    repoPath: repoPath,
    query: "合同",
    filter: SearchFilter(
        scope: .allRepo,
        currentPath: nil,
        category: nil,
        fileKind: nil,
        tags: [],
        tagMatchMode: .any,
        importedAfter: nil,
        importedBefore: nil,
        modifiedAfter: nil,
        modifiedBefore: nil,
        storageMode: nil,
        includeDeleted: false
    ),
    sort: .newestImported,
    pagination: SearchPagination(limit: 50, offset: 0)
)
```

C2-01 的只读搜索入口，服务 `S2-01 search-results`、`S2-04 search-empty`
和 `S2-05 query-error`。输入包含原始 `query`、搜索范围、过滤条件、排序和分页。
输出 `SearchResultPage`：

- `query`：回显本次查询，便于 UI 在 debounce 与重试期间保持状态。
- `total_count`：分页前命中文件总数；为 `0` 且 diagnostics 没有 error 时进入搜索空态。
- `results`：每个 `SearchFileResult` 包含原有 `FileEntry`、相关性分数、命中字段和可高亮片段。
- `diagnostics`：结构化 query parse diagnostics，包含 `UnknownField`、`InvalidDate`、
  `UnclosedQuote`、`UnbalancedParentheses`、`InvalidOperator` 等，供 `S2-05`
  展示错误 token、位置和安全替换建议。
- `index_status`：`Ready`、`Indexing` 或 `Unavailable`，供搜索结果页和空态区分
  正常空结果、索引中、索引不可用。

搜索对象：

- 文件名、相对路径、伴生笔记、分类和 change log。
- 普通关键词支持大小写不敏感、fuzzy 和 pinyin initials 命中；高级查询字段不走模糊纠错。
- `SearchFilter` 必须携带当前 Stage 2 UI 的 C2-02 过滤状态，包括 tags 的
  Any/All 匹配模式和 storage mode。`search_files` 用同一份 filter 刷新真实结果，
  facet counts 仍由 C2-02 `list_filter_facets` 返回；保存搜索属于 C2-03，
  Smart List 执行属于 C2-04。

错误与副作用边界：

- `InvalidPath`：`repoPath` 或 `filter.current_path` 不合法或越过资料库边界。
- `Config`：query/filter/sort 配置无法解析或字段组合无效。
- `Db`：搜索索引、文件元数据、笔记或 change log 无法读取。
- 该 API 只读，不写 DB，不写 `change_log`，不创建或更新 FTS/索引表，不修改标签、分类、
  笔记、generated overview 或任何用户文件。
- OCR、文件内容全文、语义搜索和远程 AI 属于 Stage 3，不属于本合同。

### `list_filter_facets(repoPath, query) throws -> SearchFacets`

```swift
let facets = try AreaMatrix.listFilterFacets(
    repoPath: repoPath,
    query: SearchFacetQuery(
        query: "合同",
        scope: .allRepo,
        currentPath: nil,
        category: nil,
        fileKind: "pdf",
        tags: ["finance"],
        tagMatchMode: .any,
        importedAfter: nil,
        importedBefore: nil,
        modifiedAfter: nil,
        modifiedBefore: nil,
        storageMode: .copied,
        includeDeleted: false
    )
)
```

C2-02 的只读 filter/facet 入口，服务 `S2-02 search-filters`、`S2-08 tags-filter`
和 `S2-01 search-results` 中 C2-02 负责的过滤器状态。输入 `SearchFacetQuery`
承载当前搜索文本、scope/current path、category、file kind、tags、Any/All tag match mode、
imported/modified date range、storage mode 和 include deleted。输出 `SearchFacets`：

- `query`：回显本次 facet 查询对应的搜索文本。
- `total_count`：当前 query + filters 下匹配的文件总数。
- `categories`：category facet counts，供 Category 行显示可选项、选中态和 disabled 状态。
- `file_kinds`：file kind / extension facet counts，供 Type 行显示可选项、选中态和 disabled 状态。
- `tags`：tag facet counts，供 S2-08 显示标签列表、已选态、文件数量和 count 加载失败后的重试恢复。
- `storage_modes`：Copied / Moved / Indexed 等 storage mode facet counts。
- `date_bounds`：当前查询下可用 imported/modified timestamp 边界，供自定义日期控件限制范围。
- `active_filter_count`：不含原始 query 文本的 active filters 数量，供 Filters 按钮、chips 和 VoiceOver 读出状态。

错误与副作用边界：

- `Config`：filter state 无效，例如 CurrentNode 缺少合法 current path、category 为空、
  file kind 非法、tag 为空、date range 反转或字段组合无法表达。
- `Db`：读取文件元数据、tag/facet 统计或必要搜索索引失败。
- 该 API 只读，不写 DB，不写 `change_log`，不创建、更新、删除或重命名标签。
- 该 API 不保存搜索、不创建或执行 Smart List，不实现 C2-03 saved search CRUD 或
  C2-04 Smart List execution。
- 该 API 不修改 files、notes、categories、generated overview、repository metadata
  或任何用户文件；不会移动、删除、重命名文件，也不会触发 AI/语义过滤。

### `create_saved_search(repoPath, request) throws -> SavedSearch`

```swift
let saved = try AreaMatrix.createSavedSearch(
    repoPath: repoPath,
    request: CreateSavedSearchRequest(
        name: "Reports from 2026",
        query: SavedSearchQuery(
            query: "invoice OR receipt",
            filter: SearchFilter(
                scope: .allRepo,
                currentPath: nil,
                category: nil,
                fileKind: "pdf",
                tags: ["finance"],
                tagMatchMode: .any,
                importedAfter: nil,
                importedBefore: nil,
                modifiedAfter: nil,
                modifiedBefore: nil,
                storageMode: nil,
                includeDeleted: false
            ),
            sort: .newestModified
        ),
        icon: "magnifyingglass",
        color: nil,
        pinned: true
    )
)
```

C2-03 的保存搜索入口，服务 `S2-03 saved-search-sheet`。输入 `CreateSavedSearchRequest`
包含名称、`SavedSearchQuery`、可选 icon/color 和 sidebar pin 状态。`SavedSearchQuery`
保存原始 query、完整 `SearchFilter`（含 scope/current path/tags/storage mode/include deleted）
和 `SearchSort`，因此保存成功后 `S2-06 smart-lists` 可以从返回记录恢复同一搜索条件。

输出 `SavedSearch`：

- `id`：稳定 saved search 标识，供后续 update/delete 和 sidebar selection 使用。
- `name`：用户可见 Smart List 名称。
- `query`：可复现搜索的 query/filter/sort/scope 状态。
- `icon` / `color`：用户选择的显示元数据；不得表达 Stage 3/4 智能能力依赖。
- `pinned`：sidebar 固定状态。
- `created_at` / `updated_at`：排序、恢复和编辑 UI 使用的时间戳。

错误与副作用边界：

- `Config`：repoPath 为空、名称为空、名称超过 64 字符、名称重复、query parser
  diagnostics、filter state 无效、icon/color 元数据无效。
- `Db`：读取或写入 `saved_searches` 元数据失败。
- 该 API 只写 saved search 元数据；不写 `change_log`，不移动、复制、删除、重命名、
  retag、reclassify、reindex 或修改任何文件。
- 0 结果的有效搜索可以保存；query 无效时必须返回结构化 `Config`，不能写入半成品。
- 该 API 不执行 Smart List、不返回 `SearchResultPage`、不实现 C2-04 `run_smart_list`。
- 共享 Smart List、跨端同步、语义/AI Smart List 依赖属于后续阶段，不属于 C2-03。

### `update_saved_search(repoPath, request) throws -> SavedSearch`

更新已有 saved search 元数据，服务 `S2-06 smart-lists` 的 Rename、Duplicate 后编辑、
Pin、Icon/Color 和 Edit query 保存流程。输入 `UpdateSavedSearchRequest` 在
`CreateSavedSearchRequest` 的基础上增加 `id`，输出更新后的 `SavedSearch`。

约束：

- `id` 必须为正整数。
- `name` 校验、query/filter/sort 校验、icon/color 校验与创建入口一致。
- 名称重复必须失败，不自动覆盖其他 Smart List。
- `Save changes` 只更新当前 saved search；Duplicate 创建新记录应调用
  `create_saved_search`，不是复用 update 产生第二条记录。
- 成功后 UI 可以用返回的 `SavedSearch.query` 刷新当前搜索上下文，但本 API 本身不执行搜索。

错误与副作用边界：

- `Config`：id、repoPath、名称、query/filter/sort 或 display metadata 无效。
- `Db`：目标 saved search 不存在、名称重复或 metadata 持久化失败。
- 该 API 不创建/删除标签，不修改分类，不写 `change_log`，不移动、删除、重命名或复制文件。
- `Cancel` 和 `Reset changes` 不应调用本 API；draft 回滚由 UI/store 层处理。

### `delete_saved_search(repoPath, savedSearchId) throws`

删除一个 saved search 记录，服务 `S2-06 smart-lists` 的删除确认流程。

语义：

- 只删除 `saved_searches` 中的命名查询记录。
- 必须允许 UI 明确展示：`This only removes the Smart List. Files will not be deleted or moved.`
- 删除后同名未来可重新创建。

错误与副作用边界：

- `Config`：repoPath 为空或 `savedSearchId <= 0`。
- `Db`：目标记录不存在或 metadata 删除失败。
- 该 API 不删除、不移动、不重命名、不 trash、不 retag、不 reclassify、不 reindex 任何文件；
  即使当前 Smart List 有匹配结果，也不能触碰那些文件。
- 该 API 不写 `change_log`，因为它不代表文件动作。

### `list_saved_searches(repoPath) throws -> [SavedSearch]`

只读列出 saved search 元数据，服务 `S2-06 smart-lists` sidebar 分组、管理菜单、
空态/错误态、query 恢复提示和 command-palette 的 C2-04 发现前置数据。

排序：

- pinned first。
- pinned 内按 pin 时间或 updated_at 倒序。
- 非 pinned 按名称 A-Z。
- Stage 2 不支持拖拽排序，也不暴露手动排序字段。

错误与副作用边界：

- `Config`：repoPath 为空。
- `Db`：saved search metadata 无法读取。
- 该 API 只读，不执行 Smart List，不计算结果数量，不返回 `SearchResultPage`。
- Smart List 打开执行属于 C2-04；调用方需要拿到 `SavedSearch.query` 后显式调用搜索执行入口。

### `run_smart_list(repoPath, savedSearchId, pagination) throws -> SearchResultPage`

```swift
let page = try AreaMatrix.runSmartList(
    repoPath: repoPath,
    savedSearchId: saved.id,
    pagination: SearchPagination(limit: 50, offset: 0)
)
```

C2-04 的 Smart List 执行入口，服务 `S2-06 smart-lists` 点击进入搜索模式，以及
`S2-15 command-palette` 打开已保存 Smart List 的导航命令。输入只包含
`savedSearchId` 和分页；Core 从 saved search 记录读取已保存的 query、完整
`SearchFilter` 和 `SearchSort`，再返回与 `search_files` 相同的 `SearchResultPage`：

- `query`：回显 Smart List 保存的查询文本，供搜索 banner 显示 `Smart List: name` 时同步展示。
- `total_count` 和 `results`：当前保存查询的分页结果；0 结果进入 Smart List 空态。
- `diagnostics`：保存的查询或过滤条件已经失效时的结构化诊断，供 UI 显示 warning dot、
  `Edit query...` 和恢复提示。
- `index_status`：让 S2-06 区分正常结果、索引中、索引不可用和 API 失败。

错误与副作用边界：

- `Config`：`repoPath` 为空、`savedSearchId <= 0`、pagination 无效，或已保存的
  filter/sort 状态无法表达。
- `FileNotFound`：`savedSearchId` 没有对应 saved search 记录。
- `Db`：读取 saved search metadata、搜索索引、文件元数据、笔记或 change log 失败。
- 该 API 只读，不创建、更新、重命名、复制、pin 或删除 saved search 记录；这些仍属于
  C2-03。
- 该 API 不写 `change_log`，不移动、删除、重命名、trash、retag、reclassify、reindex、
  duplicate 或修改任何文件，不更新 generated overview 或用户文件。
- Command palette 只能用该 API 打开已存在 Smart List 的结果页；命令索引、最近命令、
  危险命令确认和 C2-11 command index 不属于本合同。
- Stage 2 不注册超出普通搜索字段的 Smart List；智能推荐、语义搜索、OCR 和远程 AI
  属于后续阶段。

### `list_command_targets(repoPath, context) throws -> CommandIndex`

```swift
let index = try AreaMatrix.listCommandTargets(
    repoPath: repoPath,
    context: CommandIndexContext(
        query: "tag",
        selectedFileIds: [10, 11],
        currentPath: "reports/2026",
        includeFileCandidates: true
    )
)
```

C2-11 的命令索引入口，服务 `S2-15 command-palette`。输入包含 `repoPath` 和当前
selection context，其中 context 承载命令搜索文本、当前选中文件 ID、当前路径和是否返回
文件候选。输出 `CommandIndex` 提供可执行命令、导航目标、当前选择命令、最近命令、
Smart List 和文件候选：

- `commands`：普通命令行，例如 Import、Open repository、Settings、Help。
- `navigation_targets`：Settings、Smart Lists、Needs Review 等导航入口。
- `current_selection_targets`：Rename、Add tags、Change category、Delete 等依赖当前选择的入口。
- `recent_targets`：最近使用的命令或导航目标。
- `smart_lists`：已保存 Smart List 的命令面板目标；打开结果页仍由 C2-04
  `run_smart_list` 执行。
- `file_candidates`：可聚焦的文件候选；只在 context 要求时返回，不搜索文件内容。
- 每个 `CommandTarget` 必须携带 `group`、`kind`、`action`、可选 `route`、可选
  `shortcut`、禁用状态和 `requires_confirmation`，让 UI 能显示分组、VoiceOver 文案、
  快捷键和确认边界。

错误与副作用边界：

- `Db`：读取命令 registry metadata、saved-search metadata、recent-command metadata
  或文件候选 metadata 失败。
- 该 API 是只读索引，不执行 Smart List；打开 Smart List 结果仍调用 C2-04
  `run_smart_list`。
- 危险命令只返回跳转确认或预览页的目标，必须设置 `requires_confirmation`，不得在命令
  面板中直接执行。
- 该 API 不移动、删除、重命名、retag、reclassify、redo、解决导入冲突、应用分类规则、
  写 recent-command 历史、调用 AI/网络 provider、修改 generated overview 或任何用户文件。
- 该 API 不实现插件命令市场，不注册 Stage 3 智能化、OCR、语义搜索或 Stage 4 多端命令。

### `add_tag(repoPath, fileId, tag) throws -> TagSet`

```swift
let tags = try AreaMatrix.addTag(
    repoPath: repoPath,
    fileId: entry.id,
    tag: "clientA"
)
detailView.updateTags(tags.fileTags)
```

C2-05 的单文件标签添加入口，服务 `S2-07 tags-add`。输入是已初始化
`repoPath`、active `fileId` 和用户输入或候选行提供的 `tag`。Core 负责对
tag 做 trim、大小写归一和非法字符校验；成功后返回 `TagSet`，让 UI 直接刷新
当前文件标签、候选列表、recent tags、已添加/禁用状态和更新时间。

输出 `TagSet`：

- `file_id`：本次操作对应的文件 ID。
- `file_tags`：当前文件添加后拥有的标签集合，按稳定顺序返回，供 Detail Meta
  chip 刷新。
- `available_tags`：仓库中可搜索/选择的 tag registry，包含 `file_count`、
  `selected`、`disabled` 和 `updated_at`，供 S2-07 候选列表和 S2-08 标签筛选入口使用。
- `recent_tags`：最近使用标签，供 S2-07 空输入状态显示。
- `updated_at`：本次 tag relation 变更后可见的最新时间戳。

错误与副作用边界：

- `InvalidPath`：`repoPath` 为空、位于 `.areamatrix/` 内部，或 `tag` 为空、超过
  64 个字符、包含路径分隔符、冒号或 NUL。
- `FileNotFound`：`fileId <= 0`，或没有对应 active file row。
- `Db`：读取或写入 `tags`、校验 active file、写入 `change_log` 失败。
- 重复添加同一标签必须幂等返回刷新后的 `TagSet`，不得写入重复 relation。
- 该 API 只写标签 metadata 和本次单文件关系的 `change_log`；不移动、不重命名、
  不删除、不 Trash、不改分类、不写 note、不 reindex、不更新 generated overview、
  不触发 AI/网络，也不触碰任何用户文件。
- 批量加标签属于 C2-06；Undo token/history 属于 C2-07；非 AI 标签建议属于
  C2-19；AI 自动标签属于 Stage 3，均不在本合同内。

### `remove_tag(repoPath, fileId, tag) throws -> TagSet`

```swift
let tags = try AreaMatrix.removeTag(
    repoPath: repoPath,
    fileId: entry.id,
    tag: "clientA"
)
detailView.updateTags(tags.fileTags)
```

C2-05 的单文件标签关系移除入口，服务 `S2-07 tags-add` 中 chip 删除动作。
它只移除当前文件与指定 tag 的关系，不删除 tag registry 中的标签定义，也不影响
其他文件的同名标签。成功后返回与 `add_tag` 相同的刷新后 `TagSet`。

错误与副作用边界：

- `InvalidPath`：`repoPath` 或 `tag` 校验失败。
- `FileNotFound`：目标 active file 不存在。
- `Db`：读取或删除 tag relation、刷新 registry、写入 `change_log` 失败。
- 移除一个当前文件没有的 tag 必须幂等返回刷新后的 `TagSet`，不得视为删除标签定义。
- 该 API 不执行批量 mutation、不生成 Undo token、不删除其他文件 tag、不修改文件、
  分类、笔记、搜索条件、Smart List 或用户文件。

### `list_tags(repoPath, fileId) throws -> TagSet`

```swift
let tags = try AreaMatrix.listTags(repoPath: repoPath, fileId: entry.id)
tagPopover.show(
    current: tags.fileTags,
    candidates: tags.availableTags,
    recent: tags.recentTags
)
```

C2-05 的只读标签状态入口。`S2-07 tags-add` 使用它加载当前文件 tag chips、
已有标签候选、最近使用标签、空态、加载失败和 Retry 状态。`S2-08 tags-filter`
可以复用 `available_tags` 作为 tag registry；标签计数和当前 search scope 下的
selected/disabled facet 状态仍由 C2-02 `list_filter_facets` 返回。

错误与副作用边界：

- `InvalidPath`：`repoPath` 校验失败。
- `FileNotFound`：目标 active file 不存在。
- `Db`：读取 active file、tag registry 或 tag relation 失败。
- 该 API 只读，不创建、更新、移除、重命名、建议或采纳标签，不写 `change_log`，
  不保存搜索，不修改 files/notes/categories/generated overview/repository metadata，
  也不移动、删除、重命名或读取用户文件内容。

### `batch_add_tags(repoPath, fileIds, tags) throws -> BatchMutationReport`

```swift
let report = try AreaMatrix.batchAddTags(
    repoPath: repoPath,
    fileIds: selectedFileIds,
    tags: ["urgent", "clientA"]
)
toast.showAddedTags(count: report.addedCount, undoToken: report.undoToken)
```

C2-06 的批量加标签入口，服务 `S2-09 batch-add-tags`，并向 `S2-10 undo-toast`
提供可撤销操作状态。输入是已初始化 `repoPath`、多选得到的 `fileIds` 和用户确认
后的 `tags`。Core 复用 C2-05 的 tag trim、大小写归一、长度和非法字符校验；批量
页在 Apply 前应已完成本地校验，但 Core 必须再次校验，不能把非法 pending tag
静默跳过。

输出 `BatchMutationReport`：

- `requested_file_count`：合同接受的去重后文件数，供 S2-09 显示影响范围。
- `requested_tag_count`：合同接受的去重后标签数。
- `added_count`：本次新写入的 file/tag relation 数量。
- `skipped_count`：目标文件已经拥有对应 tag 的数量；这类行不得写重复 relation，
  也不得进入 Undo 反向操作。
- `failed_count`：失败的 file/tag relation 数量。
- `item_results`：逐 file/tag 结果，`status` 为 `Added`、`AlreadyHadTag` 或
  `Failed`，`error` 承载失败摘要，供 `View details`、Retry 和可访问性文本使用。
- `undo_token`：成功写入可撤销关系后返回给 C2-07 undo toast/history；没有新增关系
  或实现无法创建 undo action 时为 `nil`。

错误与副作用边界：

- `FileNotFound`：`fileIds` 为空、包含 `<= 0`，或实现阶段发现目标 active file 不存在。
- `Db`：`repoPath` 的 tag metadata 不可用、tag 输入无法归一化、读取/写入 `tags`、
  写入 `change_log` 或写入 undo action 失败。
- 成功新增、重复跳过和失败项都必须在 `BatchMutationReport` 中可追踪；部分失败不得
  把失败项显示为成功。
- 重复 file id 和重复 tag 在写入前按稳定顺序去重；重复 tag relation 必须作为
  `AlreadyHadTag` 计入 `skipped_count`，不得写入重复行。
- 成功新增的关系写入 `change_log` 并进入 C2-07 undo action；原本已有的标签关系
  不进入 Undo 反向操作。Undo 执行本身属于 C2-07。
- 该 API 只写标签 metadata、change log 和 undo action；不移动、不重命名、不删除、
  不 Trash、不改分类、不写 note、不保存搜索、不 reindex、不更新 generated overview、
  不触发 AI/网络，也不触碰任何用户文件内容或路径。
- 批量 AI 标签建议属于 Stage 3；批量改分类、批量删除、批量重命名、Undo/Redo 执行、
  非 AI 标签建议和 tag suggestion 采纳分别属于其他能力，不在本合同内。

### `suggest_tags_for_file(repoPath, request) throws -> TagSuggestionReport`

```swift
let report = try AreaMatrix.suggestTagsForFile(
    repoPath: repoPath,
    request: TagSuggestionRequest(
        fileId: entry.id,
        context: nil,
        limit: 12
    )
)
suggestionsPanel.render(report.suggestions)
```

C2-19 的非 AI 标签建议入口，服务 `S2-23 tag-suggestions`。输入是已初始化
`repoPath`、目标 active `file_id`、可选来源上下文和建议数量上限。Core 只能基于
文件名、仓库相对路径、来源目录关键词和已有标签词库生成确定性建议；不得读取文件正文、
不得调用 AI 或远程 provider、不得发生网络访问。该入口只读，不写 tag metadata。

输出 `TagSuggestionReport`：

- `file_id`：本次建议对应的文件 ID。
- `suggestions`：建议行集合，包含 `suggestion_id`、`slug`、`display_name`、
  `reason`、`source`、`match_strength`、`already_exists`、`needs_create`、`status`、
  `selected_by_default` 和 `disabled_reason`，供 S2-23 展示候选、理由、Strong/Weak、
  New tag、Already added、Invalid 和 Blocked 状态。
- `tag_set`：当前文件标签与仓库 tag registry 快照，供页面避免重复添加并在空态回到
  S2-07 手动标签入口。
- `contents_read` / `ai_used` / `network_used`：隐私边界标记，Stage 2 必须全部为
  `false`，页面据此显示“非 AI、非内容读取”的说明。

错误与副作用边界：

- `FileNotFound`：`file_id <= 0`，或没有对应 active file row。
- `Validation`：`limit` 不在 `1..=50`，来源上下文为空白、超长、含 NUL 或看起来像
  URL/远程来源。
- `Conflict`：文件 metadata、既有标签或来源上下文无法形成确定性建议状态。
- `Db`：读取 active file、tag registry 或 tag relation 失败。
- 该 API 只读，不创建、更新、移除、重命名或采纳标签，不写 `change_log` 或
  `undo_actions`，不改变搜索筛选，不移动、删除、重命名、读取或上传任何用户文件。
- AI 标签建议、语义理解、OCR/正文读取和远程 provider 属于 Stage 3 的 C3-07，
  不属于本合同。

### `apply_tag_suggestions(repoPath, request) throws -> TagSuggestionApplyReport`

```swift
let report = try AreaMatrix.applyTagSuggestions(
    repoPath: repoPath,
    request: ApplyTagSuggestionsRequest(
        fileId: entry.id,
        suggestions: selectedSuggestions
    )
)
detailView.updateTags(report.tagSet.fileTags)
toast.showUndo(report.undoToken)
```

C2-19 的建议采纳入口，服务 `S2-23 tag-suggestions` 的 `Apply selected` 与
`Apply edited`。输入是同一个 active `file_id` 和用户明确选中或编辑后的建议行。
Core 创建或复用规范化后的 tag，写入当前文件 tag relation，记录 change log，并在
至少新增一个关系时返回 C2-07 undo token。未选、Ignore、Cancel edit 或 Already added
候选不得被写入。

输出 `TagSuggestionApplyReport`：

- `file_id`：本次采纳对应的文件 ID。
- `requested_count`：本次提交的建议行数量。
- `applied_count`：新写入的 file/tag relation 数量。
- `skipped_count`：已经存在、未重复写入的 relation 数量。
- `failed_count`：失败建议行数量。
- `item_results`：逐建议行结果，`status` 为 `Applied`、`AlreadyAdded` 或 `Failed`，
  `error` 承载行级失败摘要。
- `tag_set`：采纳后的当前标签状态，供 Detail Meta 或导入结果刷新。
- `undo_token`：新增关系进入 C2-07 undo stack 后的 token；没有新增关系时为 `nil`。
- `refresh_targets`：稳定刷新建议，至少覆盖 `tags`、`change_log`、`undo_actions`。

错误与副作用边界：

- `FileNotFound`：目标 active file 不存在。
- `Validation`：提交为空、suggestion id 为空、slug/display name 非法、slug 超长、
  含路径分隔符、冒号或 NUL。
- `Conflict`：编辑后的建议在同一次提交内归一化为重复 slug，无法确定性采纳。
- `Db`：创建/复用 tag、写入 file_tags、写入 change log 或 undo action 失败。
- 成功新增、重复跳过和失败项都必须在 report 中可追踪；部分失败不得把失败项显示为成功。
- 该 API 只写标签 metadata、当前文件关系、change log 和 undo action；不移动、不重命名、
  不删除、不 Trash、不改分类、不写 note、不保存搜索、不 reindex、不更新 generated
  overview、不触发 AI/网络，也不触碰任何用户文件内容或路径。
- C2-05 仍负责手动 add/remove/list tag；C2-07 负责执行 undo；本合同不新增
  control map 之外的页面能力。

### `preview_batch_move_to_category(repoPath, fileIds, targetCategory, moveRepoOwnedFiles) throws -> BatchCategoryPreviewReport`

```swift
let preview = try AreaMatrix.previewBatchMoveToCategory(
    repoPath: repoPath,
    fileIds: selectedFileIds,
    targetCategory: "finance",
    moveRepoOwnedFiles: true
)
applyButton.isEnabled = preview.canApply
```

C2-08 的只读批量改分类预览入口，服务 `S2-12 batch-change-category`。输入是已初始化
`repoPath`、多选得到的 `fileIds`、目标分类 slug `targetCategory`，以及是否把
repo-owned 文件移动到目标分类目录的 `moveRepoOwnedFiles`。目标分类必须已经存在于
classifier 规则或默认分类中；本 API 不创建新分类，`Create new category...` 仍属于
`S2-19 classifier-rule-editor` / C2-15。

输出 `BatchCategoryPreviewReport`：

- `requested_file_count`：去重后的选中文件数，供 sheet 标题和 Selected 摘要使用。
- `target_category` / `move_repo_owned_files`：回显当前预览绑定的目标分类和移动选项。
- `preview_token`：Apply 绑定令牌。用户修改目标分类、移动选项或选择集后，旧 token 失效。
- `category_distribution`：当前分类分布，供摘要区显示 `Reports (5), Invoices (4)`。
- `will_move_count`：确认后会移动 repo-owned 文件的数量。
- `metadata_only_count`：只更新 `files.category`、不会移动源文件的数量，包括 Indexed。
- `unchanged_count`：已在目标分类且无有效变化的数量。
- `skipped_count`：缺失文件或策略允许跳过项的数量。
- `blocked_count`：路径冲突、权限不足、目标目录不可写等阻止 Apply 的数量。
- `items`：逐文件 preview 行，`status` 为 `WillMove`、`MetadataOnly`、`Unchanged`、
  `Skipped` 或 `Blocked`，并携带当前分类、目标路径、target name、storage mode、
  index-only 和原因文本。
- `can_apply` / `apply_blocked_reason`：供 Apply 按钮、错误摘要和 VoiceOver 使用。

副作用边界：

- 只读检查 classifier、DB、目标路径、冲突和权限。
- 不创建目标分类目录，不移动、重命名、删除或覆盖文件，不写 `files`、`change_log`、
  `undo_actions`、notes、tags、saved searches、generated overview 或任何用户文件。
- Indexed 文件始终 `index_only = true` 且 `will_move_file = false`，不能移动外部源文件。
- `moveRepoOwnedFiles = false` 时，repo-owned 文件也只计划 metadata-only 分类更新。
- 预览必须覆盖每个去重后的 file id；部分不可处理项必须显示为 `Skipped` 或 `Blocked`，
  不得静默消失。

错误：

- `Classify`：目标分类不存在、为空或 classifier 规则不可用。
- `FileNotFound`：`fileIds` 为空、包含非法 id，或实现阶段发现必须阻断的 active row 缺失。
- `Conflict`：目标分类路径不是目录、note sidecar 冲突、或安全目标名无法解析。
- `PermissionDenied`：目标目录、metadata 或文件系统 inspection 被权限阻断。
- `Io`：路径存在性检查、repo-owned 文件 metadata 或 note sidecar 读取失败。
- `Db`：SQLite 查询、分类分布、file row 或 undo 预检状态读取失败。

### `batch_move_to_category(repoPath, fileIds, targetCategory, moveRepoOwnedFiles, previewToken) throws -> BatchCategoryChangeReport`

```swift
let report = try AreaMatrix.batchMoveToCategory(
    repoPath: repoPath,
    fileIds: selectedFileIds,
    targetCategory: preview.targetCategory,
    moveRepoOwnedFiles: preview.moveRepoOwnedFiles,
    previewToken: preview.previewToken
)
undoToast.present(token: report.undoToken)
```

C2-08 的批量改分类执行入口，服务 `S2-12 batch-change-category` 的 Apply，并向
`S2-10 undo-toast` / C2-07 提供可撤销操作状态。输入必须绑定最近一次有效
`preview_batch_move_to_category` 返回的 `preview_token`；如果选择集、目标分类、
移动选项或 inspected state 变化，Core 必须返回 `Conflict`，要求 UI 重新 Preview。

输出 `BatchCategoryChangeReport`：

- `requested_file_count`、`target_category`：回显本次执行范围。
- `moved_count`：成功移动 repo-owned 文件并更新 metadata 的数量。
- `metadata_only_count`：成功只更新 metadata 的数量。
- `unchanged_count`：无变化项数量，不写重复 change log，不进入 undo 反向操作。
- `skipped_count`：策略允许跳过项数量。
- `failed_count`：失败项数量。
- `item_results`：逐文件结果，`status` 为 `Moved`、`MetadataUpdated`、`Unchanged`、
  `Skipped` 或 `Failed`，`error` 承载用户可展示的失败摘要。
- `updated_files`：成功写入后最新 `FileEntry`，供 List/Detail/Tree 刷新。
- `undo_token`：成功写入可撤销移动或 metadata 分类变更后返回；没有有效写入时为 `nil`。

副作用边界：

- Copy / Move 等 repo-owned 文件在 `moveRepoOwnedFiles = true` 时移动到目标分类目录，
  更新 `files.category/path/updated_at`，写 `change_log.action = moved`，并进入
  C2-07 undo action。
- `moveRepoOwnedFiles = false` 或 Indexed 文件只更新 `files.category/updated_at` 与
  change log，不移动、重命名或覆盖源文件。
- 成功改分类不改变 `file_id`、`original_name`、hash、storage mode、origin、source path、
  tags 或 notes；note sidecar 只有在对应 repo-owned 文件移动时跟随文件安全移动。
- 部分失败必须在 `item_results` 中可追踪。失败项不得显示为成功；成功项可以保留并进入
  undo action，Undo 执行仍属于 C2-07。
- 不创建新分类，不保存 classifier rule，不执行 AI 批量重分类，不删除/Trash/rename
  非目标文件，不保存搜索，不 reindex，不更新 generated overview，不触发网络或远程 AI。

错误：

- `Classify`：目标分类不存在或 classifier 规则不可用。
- `Conflict`：preview token 缺失/过期、目标同名安全路径无法解析、外部变化让 Apply 不安全。
- `FileNotFound`：选择为空、非法 id，或目标 active row 已不存在。
- `PermissionDenied`：文件系统移动、目录创建或 metadata 写入被权限阻断。
- `Io`：repo-owned 文件移动、note sidecar 移动或路径检查失败。
- `Db`：SQLite 查询、更新、change log 或 undo action 写入失败。

页面消费状态：

- S2-12 可以从 preview 合同得到选中文件数、当前分类分布、目标分类、移动选项、影响数量、
  每行状态、Apply 是否可用和禁用原因。
- S2-12 可以从执行报告得到成功/失败/跳过摘要、刷新用 `updated_files`、失败详情和
  `undo_token`。
- S2-10 / C2-07 只消费 `undo_token` 和后续 `list_undo_actions` / `undo_action` 状态；
  本合同不新增 control map 之外的页面能力。

### `preview_batch_delete(repoPath, fileIds, deleteMode) throws -> BatchDeletePreviewReport`

```swift
let preview = try AreaMatrix.previewBatchDelete(
    repoPath: repoPath,
    fileIds: selectedFileIds,
    deleteMode: .moveToTrash
)
moveButton.isEnabled = preview.canApply
```

C2-09 的只读批量删除预览入口，服务 `S2-13 batch-delete-confirm`。输入是已初始化
`repoPath`、多选得到的 `fileIds` 和 `deleteMode`。Stage 2 只允许两种模式：

- `MoveToTrash`：计划把 AreaMatrix repo-owned 的 `Copied` / `Moved` 文件移到系统 Trash。
- `RemoveFromIndex`：计划只移除 Indexed / Adopted / External 或 Missing metadata 记录。

输出 `BatchDeletePreviewReport`：

- `requested_file_count`：去重后的选中文件数，供 sheet 标题和影响摘要使用。
- `delete_mode`：回显本次预览模式，避免 UI 混淆 Trash 删除和 index-only 移除。
- `preview_token`：绑定本次选择集、模式、Trash 可用性和已检查文件状态的确认令牌；执行
  API 必须带回该值。
- `trash_available`：系统 Trash 是否可用于 repo-owned 删除；为 `false` 时 UI 必须禁用
  `Move to Trash`，不得提供永久删除替代。
- `undo_available`：本次可处理项是否能创建 C2-07 undo action；为 `false` 时 S2-13
  必须显示 Undo 不可用确认区。
- `will_trash_count`：确认后会移动到 Trash 的 repo-owned 文件数。
- `index_only_count`：可以只移除 AreaMatrix 索引记录的数量。
- `missing_count`：物理文件缺失、只能移除 metadata 的数量。
- `skipped_count`：因模式或策略被排除的数量。
- `blocked_count`：Trash 不可用、权限不足、只读、外部变化等阻断数量。
- `items`：逐文件 preview 行，`status` 为 `WillMoveToTrash`、`IndexOnly`、`Missing`、
  `Skipped` 或 `Blocked`，并携带当前路径、显示名、storage mode、动作布尔值和原因文本。
- `can_apply` / `apply_blocked_reason`：供 destructive 按钮、错误摘要和 VoiceOver 使用。
  如果存在 blocked 项但仍有可处理项，`can_apply` 仍为 `true`，blocked 项必须作为 excluded
  行保留在摘要和执行报告中。

副作用边界：

- 只读检查 DB、文件状态、Trash 可用性和权限。
- 不移动文件到 Trash，不移除 index row，不写 `files`、`change_log`、`undo_actions`、
  notes、tags、saved searches、generated overview 或任何用户文件。
- 不提供永久删除，不清空 Trash，不删除外部源文件，不触发 iCloud placeholder 下载。
- 预览必须覆盖每个去重后的 file id；不可处理项必须显示为 `Skipped` 或 `Blocked`，
  不得静默消失或当作成功项。

错误：

- `FileNotFound`：`fileIds` 为空、包含非法 id，或实现阶段发现必须阻断的 active row 缺失。
- `Conflict`：preview token 缺失/过期、选择集/模式/Trash 可用性或 inspected state 已变化。
- `PermissionDenied`：Trash、metadata、目标文件或权限 inspection 被阻断。
- `Io`：Trash 可用性、文件系统 metadata 或路径检查失败。
- `Db`：SQLite 查询、file row、Trash/undo 预检状态读取失败。

### `batch_delete_to_trash(repoPath, fileIds, deleteMode, previewToken) throws -> BatchDeleteReport`

```swift
let report = try AreaMatrix.batchDeleteToTrash(
    repoPath: repoPath,
    fileIds: selectedFileIds,
    deleteMode: preview.deleteMode,
    previewToken: preview.previewToken
)
undoToast.present(token: report.undoToken)
```

C2-09 的批量删除执行入口，服务 `S2-13 batch-delete-confirm` 的
`Move to Trash` / `Remove from index`，并向 `S2-10 undo-toast` / C2-07 提供可撤销操作状态。
输入必须带回用户刚确认的 `preview_token`，并与 preview 状态一致；如果选择集、模式、
Trash 可用性或 inspected state 变化，Core 必须拒绝不安全写入并让 UI 重新 Preview。

输出 `BatchDeleteReport`：

- `requested_file_count`、`delete_mode`：回显本次执行范围和模式。
- `moved_to_trash_count`：成功移入系统 Trash 并软删除 metadata 的 repo-owned 文件数。
- `removed_from_index_count`：成功从 active metadata 移除的 index-only 或 missing 记录数。
- `skipped_count`：策略允许跳过项数量。
- `failed_count`：失败项数量。
- `item_results`：逐文件结果，`status` 为 `MovedToTrash`、`RemovedFromIndex`、`Skipped`
  或 `Failed`，`error` 承载用户可展示的失败摘要。
- `affected_file_ids`：成功或需要刷新状态的 file ids，供 List/Detail/Tree/selection 刷新。
- `undo_token`：成功写入可撤销 Trash 或 index removal 后返回；没有有效写入或无法创建
  undo action 时为 `nil`。

副作用边界：

- `MoveToTrash` 只能处理 AreaMatrix 管理的 `Copied` / `Moved` active 条目。成功时 Core
  把目标文件移入系统 Trash，软删除 `files` row，写 `change_log.action = deleted`，
  并进入 C2-07 undo action。
- `MoveToTrash` 如果已经移动文件和软删除 metadata，但批量 undo action 写入失败，Core
  必须把已处理项从 Trash 恢复到原 repo 路径并回滚对应 `files` / `change_log` 变更，
  然后返回 `Db` 或回滚失败对应的 `Io` / `Db` 错误；不得留下无 undo token 的已删除状态。
- `RemoveFromIndex` 只能处理 Indexed / Adopted / External 或 Missing metadata。成功时
  只更新 metadata，使该条目不再出现在默认 list/detail 中，并写
  `change_log.action = removed_from_index`；不得移动、删除、重命名、覆盖或 Trash 外部源文件。
- 部分失败必须在 `item_results` 中可追踪。失败项不得显示为成功；成功项可以保留并进入
  undo action，Undo 执行仍属于 C2-07。
- 预览中 blocked 但不阻止其他可处理项的行必须在执行报告中以 `Skipped` 返回，并保持文件和
  metadata 不变；不得因为存在 blocked 行整体拒绝 `Move available files to Trash`。
- 不提供永久删除，不清空 Trash，不删除其他用户文件，不修改 tags/notes/searches/categories，
  不保存搜索，不 reindex，不更新 generated overview，不触发 AI/网络。

错误：

- `FileNotFound`：选择为空、非法 id，或目标 active row 已不存在。
- `Conflict`：preview token 缺失/过期，或选择集、模式、Trash 可用性、inspected state
  与用户确认的 preview 不一致。
- `PermissionDenied`：系统 Trash、目标文件、外部源文件 inspection 或 metadata 写入被权限阻断。
- `Io`：Trash、文件系统 metadata 或 rollback 失败。
- `Db`：SQLite 查询、软删除/index removal、change log 或 undo action 写入失败。

页面消费状态：

- S2-13 可以从 preview 合同得到选中文件数、Trash 可用性、Undo 可用性、将进入 Trash /
  仅移除索引 / missing / skipped / blocked 数量、每行状态、Apply 是否可用和禁用原因。
- S2-13 可以从执行报告得到成功/失败/跳过摘要、刷新用 `affected_file_ids`、失败详情和
  `undo_token`。
- S2-10 / C2-07 只消费 `undo_token` 和后续 `list_undo_actions` / `undo_action` 状态；
  本合同不新增 control map 之外的页面能力。

### `preview_batch_rename(repoPath, fileIds, rule) throws -> BatchRenamePreviewReport`

```swift
let preview = try AreaMatrix.previewBatchRename(
    repoPath: repoPath,
    fileIds: selectedFileIdsInListOrder,
    rule: renameRule
)
applyButton.isEnabled = preview.canApply
```

C2-10 的只读批量重命名预览入口，服务 `S2-14 batch-rename`。输入是已初始化
`repoPath`、按当前 List 排序的 `fileIds` 和 `BatchRenameRule`。`fileIds` 顺序是合同的一部分：
`KeepBaseSequence` 必须按该顺序稳定生成序号，用户改变排序、选择集或规则后旧
`preview_token` 失效。

`BatchRenameRule` 支持四种 Stage 2 策略：

- `Prefix`：使用 `prefix` 生成 `{prefix}{stem}{ext}`。
- `DatePrefix`：使用 `date_source`、`date_format` 和 `separator` 生成
  `{formattedDate}{separator}{stem}{ext}`。
- `KeepBaseSequence`：使用 `separator`、`start_number` 和 `padding` 生成
  `{stem}{separator}{sequence}{ext}`。
- `ReplaceText`：使用 `find`、`replacement` 和 `case_sensitive` 替换 stem 文本。

所有策略默认保留原扩展名，只修改 stem；Core 必须再次校验规则和生成名称，不能依赖
Swift 端本地校验。

输出 `BatchRenamePreviewReport`：

- `requested_file_count`：去重后的选中文件数，供 sheet 标题和影响摘要使用。
- `rule`：回显本次预览绑定的规则。
- `preview_token`：绑定本次选择集、排序、规则和已检查文件状态的确认令牌；执行 API 必须带回。
- `will_rename_count`：确认后会重命名 repo-owned 文件的数量。
- `display_only_count`：Indexed 条目只更新 AreaMatrix display name 的数量。
- `unchanged_count`：规则生成结果与当前名称一致的数量。
- `blocked_count`：非法名称、缺失、只读、外部变化等阻止 Apply 的数量。
- `conflict_count`：批次内部或目标目录已有文件导致的重名冲突数量。
- `items`：逐文件 preview 行，`status` 为 `Ok`、`Error`、`NameConflict`、`Missing`、
  `ReadOnly`、`DisplayOnly`、`Unchanged` 或 `ExternalChange`，并携带 original/new 名称、
  target path、storage mode、index-only 和原因文本。
- `conflicts`：冲突详情，供错误行、结果摘要和 VoiceOver 使用。
- `can_apply` / `apply_blocked_reason`：供 Apply 按钮、错误摘要和 VoiceOver 使用。

副作用边界：

- 只读检查 DB、name sanitizer、目标路径、冲突和权限。
- 不重命名文件，不更新 `files`，不写 `change_log` 或 `undo_actions`，不更新 generated overview，
  不移动、删除、Trash、覆盖或读取用户文件内容。
- Indexed 文件始终 `index_only = true` 且 `will_rename_file = false`；预览只说明 display-name
  更新，不得触碰外部源文件。
- 预览必须覆盖每个去重后的 file id；不可处理项必须显示为对应阻塞状态，不得静默跳过。
- 存在 `Error`、`NameConflict`、`Missing`、`ReadOnly` 或 `ExternalChange` 时必须禁用 Apply。
  `Unchanged` 不阻塞；但如果所有行均 `Unchanged`，Apply 也必须禁用。

错误：

- `InvalidPath`：`repoPath`、规则字段或生成名称为空、不安全、命中非法字符或 metadata 内部路径。
- `FileNotFound`：`fileIds` 为空、包含非法 id，或实现阶段发现必须阻断的 active row 缺失。
- `Conflict`：目标名冲突无法作为逐行状态表达，或预览状态无法安全绑定。
- `PermissionDenied`：metadata、目标目录、目标文件或权限 inspection 被阻断。
- `Io`：路径存在性检查、repo-owned 文件 metadata 或权限读取失败。
- `Db`：SQLite 查询、file row 或 undo 预检状态读取失败。

### `batch_rename(repoPath, fileIds, rule, previewToken) throws -> BatchRenameReport`

```swift
let report = try AreaMatrix.batchRename(
    repoPath: repoPath,
    fileIds: selectedFileIdsInListOrder,
    rule: preview.rule,
    previewToken: preview.previewToken
)
undoToast.present(token: report.undoToken)
```

C2-10 的批量重命名执行入口，服务 `S2-14 batch-rename` 的 Apply，并向
`S2-10 undo-toast` / C2-07 提供可撤销操作状态。输入必须带回最近一次有效
`preview_batch_rename` 返回的 `preview_token`；如果选择集、排序、规则或 inspected state
变化，Core 必须返回 `Conflict`，要求 UI 重新 Preview。

输出 `BatchRenameReport`：

- `requested_file_count`：回显本次执行范围。
- `renamed_count`：成功重命名 repo-owned 文件并更新 metadata 的数量。
- `display_name_updated_count`：成功只更新 Indexed display name 的数量。
- `unchanged_count`：无变化项数量，不写重复 change log，不进入 undo 反向操作。
- `skipped_count`：策略允许跳过项数量。
- `failed_count`：失败项数量。
- `item_results`：逐文件结果，`status` 为 `Renamed`、`DisplayNameUpdated`、`Unchanged`、
  `Skipped` 或 `Failed`，`error` 承载用户可展示的失败摘要。
- `updated_files`：成功写入后最新 `FileEntry`，供 List/Detail/Tree 刷新。
- `undo_token`：成功写入可撤销 rename 或 display-name 变更后返回；没有有效写入时为 `nil`。

副作用边界：

- Copy / Move 等 repo-owned 文件只在当前目录内安全 rename，更新
  `files.path/current_name/updated_at`，写 `change_log.action = renamed`，并进入 C2-07 undo action。
- Indexed 文件只更新 `files.current_name/updated_at` 与 change log，不移动、重命名、覆盖或 Trash
  外部源文件。
- 成功批量 rename 不改变 `file_id`、category、tags、notes、hash、storage mode、origin、
  source path 或文件扩展名。
- 部分失败必须在 `item_results` 中可追踪。失败项不得显示为成功；成功项可以保留并进入
  undo action，Undo 执行仍属于 C2-07。
- 不实现 AI 自动命名，不改分类，不保存 classifier rule，不删除/Trash 文件，不保存搜索，
  不 reindex，不触发网络或远程 AI。

错误：

- `InvalidPath`：`repoPath`、规则字段或生成名称为空、不安全、命中非法字符或 metadata 内部路径。
- `Conflict`：preview token 缺失/过期，或选择集、排序、规则、目标冲突、inspected state
  与用户确认的 preview 不一致。
- `FileNotFound`：选择为空、非法 id，或目标 active row 已不存在。
- `PermissionDenied`：文件系统 rename、目标目录、外部源文件 inspection 或 metadata 写入被权限阻断。
- `Io`：repo-owned 文件 rename、路径检查或 rollback 失败。
- `Db`：SQLite 查询、更新、change log 或 undo action 写入失败。

页面消费状态：

- S2-14 可以从 preview 合同得到选中文件数、规则回显、逐行 original/new 名称、冲突详情、
  index-only display-name 行、unchanged 行、阻塞原因、Apply 是否可用和禁用原因。
- S2-14 可以从执行报告得到成功/失败/跳过摘要、刷新用 `updated_files`、失败详情和
  `undo_token`。
- S2-10 / C2-07 只消费 `undo_token` 和后续 `list_undo_actions` / `undo_action` 状态；
  本合同不新增 control map 之外的页面能力。

### `correct_file_category(repoPath, fileId, category, moveFile, remember) throws -> ClassifierCorrectionResult`

```swift
let result = try AreaMatrix.correctFileCategory(
    repoPath: repoPath,
    fileId: entry.id,
    category: "finance",
    moveFile: true,
    remember: true
)
detailStore.replace(result.updatedFile)
```

C2-12 的分类纠错入口，服务 `S2-16 classifier-correct` 的 `Apply correction`。
输入是初始化后的 `repoPath`、active `fileId`、目标分类 slug、是否移动 repo-managed
文件的 `moveFile`，以及是否需要规则草稿 handoff 的 `remember`。`category` 必须已存在于
classifier 规则或默认分类中；本 API 不创建新分类。

输出 `ClassifierCorrectionResult`：

- `updated_file`：纠错后最新 `FileEntry`，供 List/Detail/Tree 刷新。
- `rule_draft`：当 `remember = true` 且 Core 能生成安全候选时返回，供 S2-17/S2-18 继续确认。
  C2-12 不保存该草稿。
- `move_file_requested`：回显本次是否请求移动 repo-managed 文件。
- `remember_requested`：回显本次是否请求未来规则 handoff。
- `rule_confirmation_required`：当存在规则草稿或用户请求记住规则时为 true，提醒 UI 必须进入
  S2-17/S2-18 确认后才能保存规则。

副作用边界：

- 对 repo-managed `Copied` / `Moved` 文件，`moveFile = true` 时可执行安全移动，更新
  `files.category/path/updated_at` 并写 `change_log.action = moved` 或等价纠错记录；同名目标不得覆盖。
- `moveFile = false`、Indexed、adopted、missing 或不可写状态只能更新分类 metadata 和
  change log，不移动、重命名或覆盖外部源文件。
- `remember = true` 只返回 `ClassifierRuleDraft`，不得写入 `.areamatrix/classifier.yaml`、
  不保存 classifier rule、不预览大面积影响、不应用到历史文件。
- 不创建新分类，不实现 C2-13 rule save、C2-14 impact preview、C2-15 rule editor，不调用
  AI/network providers。

错误：

- `Classify`：目标分类不存在、为空、格式非法或 classifier 规则不可用。
- `Conflict`：安全目标路径无法解析或存在不可覆盖同名目标。
- `Io`：文件移动、路径检查或权限读取失败。
- `Db`：SQLite 查询、`files` 更新或 change log 写入失败。

页面消费状态：

- S2-16 可以从合同得到更新后的文件、是否执行了 move preference、是否请求 Remember、是否仍需
  规则确认，以及可传给 S2-17/S2-18 的规则草稿。
- S2-16 不能从本合同直接保存规则、创建分类、预览历史影响或应用批量重分类；这些能力分别属于
  C2-13、C2-15、C2-14 和后续任务。本合同不新增 control map 之外的页面能力。

### `save_classifier_rule(repoPath, rule) throws -> ClassifierRule`

```swift
let saved = try AreaMatrix.saveClassifierRule(
    repoPath: repoPath,
    rule: ClassifierRule(
        targetCategory: "finance",
        keywords: ["合同"],
        extensions: ["pdf"],
        priority: 0,
        previewConfirmed: false
    )
)
ruleStore.markSaved(saved)
```

C2-13 的分类规则保存入口，服务 `S2-17 classifier-save-rule` 的 `Save rule`。
输入是已初始化 `repoPath` 和一个 `ClassifierRule`。`target_category` 必须是已存在的
classifier category slug；`keywords` 和 `extensions` 是追加到目标分类的独立匹配值，
不是 keyword AND extension 复合规则；`extensions` 必须是不带点的小写值；`priority`
范围是 `-1000..1000`；`preview_confirmed` 表示 UI 已经完成必需的影响预览确认。

输出 `ClassifierRule`：

- `target_category`：最终写入的目标分类 slug。
- `keywords`：保存后的关键词匹配值，供 S2-17 显示成功后的规则摘要。
- `extensions`：保存后的扩展名匹配值，不带点且小写。
- `priority`：保存后的目标分类优先级。
- `preview_confirmed`：回显本次保存是否已经由 S2-17/S2-18 完成必要预览确认。

副作用边界：

- 只允许原子更新 classifier 配置：`.areamatrix/classifier.yaml` 或等价 classifier metadata。
- 保存规则只影响未来分类；不得重分类、移动、重命名、删除、Trash、导入、reindex、
  写 notes、tags、saved searches、generated overview 或任何用户文件。
- 不创建新分类，不写 `path`、`source_folder`、独立 rule `enabled` 字段或 compound AND 规则。
- 不实现 C2-14 impact preview、C2-15 rule CRUD、AI 自动生成规则或批量应用历史文件。

错误：

- `Config`：`repoPath`、目标分类、关键词、扩展名、priority、classifier schema
  无效，规则重复，或过宽规则尚未完成必要预览确认。
- `PermissionDenied`：classifier metadata 或 `.areamatrix/classifier.yaml` 写入被权限阻断。
- `Io`：读取、备份、原子写入或恢复 classifier 配置失败。

页面消费状态：

- S2-17 可以从合同得到保存后的目标分类、独立关键词、独立扩展名和 priority，用于成功摘要、
  toast、表单恢复和后续 rule-store 刷新。
- S2-17/S2-18 可以用 `preview_confirmed = true` 表达用户已完成必需预览后的
  `Save rule only` 回流；Core 只保存规则配置，不计算影响量、不批量应用历史文件。
- S2-17 不能从本合同得到历史影响量、批量应用结果或规则列表编辑状态；这些分别属于
  C2-14、后续 apply 行为和 C2-15。本合同不新增 control map 之外的页面能力。

### `preview_classifier_rule_impact(repoPath, request) throws -> RuleImpactReport`

```swift
let report = try AreaMatrix.previewClassifierRuleImpact(
    repoPath: repoPath,
    request: ClassifierImpactPreviewRequest(
        mode: .ruleDraft,
        rule: ClassifierRule(
            targetCategory: "finance",
            keywords: ["合同"],
            extensions: ["pdf"],
            priority: 0,
            previewConfirmed: false
        ),
        moveFiles: false,
        replacementCategory: nil
    )
)
impactSheet.render(report)
```

C2-14 的分类规则影响预览入口，服务 `S2-18 classifier-impact-preview` 的
`Preview rule impact` dry-run。输入是已初始化 `repoPath` 和
`ClassifierImpactPreviewRequest`。`request.mode` 支持 `RuleDraft`、`RemoveKeyword`、
`RemoveExtension` 和 `RemoveCategory`，用于规则草稿、删除 keyword、删除 extension
或删除 category 前的同一只读影响预览。`request.rule` 承载目标分类和规则 basis；
`target_category`、`keywords`、`extensions`、`priority` 的校验语义与
`save_classifier_rule` 保持一致；`keywords` 和 `extensions` 是独立 matcher basis，
不是 keyword AND extension 复合规则。`move_files` 表示是否按 S2-18 的
`Move files to new category folders` 选择执行路径冲突 dry-run；关闭时只预览分类
metadata 变化，不因目标路径同名文件阻断。`replacement_category` 只在
`RemoveCategory` 模式下有效。

输出 `RuleImpactReport`：

- `request`：回显本次预览请求，供规则摘要、删除摘要和 Back 恢复。
- `move_files`：通过 `request` 回显 Move checkbox 状态，供 S2-18 在关闭 Move 后
  重新 dry-run 并恢复 UI 状态。
- `affected_file_count`：现有文件中命中该草稿的总数。
- `will_update_count`：命中且当前分类会改变的文件数量。
- `already_correct_count`：命中但已经属于目标分类的文件数量。
- `needs_review_count`：命中但需要人工确认、不能直接批量应用的文件数量。
- `conflict_count`：路径冲突、缺失文件或规则冲突数量。
- `sample_limit`：本响应最多携带多少样例行。
- `samples`：S2-18 表格样例，包含文件 id、路径、当前分类、新分类、命中原因、
  `WillUpdate` / `AlreadyCorrect` / `NeedsReview` / `Conflict` / `Missing` /
  `IndexOnly` 状态和可选原因。
- `conflicts`：结构化冲突列表，供禁用原因和 VoiceOver 文案使用。
- `needs_review`：是否存在 review-only 行。
- `warning_required` / `warning`：影响量超过阈值时显示过宽规则 warning。
- `can_apply` / `apply_blocked_reason`：后续 apply 任务是否可直接执行，以及禁用原因。
  删除 category 且没有 `replacement_category` 时必须返回 `can_apply = false`，并给出
  replacement 缺失的禁用原因。

副作用边界：

- 只读读取 classifier 配置和文件 metadata；RuleDraft 必须按当前
  `classifier.yaml` matcher 语义临时叠加草稿后重新计算新分类，DB 查询和
  move dry-run 的冲突检测语义只在 `move_files = true` 时参与 Apply 禁用判断。
- 删除 keyword、extension 或 category 的预览只计算现有 metadata 会如何变化；
  不修改 `classifier.yaml`，也不得移动、删除或重命名历史文件。
- 不得保存规则、重分类、移动、重命名、删除、Trash、导入、reindex、写 notes、
  tags、saved searches、generated overview、change_log、undo_actions 或任何用户文件。
- 不实现 C2-13 rule save、C2-15 rule CRUD、后续 apply 行为、AI 自动生成规则、
  后台持续规则评估或跨端同步。

错误：

- `Config`：`repoPath`、目标分类、关键词、扩展名、priority、replacement category、
  delete preview request 或 classifier schema 无效。
- `Db`：classifier impact 所需文件 metadata、分类 metadata、冲突检测 metadata 或
  preview 查询不可读取。

页面消费状态：

- S2-18 可以从合同得到规则摘要、影响总量、will update / already correct /
  needs review / conflict 计数、样例表格、Index-only / Missing / Name conflict 状态、
  Move on/off 的冲突差异、过宽 warning、Apply 是否可用、禁用原因、删除匹配值影响
  和删除 category replacement 缺失状态。
- S2-18 不能从本合同保存规则、应用到现有文件、写 Undo stack、编辑规则列表或创建新分类；
  这些分别属于 C2-13、后续 apply 行为、C2-07、C2-15 和 classifier editor 流程。
  本合同不新增 control map 之外的页面能力。

### `list_classifier_rules(repoPath) throws -> ClassifierRuleEditorSnapshot`

```swift
let snapshot = try AreaMatrix.listClassifierRules(repoPath: repoPath)
ruleEditor.load(snapshot.rules, defaultRuleId: snapshot.defaultRuleId)
```

C2-15 的分类规则编辑器入口，服务 `S2-19 classifier-rule-editor` 的初始加载、
YAML reload 后刷新、保存成功后刷新和 Revert。输入只包含已初始化 `repoPath`。

输出 `ClassifierRuleEditorSnapshot`：

- `rules`：当前 classifier category 列表。每个 `ClassifierRuleRecord` 包含
  `rule_id`、`slug`、`display_name`、`description`、`extensions`、`keywords`、
  `priority`、`naming_template` 和 `is_default`，对应 S2-19 左侧分类列表和右侧详情。
- `default_rule_id`：当前默认分类，用于禁用删除默认分类和读出 default 状态。
- `updated_rule_id`：最近一次 update/delete 后可重新选中的行；纯列表加载时为 `nil`。
- `warning`：读取成功但需要用户注意的 classifier 状态，例如外部 YAML reload 后仍需
  Validate。

副作用边界：

- 只读取 `.areamatrix/classifier.yaml` 或等价 classifier metadata。
- 不校验 UI 草稿、不保存规则、不删除分类、不预览影响、不移动、删除、重命名或重分类
  历史文件。
- 不写 `files`、`change_log`、`undo_actions`、notes、tags、saved searches、
  generated overview，也不打开 YAML、不调用 AI/network providers。

错误：

- `Config`：`repoPath` 为空、位于 `.areamatrix/` 内部，或 classifier schema、
  default category、slug、extension、keyword、priority、naming template 无效。
- `PermissionDenied`：classifier metadata 或 `.areamatrix/classifier.yaml` 读取被权限阻断。
- `Io`：读取 classifier 配置失败。

页面消费状态：

- S2-19 可以从合同得到分类列表、dirty/revert 的 last-valid 基线、字段初值、
  default category 删除禁用状态、空态、加载失败和 reload 后刷新状态。
- S2-19 不能从本合同得到历史影响量、批量应用结果、Open YAML 的平台动作或 AI 规则建议；
  这些分别属于 C2-14、后续 apply 行为、平台层和 Stage 3。本合同不新增 control map
  之外的页面能力。

### `create_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`

```swift
let snapshot = try AreaMatrix.createClassifierRule(
    repoPath: repoPath,
    request: ClassifierRuleCreateRequest(
        slug: "tax",
        displayName: "Tax",
        description: "Tax documents",
        extensions: ["pdf"],
        keywords: ["tax"],
        priority: 0,
        namingTemplate: "{stem}"
    )
)
ruleEditor.replaceSnapshot(snapshot)
```

C2-15 的新建分类入口，服务 S2-19 的 `New category` 后 Validate + Save。输入是
已初始化 `repoPath` 和一个 `ClassifierRuleCreateRequest`。`slug` 是写回 classifier
的分类 slug；扩展名必须是不带点的小写值；`priority` 范围为 `-1000..1000`；
`naming_template` 只允许当前 `classifier.yaml` 支持的模板字段。新建分类不会自动影响
历史文件，因此不要求 impact preview confirmation。

输出为新建后的 `ClassifierRuleEditorSnapshot`，让 S2-19 刷新分类列表、选中新建行、
Save 成功后的 last-valid 基线、dirty 状态和 warning。

副作用边界：

- 只允许原子更新 classifier 配置：`.areamatrix/classifier.yaml` 或等价 classifier metadata。
- 新建分类只影响未来分类；不会自动移动、删除、重命名或重分类历史文件。
- 写入失败时旧 classifier 配置必须保持为活动版本；实现阶段需要能恢复临时写入或备份。
- 不写 `files`、`change_log`、`undo_actions`、notes、tags、saved searches、
  generated overview，不执行 C2-13 `save_classifier_rule`、C2-14 impact preview、
  Trash、reindex、AI/network provider 或 Open YAML 平台动作。
- 不实现复杂脚本规则、插件规则、`path`、`source_folder` 或独立 rule `enabled` 字段。

错误：

- `Config`：`repoPath`、slug、display name、description、extensions、keywords、
  priority、naming template、重复 slug、重复 matcher value 或 classifier schema 无效。
- `PermissionDenied`：classifier metadata 或 `.areamatrix/classifier.yaml` 写入被权限阻断。
- `Io`：读取、备份、原子写入或恢复 classifier 配置失败。

页面消费状态：

- S2-19 可以从合同得到新建后的列表快照、当前选中行、Save 成功后的 last-valid 基线、
  字段错误对应的 `Config` 状态和写入失败恢复路径。
- S2-19 不能从本合同得到历史影响量、批量应用结果、Undo token、文件刷新列表或 YAML 高级
  编辑器动作。本合同不新增 control map 之外的页面能力。

### `update_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`

```swift
let snapshot = try AreaMatrix.updateClassifierRule(
    repoPath: repoPath,
    request: ClassifierRuleUpdate(
        ruleId: "finance",
        slug: "finance",
        displayName: "Finance",
        description: "Finance documents",
        extensions: ["pdf", "csv"],
        keywords: ["invoice"],
        priority: 10,
        namingTemplate: "{stem}-{date}",
        previewConfirmed: true
    )
)
ruleEditor.replaceSnapshot(snapshot)
```

C2-15 的编辑保存入口，服务 S2-19 的 Validate 后 Save。输入是已初始化
`repoPath` 和一个 `ClassifierRuleUpdate`。`rule_id` 是稳定目标行，`slug` 是写回
classifier 的分类 slug；扩展名必须是不带点的小写值；`priority` 范围为
`-1000..1000`；`naming_template` 只允许当前 `classifier.yaml` 支持的模板字段。
`preview_confirmed` 表示删除/大范围变更前 UI 已经完成影响预览或等价摘要确认。

输出仍为 `ClassifierRuleEditorSnapshot`，让 S2-19 在保存成功后用同一份已持久化快照
刷新分类列表、详情字段、default 状态、dirty 状态、warning 和 last-valid 基线。

副作用边界：

- 只允许原子更新 classifier 配置：`.areamatrix/classifier.yaml` 或等价 classifier metadata。
- 保存只影响未来分类；删除匹配值或修改分类配置不会自动移动、删除、重命名或重分类历史文件。
- 写入失败时旧 classifier 配置必须保持为活动版本；实现阶段需要能恢复临时写入或备份。
- 不写 `files`、`change_log`、`undo_actions`、notes、tags、saved searches、
  generated overview，不执行 C2-13 `save_classifier_rule` 的单规则草稿保存、不执行 C2-14
  impact preview、不调用 AI/network providers。
- 不实现 C2-13 rule save、C2-14 impact preview、复杂脚本规则、插件规则或 Stage 3 AI 规则。
- 不实现复杂脚本规则、插件规则、`path`、`source_folder` 或独立 rule `enabled` 字段。

错误：

- `Config`：`repoPath`、`rule_id`、slug、display name、description、extensions、
  keywords、priority、naming template、default category、重复 slug、重复 matcher、
  preview confirmation 或 classifier schema 无效。
- `PermissionDenied`：classifier metadata 或 `.areamatrix/classifier.yaml` 写入被权限阻断。
- `Io`：读取、备份、原子写入或恢复 classifier 配置失败。

页面消费状态：

- S2-19 可以从合同得到保存后的列表快照、当前选中行、Save 成功后的 last-valid 基线、
  仍需展示的 warning、字段错误对应的 `Config` 状态和写入失败恢复路径。
- S2-19 不能从本合同得到历史影响量、批量应用结果、Undo token、文件刷新列表或 YAML 高级
  编辑器动作。本合同不新增 control map 之外的页面能力。

### `delete_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`

```swift
let snapshot = try AreaMatrix.deleteClassifierRule(
    repoPath: repoPath,
    request: ClassifierRuleDeleteRequest(
        ruleId: "legacy",
        replacementCategory: "docs",
        previewConfirmed: true
    )
)
ruleEditor.replaceSnapshot(snapshot)
```

C2-15 的分类规则删除入口，服务 S2-19 的 Delete category 和删除已存在 rule row 的
确认流程。输入是已初始化 `repoPath` 和一个 `ClassifierRuleDeleteRequest`。
`rule_id` 指向要删除的 classifier category；`replacement_category` 是删除分类前影响预览
使用的回退分类；`preview_confirmed` 表示 UI 已展示影响摘要或完成 S2-18 影响预览。

输出为删除后的 `ClassifierRuleEditorSnapshot`，让 S2-19 刷新分类列表、选中回退行、
default 状态、dirty 状态和 warning。

副作用边界：

- 只允许原子更新 classifier 配置，删除对应 classifier category 或 rule row。
- 删除规则不自动移动、删除、重命名或重分类历史文件；是否更新现有文件分类只能通过后续
  impact/apply 流程执行。
- 必须拒绝删除默认分类、最后一个分类、缺失 replacement 的分类删除、未完成影响确认的删除。
- 不写 `files`、`change_log`、`undo_actions`、notes、tags、saved searches、
  generated overview，不执行 Trash、reindex、AI/network provider 或 Open YAML 平台动作。

错误：

- `Config`：`repoPath`、`rule_id`、replacement category、preview confirmation、默认分类保护、
  最后分类保护或 classifier schema 无效。
- `PermissionDenied`：classifier metadata 或 `.areamatrix/classifier.yaml` 写入被权限阻断。
- `Io`：读取、备份、原子写入或恢复 classifier 配置失败。

页面消费状态：

- S2-19 可以从合同得到删除后的列表、下一条可选行、默认分类保护、删除禁用原因对应错误、
  Save/Revert 基线和写入失败恢复状态。
- S2-19 不能从本合同得到历史文件更新、Undo action、Trash 删除、AI 建议或插件规则状态。
  本合同不新增 control map 之外的页面能力。

### `list_undo_actions(repoPath) throws -> [UndoActionRecord]`

```swift
let actions = try AreaMatrix.listUndoActions(repoPath: repoPath)
let latest = actions.first { $0.status == .pending }
undoToast.present(action: latest)
```

C2-07 的 Undo action log 列表入口，服务 `S2-10 undo-toast` 和
`S2-11 undo-history`。输入只包含已初始化 `repoPath`；输出按最近优先返回
Undo stack snapshot，让 toast、历史面板、Cmd+Z 状态和 VoiceOver 可以从合同中
得到同一份可用性状态。

输出 `UndoActionRecord`：

- `action_id`：稳定 undo action 标识，来自 `undo_actions.token`，也是
  `undo_action` 的输入。
- `kind`：稳定操作类型，例如 `batch_add_tags`、`move_files`、`rename_files`
  或 `trash_delete`，供 UI 选择图标和文案。
- `summary`：显示在 toast 和历史行的操作摘要，不要求 UI 解析 JSON。
- `affected_count`：影响文件数或关系数。
- `affected_file_names`：最多若干文件名样例，供 `S2-11` preview 使用。
- `status`：`Pending`、`Executed`、`Expired`、`Blocked`。
- `can_undo`：当前是否允许通过 `undo_action` 执行。
- `disabled_reason`：过期、被后续写操作阻塞、外部变化不可撤销、Trash
  不可恢复或权限不足时的用户可读原因。
- `created_at` / `updated_at`：排序、相对时间和状态刷新使用的 Unix 秒级时间戳。

错误与副作用边界：

- `Db`：读取 `undo_actions` metadata、summary 或状态失败。
- `Io`：实现阶段读取与 summary 相关的 AreaMatrix-owned metadata 失败。
- 该 API 只读，不执行 undo，不写 `undo_actions`，不写 `change_log`，不移动、
  重命名、删除、Trash restore、retag、reclassify、reindex、更新 generated
  overview 或触碰用户文件。
- 外部 FSEvents 造成的变化不得伪装成可撤销操作；只能返回 `Blocked` 或不进入
  pending 列表，并通过 `disabled_reason` 说明。

### `undo_action(repoPath, actionId) throws -> UndoActionResult`

```swift
let result = try AreaMatrix.undoAction(
    repoPath: repoPath,
    actionId: action.actionId
)
store.refresh(result.refreshTargets)
```

C2-07 的 Undo 执行入口。输入是已初始化 `repoPath` 和 `action_id`；输出
`UndoActionResult` 告诉 UI 本次撤销的最终状态、影响数量、完成摘要以及需要刷新的
页面状态。该入口只执行 Undo，不执行 Redo；Redo stack 和 `Shift+Cmd+Z` 属于
C2-18。

输出 `UndoActionResult`：

- `action_id`：本次请求的 action 标识。
- `status`：执行后状态，成功通常为 `Executed`；失败可保持或转为 `Blocked`。
- `summary`：完成文案，例如 `Undone: added tag "finance" to 24 files.`。
- `affected_count`：实际撤销影响范围。
- `refresh_targets`：稳定刷新建议，例如 `files`、`tags`、`undo_actions`、
  `change_log`、`tree`、`selection`，供页面消费方刷新对应 store。
- `completed_at`：撤销完成时间。

错误与副作用边界：

- `FileNotFound`：`action_id` 为空、找不到 pending undo action、或反向操作引用的
  文件已不存在。
- `Conflict`：外部变化、后续写操作或当前状态让反向操作不再安全。
- `PermissionDenied`：metadata、目标文件、Trash restore 或目录写入被权限阻断。
- `Db`：读取/标记 undo action、写入反向 `change_log` 或恢复 metadata 失败。
- `Io`：反向文件操作失败。
- Undo 必须按单个 action 的事务边界执行。失败不得把失败项显示为成功，不得破坏当前状态，
  不得把未完成 action 标记为 `Executed`。
- 撤销 batch tag 只移除当初新增的标签关系；原本已有标签关系不被删除。
- 撤销移动、重命名、删除或改分类时，必须遵守原能力的用户文件安全边界；外部
  FSEvents 造成的变化不得被撤销。
- 该入口不实现批量改分类、批量删除、批量重命名、导入冲突批量决策、Redo、
  AI 标签建议、远程同步或跨端 Undo。

### `list_redo_actions(repoPath) throws -> [RedoActionRecord]`

```swift
let actions = try AreaMatrix.listRedoActions(repoPath: repoPath)
let latest = actions.first { $0.status == .available && $0.canRedo }
redoRegion.render(action: latest)
```

C2-18 的 Redo action log 列表入口，服务 `S2-22 redo`，并被宿主
`S2-10 undo-toast` Redo slot 与 `S2-11 undo-history` Redo row 消费。输入只包含
已初始化 `repoPath`；输出按最近优先返回 redo stack snapshot，让 Redo 按钮、
`Redo latest`、`Shift+Cmd+Z`、VoiceOver 和禁用原因从同一份合同中得到状态。

输出 `RedoActionRecord`：

- `action_id`：稳定 redo action 标识，也是 `redo_action` 的输入。
- `kind`：稳定操作类型，例如 `batch_add_tags`、`move_files`、`rename_files`
  或 `trash_delete`，供 UI 选择图标和文案。
- `summary`：显示在 Redo slot 和历史行的操作摘要，不要求 UI 解析 JSON。
- `affected_count`：影响文件数或关系数。
- `affected_file_names`：最多若干文件名样例，供 `S2-22` preview 使用。
- `status`：`Available`、`Cleared`、`Blocked`、`Expired`、`Executed`。
- `can_redo`：当前是否允许通过 `redo_action` 执行。
- `disabled_reason`：redo stack 被新写操作清空、外部变化阻塞、跨重启过期、
  Trash restore 不可用或权限不足时的用户可读原因。
- `source_undo_action_id`：生成该 redo 行的 C2-07 undo action，供 S2-22 说明来源。
- `created_at` / `updated_at`：排序、相对时间和状态刷新使用的 Unix 秒级时间戳。

错误与副作用边界：

- `Db`：读取 redo stack metadata、summary、source undo linkage 或状态失败。
- `Io`：实现阶段读取与 summary 相关的 AreaMatrix-owned metadata 失败。
- 该 API 只读，不执行 redo，不写 `undo_actions`，不写 `change_log`，不移动、
  重命名、删除、Trash restore、retag、reclassify、reindex、更新 generated
  overview、触发 iCloud 下载、调用 AI/network provider 或触碰 `apps/**`。
- 新写操作清空 redo stack 后必须返回 `Cleared` 或不进入可用列表，并通过
  `disabled_reason` 提供用户可见原因。

### `redo_action(repoPath, actionId) throws -> RedoActionResult`

```swift
let result = try AreaMatrix.redoAction(
    repoPath: repoPath,
    actionId: action.actionId
)
store.refresh(result.refreshTargets)
```

C2-18 的 Redo 执行入口。输入是已初始化 `repoPath` 和 redo `action_id`；输出
`RedoActionResult` 告诉 UI 本次重做的最终状态、影响数量、完成摘要、恢复后的
Undo token 以及需要刷新的页面状态。Redo 只重放 AreaMatrix 成功 Undo 后生成的
可用 redo action；新的写操作会清空 redo stack，多设备协同 redo 不属于 Stage 2。

输出 `RedoActionResult`：

- `action_id`：本次请求的 redo action 标识。
- `status`：执行后状态，成功通常为 `Executed`；失败可保持或转为 `Blocked`。
- `summary`：完成或失败文案，例如 `Redone: moved 5 files to Documents.`。
- `affected_count`：实际重做影响范围。
- `refresh_targets`：稳定刷新建议，例如 `files`、`tags`、`undo_actions`、
  `redo_actions`、`change_log`、`tree`、`selection`，供页面消费方刷新对应 store。
- `undo_token`：redo 成功后原操作重新进入 C2-07 Undo stack 时创建的 undo token。
- `completed_at`：重做完成时间。

错误与副作用边界：

- `FileNotFound`：`action_id` 为空、找不到 redo action、或原动作引用的文件已不存在。
- `ExpiredAction`：redo action 已被新写操作清空、跨重启过期或不再属于可用 stack。
- `Conflict`：外部变化、路径冲突、stale state 或 Trash preflight 让重做不安全。
- `PermissionDenied`：metadata、目标文件、Trash restore 或目录写入被权限阻断。
- `Db`：读取/标记 redo action、写入 redo `change_log` 或恢复 C2-07 undo stack 失败。
- `Io`：重做文件操作或 rollback 失败。
- Redo 必须按单个 action 的事务边界执行。失败不得破坏当前文件系统和 DB 状态，
  不得把未完成 redo 标记为 `Executed`，不得覆盖外部 FSEvents 造成的变化。
- 该入口不实现 Undo 本身、批量改分类、批量删除、批量重命名、导入冲突批量决策、
  classifier rule、AI 标签建议、远程同步、多设备 redo 或独立 Redo 页面。

页面消费状态：

- S2-22 可以从列表合同得到 redo 可用性、来源 undo action、影响数量、示例文件、
  cleared/blocked/expired 原因、相对时间、`Shift+Cmd+Z` 和 VoiceOver 所需状态。
- S2-22 可以从执行结果得到成功/失败摘要、刷新用 `refresh_targets`、恢复后的
  `undo_token` 和失败后是否继续保留 redo row。
- S2-10 / S2-11 只作为宿主区域消费 C2-18 状态；本合同不新增 control map 之外的
  独立 Redo 页面、独立 panel 或其他页面能力。

### `get_file(repoPath, fileId) throws -> FileEntry`

```swift
let entry = try AreaMatrix.getFile(repoPath: repoPath, fileId: 42)
detailView.show(entry)
```

文件不存在抛 `FileNotFound`。

### `list_changes(repoPath, filter) throws -> [ChangeLogEntry]`

```swift
let changes = try AreaMatrix.listChanges(
    repoPath: repoPath,
    filter: ChangeFilter(
        fileId: entry.id,
        category: nil,
        action: nil,
        since: nil,
        until: nil,
        limit: 100,
        offset: 0
    )
)
historyView.update(changes)
```

详见 [../modules/change-log.md](../modules/change-log.md)。

### `list_tree_json(repoPath, locale) throws -> String`

```swift
let json = try await Task.detached {
    try AreaMatrix.listTreeJson(repoPath: repoPath, locale: "zh-Hans")
}.value

let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let tree = try decoder.decode(TreeNode.self, from: json.data(using: .utf8)!)
sidebar.update(tree)
```

输入：

- `repoPath`：已初始化的资料库根目录。
- `locale`：显示名 locale，例如 `zh-Hans` 或 `en`；未知 locale 可回退到稳定 slug。

输出为 Swift 可解码的 `TreeNode` JSON 字符串，而非跨 FFI 返回
`TreeNode` 对象，避免大 sequence 多次拷贝。JSON 根节点和所有子节点使用同一
schema：

```json
{
  "slug": "__root__",
  "display_name": "资料库",
  "kind": "RepositoryRoot",
  "relative_path": "",
  "file_count": 0,
  "size_bytes": 0,
  "depth": 0,
  "children": []
}
```

`relative_path` 是稳定 path key；同级 `children` 必须稳定排序。`kind` 取值
为 `RepositoryRoot`、`SystemCategory`、`UserFolder` 或 `Subdir`，字段名保持
snake_case 以配合 Swift `JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase`。

错误码边界：

- `RepoNotInitialized`：资料库 metadata 缺失。
- `Db`：树构建需要读取 SQLite metadata 时失败。
- `Io`：资料库目录、文件路径、文件 metadata 或分类配置无法读取。

副作用边界：该 API 只读取资料库文件路径和分类配置，不写 DB，不创建 generated
overview，不移动、重命名、删除或修改用户文件。虚拟智能列表、搜索结果树和
Stage 2 tree projection 不属于本接口。详见 [../modules/tree-scan.md](../modules/tree-scan.md)。

### `list_icloud_conflicts(repoPath) throws -> [ICloudConflictPair]`

```swift
let conflicts = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.listIcloudConflicts(repoPath: repoPath)
}.value
let needsReview = conflicts.filter { $0.status == .needsReview }
```

`list_icloud_conflicts` 是 C1-25 的只读 iCloud conflicted copy 列表入口，
用于 S1-36。输入是已初始化的资料库根路径；输出按冲突副本返回
`ICloudConflictPair`：

- `conflict_id`：稳定冲突 ID，供后续单项 resolve 入口使用。
- `original_path` / `original_modified_at`：可识别时返回原始版本路径和修改时间。
- `conflicted_copy_path` / `conflicted_modified_at`：冲突副本路径和修改时间。
- `status`：当前状态；识别不确定或需要用户决策时必须为 `NeedsReview`。
- `uncertainty_reason`：原始版本无法确定、多个候选或 metadata 不完整时的结构化原因。

副作用边界：

- 只扫描 iCloud conflicted copy 和可选 conflict state metadata。
- 不删除、不移动、不重命名、不覆盖、不合并任何原始文件或冲突副本。
- 不触发 iCloud placeholder 下载；下载协调属于平台层。
- 不写 `files` 记录；后续 `mark_icloud_conflict_resolved` 这类单项 resolve
  入口必须显式由用户确认，不能藏在列表查询中。

错误：

- `ICloudPlaceholder`：关键 metadata 或冲突副本仍是未下载占位符。
- `PermissionDenied`：资料库、冲突副本或 conflict state metadata 无法检查。
- `Io`：文件系统扫描、metadata 读取或路径解析失败。
- `Db`：可选 conflict state metadata 读取失败。

空态返回空数组。加载失败必须通过结构化 `CoreError` 抛出；识别不确定的
冲突仍返回条目，但 `status = NeedsReview`。

### `preview_conflict_versions(repoPath, conflictId) throws -> ICloudConflictPreviewReport`

```swift
let preview = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.previewConflictVersions(
        repoPath: repoPath,
        conflictId: conflict.conflictId
    )
}.value
let defaultChoice = preview.defaultResolution // .keepBoth
```

`preview_conflict_versions` 是 C2-16 的 iCloud 冲突可视化预览入口，
用于 S2-20 在用户明确进入单个冲突后展示版本 metadata、预览摘要和按钮
可用性。输入是已初始化资料库根路径和 `list_icloud_conflicts` 返回的
`conflict_id`；输出为 `ICloudConflictPreviewReport`：

- `conflict_id`：回显稳定冲突 ID，供 Resolve 绑定同一冲突。
- `versions`：每个版本的 metadata 和预览摘要，字段包括 `version_id`、
  `role`、`path`、`modified_at`、`size_bytes`、`hash_sha256`、
  `preview_summary` 和 `preview_status`。
- `default_resolution`：必须为 `KeepBoth`，让 UI 默认保留所有版本。
- `resolution_options`：每个选择的 destructive、Trash 依赖、启用状态和
  禁用原因。
- `metadata_complete`：metadata 是否足以启用 destructive 选择。
- `trash_available`：系统 Trash 是否可用于 Keep original / Keep conflicted copy。
- `can_keep_both`：Keep both 是否可直接提交。
- `can_resolve_destructive`：是否允许启用会丢弃某个版本的选择。
- `blocked_reason`：整体阻断原因，供错误摘要和 VoiceOver 使用。

副作用边界：

- 只读取 conflict state、版本 metadata、可安全读取的 hash 或摘要。
- 不标记 resolved，不写 `files`、`change_log` 或 `undo_actions`。
- 不删除、不移动、不重命名、不覆盖、不合并任何版本，不写 Trash。
- 不触发 iCloud placeholder 下载；下载协调属于平台层。
- 不实现 QuickLook UI 渲染、import conflict 批量决策或 Stage 4 云盘 SDK 集成。

错误：

- `ICloudPlaceholder`：关键 metadata 或任一必需版本仍是未下载占位符。
- `PermissionDenied`：资料库、版本 metadata、Trash preflight 或 conflict state
  无法检查。
- `Conflict`：`conflict_id` 已过期、无法安全绑定或当前版本集合已变化。
- `Io`：文件系统 metadata、hash 或预览摘要读取失败。
- `Db`：可选 conflict state metadata 读取失败。

S2-20 可以从本合同得到两个或多个版本的 metadata、metadata-only / preview
可用性、默认 Keep both、Trash 不可用时的按钮禁用原因，以及 destructive
二次确认所需的“另一版本会进入 Trash”边界。S2-20 不能从本合同得到
QuickLook 视图对象、平台 iCloud 下载进度、Undo 执行结果或跨设备同步冲突处理。

### `resolve_icloud_conflict(repoPath, conflictId, resolution) throws -> ICloudConflictResolveReport`

```swift
let report = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.resolveIcloudConflict(
        repoPath: repoPath,
        conflictId: conflict.conflictId,
        resolution: .keepBoth
    )
}.value
```

`resolve_icloud_conflict` 是 C2-16 的单项解决入口，只能在用户完成 S2-20
确认后调用。`resolution` 取值：

- `KeepBoth`：保留所有版本，只把冲突状态写为 resolved / acknowledged。
- `KeepOriginal`：保留原始版本，将 conflicted copy 移到系统 Trash。
- `KeepConflictedCopy`：保留 conflicted copy，将原始版本移到系统 Trash。

输出 `ICloudConflictResolveReport`：

- `conflict_id`：已解决冲突 ID。
- `resolution`：实际应用的用户选择。
- `status`：最终冲突状态，成功时为 `Resolved`。
- `kept_paths`：仍保留的版本路径。
- `trashed_paths`：移入 Trash 的版本路径；`KeepBoth` 时为空。
- `undo_token`：Trash 相关解决可撤销时返回。
- `change_log_action`：本次写入的 change-log action。

副作用边界：

- `KeepBoth` 不移动、不删除、不覆盖任何版本，只写 conflict state 和 change log。
- `KeepOriginal` / `KeepConflictedCopy` 只能把未保留版本移到系统 Trash，
  不提供永久删除，不清空 Trash，不删除外部无关文件。
- 成功后写 conflict state、change log，并在 Trash 操作可撤销时写 undo action。
- 任一阶段失败必须保持 conflict unresolved；不得清除 Needs Review，也不得把
  失败项当作成功。
- 不实现导入冲突批量策略、通用 batch delete、平台 QuickLook、iCloud 下载触发
  或 Stage 4 云盘 SDK 集成。

错误：

- `ICloudPlaceholder`：必需版本仍是未下载占位符。
- `PermissionDenied`：Trash、目标文件、metadata 或 conflict state 写入被阻断。
- `Conflict`：preview 后版本集合或 conflict state 已变化，或 requested
  resolution 不再安全。
- `Io`：Trash、文件系统移动或失败回滚出错。
- `Db`：conflict state、change log 或 undo action 写入失败。

S2-20 可以从本合同得到成功后应移除 Needs Review 的状态、保留/Trash 路径、
Undo toast token 和失败时继续保持 unresolved 的判断依据。本合同没有引入
control map 之外的页面能力；S1-36 仍只消费 `list_icloud_conflicts`，S2-20
消费 preview / resolve。

### `preview_import_conflict_batch(repoPath, request) throws -> ImportConflictBatchPreviewReport`

```swift
let preview = try AreaMatrix.previewImportConflictBatch(
    repoPath: repoPath,
    request: request
)
applyButton.isEnabled = preview.canApply && !preview.replaceConfirmationRequired
```

`preview_import_conflict_batch` 是 C2-17 的只读批量导入冲突预览入口，
服务 `S2-21 import-conflict-batch`。输入 `ImportConflictBatchPreviewRequest`
包含：

- `import_session_id`：当前批量导入 staging session。
- `conflict_ids`：当前选择或作用域中的冲突项；为空必须返回 `FileNotFound`。
- `duplicate_strategy`：hash duplicate 行策略，默认应为 `Skip`。
- `same_name_strategy`：same-name different-content 行策略，默认应为 `KeepBoth`。
- `apply_to_all_similar_conflicts`：开启时按 conflict type 覆盖当前 session 内同类冲突；
  关闭时只覆盖 `conflict_ids` 对应行，未选行保持 pending。

输出 `ImportConflictBatchPreviewReport`：

- `preview_token`：绑定 session、scope、strategy、Trash 可用性和 inspected staging state。
- `duplicate_conflict_count` / `same_name_conflict_count`：分组数量。
- `included_count` / `pending_count` / `blocked_count`：当前作用域与阻断摘要。
- `replace_count` / `skip_count` / `keep_both_count` / `ask_per_item_count`：
  当前策略影响数量。
- `trash_available` / `undo_available`：Replace 和成功写入后 Undo 是否可用。
- `can_apply` / `apply_blocked_reason`：Apply 按钮状态和禁用原因。
- `replace_confirmation_required` / `replace_confirmation_summary`：Replace 二次确认状态。
- `items`：逐冲突预览行，包含 conflict type、existing/incoming/target path、选中策略、
  `Ready` / `Pending` / `NeedsConfirmation` / `Blocked` / `Failed` 状态、Index-only 阻断、
  risk summary 和原因文本。

副作用边界：

- 只读检查 import session、staging conflict rows、目标路径、hash/name conflict、Trash
  和 Undo 可用性。
- 不写 import session 决策，不 promote staging 文件，不移动、删除、Trash、覆盖或替换已有文件。
- 不写 `files`、`change_log`、`undo_actions`，不清空 staging，不 reindex，不更新 generated
  overview，不触发 iCloud 下载，不调用 AI/网络。
- Index-only 目标必须在 preview 中阻断 Replace；不得通过二次确认绕过。
- Ask-per-item 只作为输出状态和后续路由依据；本接口不打开 S1-22/S1-23/S1-24，也不执行逐项策略。

错误：

- `FileNotFound`：`import_session_id` 为空、`conflict_ids` 为空，或指定 session/conflict 已不存在。
- `Conflict`：策略组合无法安全预览、作用域与当前 staging state 无法绑定。
- `PermissionDenied`：metadata、staging、Trash 或目标路径 inspection 被权限阻断。
- `StagingRecoveryRequired`：存在未恢复的 staging residue 或 import session 状态不一致，必须先恢复。
- `Io`：staging 文件、目标路径、Trash preflight 或 metadata inspection 失败。
- `Db`：import session、conflict row、file row、Trash/undo 预检状态读取失败。

### `apply_import_conflict_batch(repoPath, request, previewToken) throws -> ImportConflictBatchApplyReport`

```swift
let report = try AreaMatrix.applyImportConflictBatch(
    repoPath: repoPath,
    request: confirmedRequest,
    previewToken: preview.previewToken
)
undoToast.present(token: report.undoToken)
```

`apply_import_conflict_batch` 是 C2-17 的执行入口，只能在 S2-21 完成 preview 和必要
Replace 二次确认后调用。输入 `ImportConflictBatchApplyRequest` 与 preview request 对齐，
并额外包含 `replace_confirmed`；当任一策略为 `Replace` 且该字段为 false 时必须返回
`Conflict`，不得写入任何状态。

输出 `ImportConflictBatchApplyReport`：

- `resolved_count`、`skipped_count`、`kept_both_count`、`replaced_count`、
  `queued_for_per_item_count`、`pending_count`、`failed_count`：执行摘要。
- `item_results`：逐冲突结果，`status` 为 `Skipped`、`KeptBoth`、`Replaced`、
  `QueuedForPerItem`、`Pending` 或 `Failed`，并携带 file id、final path 和错误摘要。
- `affected_file_ids`：成功写入或需要刷新状态的 file ids。
- `undo_token`：成功写入可撤销 replace / import 决策后返回；没有可撤销写入时为 `nil`。
- `change_log_actions`：成功行写入的 action 名称。
- `failure_summary`：部分失败后的恢复摘要，供 S2-21 `Retry failed` / `Ask per item` 使用。

副作用边界：

- `Skip` 对 hash duplicate 不导入重复内容，不删除、不移动、不覆盖已有文件；保持可追踪结果。
- `KeepBoth` 为 incoming 文件生成安全新名称并继续导入，不覆盖已有文件。
- `Replace` 必须在 `replace_confirmed = true` 且 Trash / recovery 可用时执行；旧文件必须进入
  Trash 或可恢复路径，写 change log 和 undo action。
- `AskPerItem` 不执行批量策略，只把当前作用域行保留为逐项处理队列状态。
- 未勾选或不在当前作用域的行保持 staging unresolved，不写 change log，不进入 Undo stack。
- 任一失败必须保留 staged 文件和冲突状态；不得清除 pending/unresolved，不得把失败项当成功。
- 不实现 iCloud conflict、Stage 4 sync conflict、通用 batch delete/rename/category、classifier rule、
  tag、search、AI 或 macOS UI 能力。

错误：

- `FileNotFound`：session/conflict 为空、非法或已不存在。
- `Conflict`：`preview_token` 缺失/过期，scope、strategy、Trash 可用性或 inspected staging state
  已变化，或 Replace 缺少二次确认。
- `PermissionDenied`：staging、Trash、目标文件、metadata、change log 或 undo 写入被权限阻断。
- `StagingRecoveryRequired`：Apply 前发现 staging residue 或 import session 状态需要恢复。
- `Io`：staging promote、Trash、文件系统写入或 rollback 失败。
- `Db`：import session 决策、`files`、`change_log` 或 `undo_actions` 写入失败。

页面消费状态：

- S2-21 可以从 preview 合同得到冲突分组、默认安全策略、全量/选中作用域、pending 行、
  Replace 数量、blocked 数量、Index-only 禁止 Replace、Trash/Undo 可用性、二次确认文案、
  Apply/Ask-per-item 是否可用和 VoiceOver 所需状态文本。
- S2-21 可以从执行报告得到成功/失败/跳过/替换/保留两份/pending/逐项队列摘要、刷新用
  `affected_file_ids`、`undo_token`、change log action 和失败恢复摘要。
- S2-10 / C2-07 只消费 `undo_token` 和后续 `list_undo_actions` / `undo_action` 状态。
- Ask-per-item 后续进入 S1-22 / S1-23 / S1-24 的路由由对应页面任务处理；本合同不新增
  control map 之外的页面能力。

---

## note API

### `read_note(repoPath, fileId) throws -> String?`

```swift
if let note = try AreaMatrix.readNote(repoPath: repoPath, fileId: entry.id) {
    detailView.noteEditor.text = note
}
```

无笔记时返回 `nil`。

### `write_note(repoPath, fileId, contentMd) throws`

```swift
@MainActor
func saveNote(_ entry: FileEntry, content: String) async {
    let inflightPath = "\(entry.path).md"
    await inflightTracker.mark(inflightPath)
    defer { Task { await inflightTracker.unmark(inflightPath) } }

    do {
        try await Task.detached {
            try AreaMatrix.writeNote(
                repoPath: repoPath,
                fileId: entry.id,
                contentMd: content
            )
        }.value
    } catch {
        await showAlert("保存笔记失败：\(error.localizedDescription)")
    }
}
```

应用同时写：

- DB `notes` 表
- 物理文件 `<filename>.md`（与文件同目录）

`InFlightTracker` 标记避免 watcher 把这次写视为外部变化（详见 [../architecture/fs-watcher.md](../architecture/fs-watcher.md)）。

---

## sync API

### `sync_external_changes(repoPath, events) throws -> SyncResult`

```swift
let coreEvents = events.map { e in
    ExternalEvent(
        path: e.relativePath,
        kind: e.kind,
        fsEventId: e.eventId
    )
}

let result = try await Task.detached {
    try AreaMatrix.syncExternalChanges(repoPath: repoPath, events: coreEvents)
}.value

print("created: \(result.detectedCreates), renamed: \(result.detectedRenames), deleted: \(result.detectedDeletes)")
appState.refreshList()
```

应用调用方在去抖 + InFlight 过滤后传入。详见 [../architecture/source-of-truth.md](../architecture/source-of-truth.md)。

### `get_fs_event_cursor(repoPath) throws -> Int64?`

```swift
let cursor = try AreaMatrix.getFsEventCursor(repoPath: repoPath)
let stream = startFSEventStream(sinceWhen: cursor ?? .now)
```

启动时调用，决定 FSEventStream 从哪个 event id 开始重放。

### `set_fs_event_cursor(repoPath, lastEventId) throws`

```swift
try AreaMatrix.setFsEventCursor(repoPath: repoPath, lastEventId: lastBatch.maxEventId)
```

每批 sync 完成后保存 cursor，断电后下次启动差量重放。

---

## CoreBridge 包装层（推荐做法）

UI 不直接调 `AreaMatrix.*`，而是通过应用层 `CoreBridge` actor 包装：

```swift
public actor CoreBridge {
    private let repoPath: String
    private let queue: TaskGroup<Void>?

    public init(repoPath: String) {
        self.repoPath = repoPath
    }

    public func bootstrap() async throws -> RecoveryReport {
        try AreaMatrix.initLogging(level: "info")
        return try AreaMatrix.recoverOnStartup(repoPath: repoPath)
    }

    public func importFile(from src: URL, options: ImportOptions) async throws -> FileEntry {
        try await Task.detached(priority: .userInitiated) { [repoPath] in
            try AreaMatrix.importFile(
                repoPath: repoPath,
                sourcePath: src.path,
                options: options
            )
        }.value
    }

    public func listFiles(filter: FileFilter) async throws -> [FileEntry] {
        try await Task.detached(priority: .userInitiated) { [repoPath] in
            try AreaMatrix.listFiles(repoPath: repoPath, filter: filter)
        }.value
    }

    public func tree(locale: String) async throws -> TreeNode {
        let json = try await Task.detached(priority: .userInitiated) { [repoPath] in
            try AreaMatrix.listTreeJson(repoPath: repoPath, locale: locale)
        }.value
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TreeNode.self, from: json.data(using: .utf8)!)
    }
}
```

详见 [../architecture/ffi-design.md](../architecture/ffi-design.md) 与 [uniffi-recipes.md](uniffi-recipes.md)。

---

## 调用规范

### 主线程禁忌

下列函数耗时不可预测，**必须**在 Swift 侧用 `Task.detached`：

- `import_file`（hash 大文件）
- `reindex_from_filesystem`（全扫）
- `create_diagnostics_snapshot`（可能复制损坏 metadata）
- `repair_metadata`（可能创建诊断并全扫）
- `resume_scan_session`（可能继续全扫）
- `recover_on_startup`（启动时）
- `list_tree_json`（大库）
- `list_icloud_conflicts`（扫描 iCloud conflicted copy）
- `preview_move_to_category`（目标路径和同名冲突预检）
- `move_to_category`（可能移动 repo-owned 文件）
- `add_tag` / `remove_tag`（写标签 metadata 和 change log）
- `sync_external_changes`（批量事件）

下列函数轻量，可同步调（< 5ms）：

- `get_version`
- `predict_category`
- `load_config`
- `get_latest_scan_session`
- `get_file`
- `list_tags`
- 单条 `list_files`（limit ≤ 50）

### 错误处理统一规约

Core 对 C1-21 暴露 `map_core_error(input: ErrorMappingInput) -> ErrorMapping`。
输入用 `ErrorKind` 加原始 `path` / `reason` / `message` 表示同一个
`CoreError` payload；输出固定包含 `kind`、`user_message`、`severity`、
`suggested_action`、`recoverability` 和 `raw_context`。该函数无文件系统、
数据库、日志或状态副作用，Swift `AppError` 只能基于这些结构化字段编排
本地化和展示，不得用字符串 contains 做主分支判断。

```swift
extension CoreError {
    var userMessage: String {
        switch self {
        case .Io(let msg):
            return "文件操作失败：\(msg)"
        case .Db:
            return "数据库错误，请尝试重启应用"
        case .DuplicateFile(let path):
            return "文件已存在：\(path)"
        case .InvalidPath(let path):
            return "无效路径：\(path)"
        case .ICloudPlaceholder(let path):
            return "iCloud 文件未下载：\(path)"
        case .PermissionDenied(let path):
            return "权限不足：\(path)"
        case .FileNotFound(let path):
            return "文件不存在：\(path)"
        case .RepoNotInitialized:
            return "请先初始化资料库"
        case .Conflict(let path):
            return "路径冲突：\(path)"
        case .Classify(let reason):
            return "分类失败：\(reason)"
        case .Config(let reason):
            return "配置错误：\(reason)"
        case .Internal(let msg):
            return "内部错误：\(msg)"
        }
    }
}
```

详见 [error-codes.md](error-codes.md)。

### 取消与超时

UniFFI 0.x 不支持 Rust 端 cooperative cancellation。Swift 端 `Task.cancel()` 不会立刻打断 Rust 调用。对策：

- 长任务（reindex / sync）拆成多次小调用
- 启动时显示 indeterminate 进度，超过 X 秒提示用户耐心
- 不为单次调用加 timeout

详见 [uniffi-recipes.md](uniffi-recipes.md)。

---

## 版本演进

| 版本 | 变化 |
|---|---|
| 0.1.x | MVP 接口，可能多次微调 |
| 0.2.x | 加 `search`、批量操作预览/执行、`undo` |
| 0.3.x | 加 `ai_predict`、`auto_naming` |
| 1.0.0 | 接口稳定承诺生效 |

---

## Related

- [error-codes.md](error-codes.md)
- [classifier-yaml.md](classifier-yaml.md)
- [uniffi-recipes.md](uniffi-recipes.md)
- [../architecture/adopt-existing-folders.md](../architecture/adopt-existing-folders.md)
- [../architecture/ffi-design.md](../architecture/ffi-design.md)
- [../modules/storage.md](../modules/storage.md)
- [../modules/classify.md](../modules/classify.md)
- [../modules/change-log.md](../modules/change-log.md)
- [../modules/tree-scan.md](../modules/tree-scan.md)
