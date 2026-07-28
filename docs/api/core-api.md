# Core API（UDL 接口规范）

> AreaMatrix Core 暴露给 Swift / Kotlin / Python 的所有函数与类型，权威定义。任何对外接口变化必须先改本文档与 `area_matrix.udl`。
>
> 阅读时长：约 16 分钟。

---

## 接口稳定性约定

| Contract generation | 状态 | 含义 |
|---|---|---|
| 0.1.x | unstable | 每个版本可能调整，使用方自担风险 |
| 1.0 起 | stable | 破坏性变化只在 MAJOR 版本发生 |
| 弃用流程 | — | 标记 `[Deprecated]` 至少保留一个 MINOR 版本 |

详见 [../architecture/ffi-design.md](../architecture/ffi-design.md)。

---

## 完整 UDL 文件

```idl
namespace area_matrix {
    string get_version();

    ObservabilityBuildContext get_observability_build_context();

    [Throws=CoreError]
    void init_logging(string level, CoreLogCallback callback);

    [Throws=CoreError]
    ObservabilityHealth initialize_observability(
        ObservabilityConfig config,
        CoreObservabilitySink sink
    );

    [Throws=CoreError]
    ObservabilityHealth update_observability_config(ObservabilityConfig config);

    ObservabilityHealth get_observability_health();

    [Throws=CoreError]
    ObservabilityHealth flush_observability(u64 deadline_ms);


    [Throws=CoreError]
    BindingContractReport inspect_binding_contract(BindingContractRequest request);

    // platform capabilities exposes platform capability rows. repository settings reuses
    // the same matrix to disable unsupported settings before config updates.
    [Throws=CoreError]
    PlatformCapabilities get_platform_capabilities(
        PlatformId platform, string app_version
    );

    [Throws=CoreError]
    RepoPathValidation validate_repo_path(string repo_path);

    [Throws=CoreError]
    RepoPathValidation validate_initialized_repo_path(string repo_path);

    [Throws=CoreError]
    void init_repo(string repo_path, RepoInitOptions options);

    // repository settings reads a revisioned snapshot.
    [Throws=CoreError]
    RepoConfigSnapshot load_repo_config(string repo_path);

    // repository settings submits dirty fields with compare-and-swap revision.
    [Throws=CoreError]
    RepoConfigSnapshot update_repo_config(string repo_path, RepoConfigPatch patch);

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
    RemoteProviderProbePlan prepare_remote_ai_provider_probe(
        string repo_path, RemoteProviderTestRequest request
    );

    [Throws=CoreError]
    RemoteProviderTestResult complete_remote_ai_provider_probe(
        string repo_path, RemoteProviderProbeObservation observation
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
    AiTagSuggestionReport suggest_tags_with_ai(
        string repo_path, AiTagSuggestionRequest request
    );

    [Throws=CoreError]
    AiTagSuggestionApplyReport apply_ai_tag_suggestions(
        string repo_path, ApplyAiTagSuggestionsRequest request
    );

    [Throws=CoreError]
    AiPrivacyRulesSnapshot list_ai_privacy_rules(string repo_path);

    [Throws=CoreError]
    AiPrivacyRulesSnapshot update_ai_privacy_rules(
        string repo_path, AiPrivacyRulesUpdateRequest request
    );

    [Throws=CoreError]
    AiPrivacyEvaluationReport evaluate_ai_privacy(
        string repo_path, AiPrivacyEvaluationRequest request
    );

    [Throws=CoreError]
    AiFallbackStatus get_ai_fallback_status(
        string repo_path, AiFallbackStatusRequest request
    );

    [Throws=CoreError]
    SemanticSearchResultPage semantic_search(
        string repo_path,
        string query,
        SearchFilter filter,
        SearchPagination pagination
    );

    [Throws=CoreError]
    SemanticIndexBuildReport build_embedding_index(
        string repo_path, SemanticIndexScope scope
    );

    [Throws=CoreError]
    RecoveryReport recover_on_startup(string repo_path);

    // manual rescan previews repository impact before rescan confirmation enables
    // the high-risk confirmation. Preview is read-only: it must not write
    // files, scan sessions, change log, or database file rows.
    [Throws=CoreError]
    ManualRescanPreviewReport preview_manual_rescan(string repo_path);

    // manual rescan reuses the full repository reindex entry point after
    // rescan confirmation has shown preview and the high-risk confirmation. The scope is
    // the entire repository; partial subtree rescan is not exposed by this
    // contract. Core must only update AreaMatrix metadata and must not move,
    // delete, rename, overwrite, trash, or download user files.
    [Throws=CoreError]
    ReindexReport reindex_from_filesystem(string repo_path);

    [Throws=CoreError]
    DiagnosticsSnapshot create_diagnostics_snapshot(string repo_path);

    [Throws=CoreError]
    RepairMetadataPreflight preflight_repair_metadata(string repo_path);

    [Throws=CoreError]
    RepairReport repair_metadata(string repo_path, RepairOptions options);

    // manual rescan consumers read the latest scan session to render manual rescan
    // progress, completion, failure, interruption, and retry state without
    // starting or resuming a scan.
    [Throws=CoreError]
    ScanSession? get_latest_scan_session(string repo_path);

    // manual rescan resumes an interrupted or failed whole-repository manual rescan
    // only after the UI has routed the user through rescan confirmation recovery flow.
    [Throws=CoreError]
    ReindexReport resume_scan_session(string repo_path, i64 scan_session_id);

    [Throws=CoreError]
    OverviewRegenerationPlan prepare_overview_regeneration(
        string repo_path, ContentLocale content_locale
    );

    [Throws=CoreError]
    OverviewRegenerationSession start_overview_regeneration(
        string repo_path, OverviewRegenerationStartRequest request
    );

    [Throws=CoreError]
    OverviewRegenerationSession commit_overview_regeneration(
        string repo_path, string operation_id
    );

    [Throws=CoreError]
    OverviewRegenerationSession get_overview_regeneration(
        string repo_path, string operation_id
    );

    [Throws=CoreError]
    OverviewRegenerationSession? recover_overview_regeneration_on_startup(
        string repo_path
    );

    [Throws=CoreError]
    OverviewRegenerationSession resume_overview_regeneration(
        string repo_path, string operation_id
    );

    [Throws=CoreError]
    OverviewRegenerationSession cancel_overview_regeneration(
        string repo_path, string operation_id
    );

    [Throws=CoreError]
    OverviewRegenerationSession rollback_overview_regeneration(
        string repo_path, string operation_id
    );

    [Throws=CoreError]
    OverviewLanguageStatus get_overview_language_status(
        string repo_path, ContentLocale content_locale
    );

    // desktop import flow reuses predict_category for read-only
    // Windows/Linux import preview state after the platform picker, drop
    // adapter, or optional shell entry has produced safe display names. Core
    // does not expand folders, run platform permission preflight, detect
    // Trash/Recycle Bin support, or manage multi-item progress here.
    [Throws=CoreError]
    ClassifyResult predict_category(string repo_path, string filename);

    // desktop import flow uses import_file_with_result for the final
    // committed single-item desktop import result. import_file remains the
    // backwards-compatible FileEntry entry point for existing callers.
    // The desktop result includes source removal status so Move can report
    // Imported, original retained without parsing errors or rolling back a
    // safely committed repository file. Replace confirmation belongs to
    // replace confirmation; this entry point does not add a desktop-only replace or
    // platform Trash API.
    [Throws=CoreError]
    FileEntry import_file(
        string repo_path, string source_path, ImportOptions options
    );

    [Throws=CoreError]
    ImportResult import_file_with_result(
        string repo_path, string source_path, ImportOptions options
    );

    [Throws=CoreError]
    FileEntry import_file_observed(
        string repo_path, string source_path, ImportOptions options,
        CoreTraceContext trace_context
    );

    [Throws=CoreError]
    ImportResult import_file_with_result_observed(
        string repo_path, string source_path, ImportOptions options,
        CoreTraceContext trace_context
    );

    // replace confirmation may compose this existing deletion contract only for
    // recoverable repo-owned discarded versions. Swift owns the host availability
    // probe and dangerous confirmation; Core owns the actual Trash mutation,
    // metadata/change-log/Undo commit, and failure rollback. There is no
    // hard-delete flag; platforms must disable Replace when Trash or a documented
    // safety backup is unavailable.
    [Throws=CoreError]
    void delete_file(string repo_path, i64 file_id);

    [Throws=CoreError]
    void remove_index_entry(string repo_path, i64 file_id);

    [Throws=CoreError]
    FileEntry rename_file(
        string repo_path, i64 file_id, string new_name, ContentLocale content_locale
    );

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
    ClassifierRuleEditorSnapshot list_classifier_rules(
        string repo_path, ContentLocale? editing_locale
    );

    [Throws=CoreError]
    ClassifierRuleEditorSnapshot create_default_classifier(
        string repo_path, boolean confirmed, ContentLocale? editing_locale
    );

    [Throws=CoreError]
    ClassifierRuleEditorSnapshot restore_default_classifier(
        string repo_path, boolean confirmed, ContentLocale? editing_locale
    );

    [Throws=CoreError]
    ClassifierRuleEditorSnapshot restore_last_valid_classifier(
        string repo_path, boolean confirmed, ContentLocale? editing_locale
    );

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

    // desktop main query reuses list_files, get_file, list_tree_json,
    // and search_files for Windows and Linux main-window state. Desktop
    // shells page through FileFilter.limit/offset and must not scan the repo
    // directly or hide watcher/import/recovery behavior behind this query set.
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
    MissingFileState get_missing_file_state(string repo_path, i64 file_id);

    [Throws=CoreError]
    MissingFileRecoveryReport relink_missing_file(
        string repo_path, MissingFileRelinkRequest request
    );

    [Throws=CoreError]
    MissingFileRecoveryReport remove_missing_file_record(
        string repo_path, MissingFileRemoveRecordRequest request
    );

    // mobile file detail composes get_file + list_changes + read_note.
    // FileEntry.availability_status lets mobile file detail surface route Missing to missing-file recovery surface
    // without platform-side metadata inference.
    [Throws=CoreError]
    sequence<ChangeLogEntry> list_changes(string repo_path, ChangeFilter filter);

    // desktop main query also uses this read-only tree JSON for desktop sidebar state.
    [Throws=CoreError]
    string list_tree_json(string repo_path, string locale);

    [Throws=CoreError]
    sequence<SyncConflict> detect_sync_conflicts(string repo_path);

    [Throws=CoreError]
    SyncConflictResolutionPreviewReport preview_sync_conflict_resolution(
        string repo_path,
        string conflict_id,
        SyncConflictResolutionStrategy resolution
    );

    [Throws=CoreError]
    SyncConflictResolveReport resolve_sync_conflict(
        string repo_path,
        string conflict_id,
        SyncConflictResolutionRequest resolution
    );

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
    CloudStorageState detect_cloud_storage_state(string repo_path);

    [Throws=CoreError]
    CloudStorageState acknowledge_onedrive_risk_notice(string repo_path);

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
    SyncResult sync_external_changes(
        string repo_path, sequence<ExternalEvent> events, ContentLocale content_locale
    );

    [Throws=CoreError]
    ExternalSyncLocaleRecoveryPlan? prepare_external_sync_locale_recovery(string repo_path);

    [Throws=CoreError]
    ExternalSyncLocaleRecoveryReport resolve_external_sync_locale_recovery(
        string repo_path, string recovery_token, ContentLocale content_locale
    );

    [Throws=CoreError]
    i64? get_fs_event_cursor(string repo_path);

    [Throws=CoreError]
    void set_fs_event_cursor(string repo_path, i64 last_event_id);

    [Throws=CoreError]
    PlatformWatcherSnapshot record_watcher_health(
        string repo_path, PlatformWatcherHealthSignal signal
    );

    ErrorMapping map_core_error(ErrorMappingInput input);
};

dictionary RepositoryLocalePolicySnapshot {
    RepositoryLocalePolicyState state;
    string raw_value;
};

dictionary RepoConfigSnapshot {
    string repo_path;
    i64 revision;
    StorageMode default_mode;
    OverviewOutput overview_output;
    boolean ai_enabled;
    RepositoryLocalePolicySnapshot locale_policy;
    boolean icloud_warn;
    boolean enable_extension_rules;
    boolean enable_keyword_rules;
    boolean fallback_to_inbox;
    boolean allow_replace_during_import;
};

dictionary RepoConfigPatch {
    i64 expected_revision;
    string? repo_path;
    StorageMode? default_mode;
    OverviewOutput? overview_output;
    boolean? ai_enabled;
    RepositoryLocalePolicy? locale_policy;
    boolean? icloud_warn;
    boolean? enable_extension_rules;
    boolean? enable_keyword_rules;
    boolean? fallback_to_inbox;
    boolean? allow_replace_during_import;
};

dictionary BindingContractRequest {
    BindingTargetPlatform target_platform;
    i64 binding_version;
};

dictionary BindingApiContract {
    string name;
    string capability;
    BindingSupportStatus status;
    string? reason;
};

dictionary BindingTypeMapping {
    string rust_type;
    string udl_type;
    string target_type;
    BindingSupportStatus status;
    string? reason;
};

dictionary BindingMissingCapability {
    string capability;
    string label;
    BindingSupportStatus status;
    string reason;
};

dictionary BindingContractReport {
    BindingTargetPlatform target_platform;
    i64 binding_version;
    string core_version;
    sequence<BindingApiContract> supported_apis;
    sequence<BindingTypeMapping> type_mappings;
    sequence<BindingMissingCapability> missing_capabilities;
};

dictionary PlatformCapabilitySupport {
    PlatformCapabilityStatus status;
    boolean ui_enabled;
    boolean requires_permission;
    string? reason;
};

dictionary PlatformCapabilities {
    PlatformId platform;
    string app_version;
    PlatformCapabilitySupport watcher;
    PlatformCapabilitySupport trash;
    PlatformCapabilitySupport share_extension;
    PlatformCapabilitySupport cloud_placeholder;
    PlatformCapabilitySupport security_bookmark;
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

dictionary RemoteProviderProbeHeader {
    string name;
    string value;
};

dictionary RemoteProviderProbePlan {
    RemoteAiProviderKind provider;
    string model_id;
    string? endpoint_url;
    string key_reference;
    string probe_token;
    RemoteProviderProbeMethod method;
    string url;
    sequence<RemoteProviderProbeHeader> headers;
    RemoteProviderProbeAuthorization authorization;
    u32 timeout_millis;
    u64 maximum_response_body_bytes;
    boolean follow_redirects;
};

dictionary RemoteProviderProbeObservation {
    string probe_token;
    RemoteProviderProbeOutcome outcome;
    u32? http_status;
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
    ContentLocale content_locale;
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
    string operation_id;
    string? retry_of_operation_id;
    i64 file_id;
    AiSummaryProviderScope provider_scope;
    AiSummaryContextPolicy context_policy;
    string? privacy_policy_ref;
    boolean regenerate_existing;
    ContentLocale content_locale;
};

dictionary AiSummaryDraft {
    string operation_id;
    ContentLocale content_locale;
    i64 format_contract_version;
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
    i64 expected_content_revision;
    boolean confirm_replace_user_owned;
    string summary_text;
    string? draft_id;
    AiSummaryRoute? route;
    string? model_name;
    i64? generated_at;
    sequence<AiSummaryInputField> used_context;
    string? privacy_rule_id;
    i64? call_log_id;
    AiContentOwnership ownership;
    string operation_id;
    ContentLocale content_locale;
    i64 format_contract_version;
};

dictionary AiSummarySaveReport {
    i64 file_id;
    i64 content_revision;
    AiContentOwnership ownership;
    string saved_summary;
    i64 saved_at;
    AiSummaryRoute? route;
    string? model_name;
    i64? generated_at;
    sequence<AiSummaryInputField> used_context;
    string? privacy_rule_id;
    i64? call_log_id;
    string operation_id;
    ContentLocale content_locale;
    i64 format_contract_version;
    i64 character_count;
};

dictionary AiSummaryClearRequest {
    i64 file_id;
    i64 expected_content_revision;
    boolean confirmed;
};

dictionary AiSummaryClearReport {
    i64 file_id;
    boolean cleared;
    i64 content_revision;
    i64 cleared_at;
};

dictionary AiTagSuggestionRequest {
    i64 file_id;
    sequence<string> candidate_tags;
    string? privacy_policy_ref;
    ContentLocale content_locale;
};

dictionary AiTagSuggestion {
    string suggestion_id;
    string slug;
    string display_name;
    f32 confidence;
    string reason;
    AiTagSuggestionCandidateStatus status;
    AiTagSuggestionMergeAction merge_action;
    string? matched_existing_slug;
    boolean selected_by_default;
    string? disabled_reason;
};

dictionary AiTagSuggestionReport {
    i64 file_id;
    AiTagSuggestionReportStatus status;
    sequence<AiTagSuggestion> suggestions;
    AiTagSuggestionRoute? route;
    string? model_name;
    i64? generated_at;
    sequence<AiTagSuggestionInputField> used_context;
    AiTagSuggestionSkipReason? skipped_reason;
    string? privacy_rule_id;
    i64? call_log_id;
    boolean requires_user_confirmation;
    f32 confidence_threshold;
    boolean contents_read;
    boolean ai_used;
    boolean network_used;
};

dictionary ApplyAiTagSuggestionItem {
    string suggestion_id;
    string slug;
    string display_name;
    f32 confidence;
    boolean edited_by_user;
    string? merge_target_slug;
};

dictionary ApplyAiTagSuggestionsRequest {
    i64 file_id;
    sequence<ApplyAiTagSuggestionItem> suggestions;
    i64? call_log_id;
    string? privacy_rule_id;
    boolean confirmed;
};

dictionary AiTagSuggestionApplyItemResult {
    string suggestion_id;
    string slug;
    AiTagSuggestionApplyStatus status;
    string? error;
};

dictionary AiTagSuggestionApplyReport {
    i64 file_id;
    i64 requested_count;
    i64 applied_count;
    i64 skipped_count;
    i64 failed_count;
    sequence<AiTagSuggestionApplyItemResult> item_results;
    TagSet tag_set;
    string? undo_token;
    i64? call_log_id;
    sequence<string> refresh_targets;
};

dictionary AiPrivacyRuleInput {
    string? rule_id;
    string name;
    AiPrivacyRuleKind kind;
    string pattern;
    AiPrivacyRuleAppliesTo applies_to;
    boolean enabled;
    string? description;
};

dictionary AiPrivacyRuleRecord {
    string rule_id;
    string name;
    AiPrivacyRuleKind kind;
    string pattern;
    AiPrivacyRuleAppliesTo applies_to;
    boolean enabled;
    string? description;
    i64 match_count;
    i64? last_matched_at;
};

dictionary AiPrivacyFieldRule {
    AiPrivacyInputField field;
    boolean allow_remote;
};

dictionary AiPrivacyFieldState {
    AiPrivacyInputField field;
    boolean allow_remote;
    i64 last_matched_count;
};

dictionary AiPrivacyProviderScopeSnapshot {
    boolean provider_configured;
    boolean provider_verified;
    boolean remote_provider_enabled;
    sequence<AiFeatureKind> feature_scope;
};

dictionary AiPrivacyRulesSnapshot {
    boolean privacy_gate_enabled;
    sequence<AiPrivacyRuleRecord> rules;
    sequence<AiPrivacyFieldState> remote_allowed_fields;
    AiPrivacyProviderScopeSnapshot provider_scope;
    i64? updated_at;
    boolean remote_blocked_by_default;
};

dictionary AiPrivacyRulesUpdateRequest {
    boolean privacy_gate_enabled;
    sequence<AiPrivacyRuleInput> rules;
    sequence<AiPrivacyFieldRule> remote_allowed_fields;
    AiPrivacyProviderScopeSnapshot provider_scope;
    boolean confirmed;
};

dictionary AiPrivacyEvaluationContext {
    i64? file_id;
    string? repo_relative_path;
    string? file_name;
    string? category;
    string? extension;
    sequence<string> tags;
};

dictionary AiPrivacyEvaluationRequest {
    AiFeatureKind feature;
    AiPrivacyEvaluationRoute route;
    sequence<AiPrivacyInputField> requested_fields;
    boolean privacy_gate_enabled;
    AiPrivacyProviderScopeSnapshot provider_scope;
    sequence<AiPrivacyRuleInput> rules;
    sequence<AiPrivacyFieldRule> remote_allowed_fields;
    AiPrivacyEvaluationContext context;
};

dictionary AiPrivacyRuleMatch {
    string rule_id;
    string name;
    AiPrivacyRuleKind kind;
    string pattern;
    AiPrivacyRuleAppliesTo applies_to;
    AiPrivacyInputField? matched_field;
};

dictionary AiPrivacyEvaluationReport {
    AiPrivacyDecision decision;
    AiPrivacySkippedReason? skipped_reason;
    AiPrivacyProviderGateReason? provider_gate_reason;
    sequence<AiPrivacyRuleMatch> matched_rules;
    AiPrivacyInputField? matched_field_type;
    sequence<AiPrivacyInputField> allowed_fields;
    sequence<AiPrivacyInputField> blocked_fields;
    sequence<AiPrivacyInputField> sent_fields;
    string message;
};

dictionary AiFallbackStatusRequest {
    AiFallbackOperation operation;
    AiCallLogRoute? route;
    AiFallbackProviderErrorKind? provider_error;
    string? provider_error_code;
    AiPrivacyDecision? privacy_decision;
    AiPrivacySkippedReason? privacy_skipped_reason;
    AiCategorySuggestionSkipReason? category_skipped_reason;
    SemanticSearchFallbackReason? semantic_fallback_reason;
    AiCallLogStatus? call_log_status;
    i64? call_log_id;
    string? privacy_rule_id;
    i64? retry_after;
};

dictionary AiFallbackStatus {
    AiFallbackOperation operation;
    AiFallbackKind kind;
    AiFallbackCategory category;
    string title;
    string message;
    boolean retryable;
    string? retry_disabled_reason;
    AiFallbackAction? primary_action;
    AiFallbackAction? secondary_action;
    AiFallbackAction non_ai_fallback_action;
    AiCallLogRoute? route;
    i64? call_log_id;
    string? privacy_rule_id;
    i64? retry_after;
};

dictionary SemanticSearchMatch {
    SearchFileResult result;
    f32 relevance;
    string matched_reason;
    sequence<SemanticSearchInputField> used_fields;
    SemanticSearchRoute route;
    boolean also_matched_normal_search;
    i64? call_log_id;
    string? privacy_rule_id;
};

dictionary SemanticNormalSearchMatch {
    SearchFileResult result;
    boolean deduped_by_semantic;
};

dictionary SemanticSearchResultPage {
    string query;
    i64 semantic_total_count;
    i64 normal_total_count;
    sequence<SemanticSearchMatch> semantic_matches;
    sequence<SemanticNormalSearchMatch> normal_matches;
    i64 deduped_normal_count;
    SemanticIndexStatus index_status;
    SemanticSearchRoute? route;
    SemanticSearchFallbackReason? fallback_reason;
    string? fallback_message;
    i64? call_log_id;
    string? privacy_rule_id;
    boolean low_confidence;
};

dictionary SemanticIndexScope {
    SearchFilter filter;
    SemanticSearchRoute? route;
    string? privacy_policy_ref;
    boolean confirmed;
};

dictionary SemanticIndexBuildReport {
    SemanticIndexStatus status;
    SemanticSearchRoute? route;
    i64 total_count;
    i64 processed_count;
    i64 skipped_count;
    i64 failed_count;
    i64 privacy_skipped_count;
    string? provider_name;
    i64? call_log_id;
    SemanticSearchFallbackReason? fallback_reason;
    string? message;
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
    RepositoryLocalePolicy locale_policy;
    ContentLocale content_locale;
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
    boolean is_onedrive_path;
    PlatformPathKind platform_path_kind;
    boolean is_case_sensitive_path;
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
    // desktop import flow and files import dialogs keep Replace hidden or
    // disabled until the separate replace confirmation proves
    // recoverability. Overwrite is the committed strategy token after that
    // confirmation, not the preview or platform Trash capability contract.
    DuplicateStrategy duplicate_strategy;
    ContentLocale content_locale;
};

dictionary ImportResult {
    FileEntry entry;
    ImportSourceRemovalStatus source_removal_status;
    string? source_removal_failure;
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

enum ClassifierConfigHealth { "Valid", "Missing", "Unreadable", "Invalid" };

enum ClassifierRecoveryAction { "CreateDefault", "RestoreDefault", "RestoreLastValid" };

dictionary ClassifierRuleRecord {
    string rule_id;
    string slug;
    sequence<ClassifierLocaleValue> display_names;
    sequence<ClassifierLocaleValue> descriptions;
    sequence<string> extensions;
    sequence<string> keywords;
    i64 priority;
    string? naming_template;
    boolean is_default;
};

dictionary ClassifierLocaleValue {
    string locale;
    string value;
};

dictionary ClassifierRuleEditorSnapshot {
    sequence<ClassifierRuleRecord> rules;
    string default_rule_id;
    string? updated_rule_id;
    string repository_locale_policy;
    ContentLocale? editing_locale;
    ClassifierConfigHealth health;
    sequence<ClassifierRecoveryAction> recovery_actions;
    string? warning;
};

dictionary ClassifierRuleCreateRequest {
    string repository_locale_policy;
    ContentLocale editing_locale;
    string slug;
    string display_name;
    string description;
    sequence<string> extensions;
    sequence<string> keywords;
    i64 priority;
    string? naming_template;
};

dictionary ClassifierRuleUpdate {
    string repository_locale_policy;
    ContentLocale editing_locale;
    string rule_id;
    ClassifierRuleObservedState observed;
    string slug;
    string display_name;
    string description;
    sequence<string> extensions;
    sequence<string> keywords;
    i64 priority;
    string? naming_template;
    boolean preview_confirmed;
};

dictionary ClassifierRuleObservedState {
    string rule_id;
    string slug;
    string display_name;
    string description;
    sequence<string> extensions;
    sequence<string> keywords;
    i64 priority;
    string? naming_template;
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
    FileAvailabilityStatus availability_status;
    i64 imported_at;
    i64 updated_at;
};

dictionary MissingFileState {
    i64 file_id;
    string relative_path;
    string? last_known_path;
    i64? last_seen_at;
    MissingFileReason reason;
    string? expected_hash_sha256;
    boolean can_locate;
    boolean can_try_again;
    boolean can_remove_record;
    boolean remove_record_requires_confirmation;
    boolean can_run_rescan;
    string? rescan_disabled_reason;
};

dictionary MissingFileRelinkRequest {
    i64 file_id;
    string new_path;
    boolean confirmed;
};

dictionary MissingFileRemoveRecordRequest {
    i64 file_id;
    boolean confirmed;
};

dictionary MissingFileRecoveryReport {
    i64 file_id;
    MissingFileRecoveryStatus status;
    string? previous_path;
    string? current_path;
    boolean hash_matched;
    boolean record_removed;
    boolean file_deleted;
    string? change_log_action;
    string? message;
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

dictionary SyncConflictAffectedFile {
    string path;
    i64? file_id;
    SyncConflictFileRole role;
    i64? size_bytes;
    i64? modified_at;
    string? hash_sha256;
    string? source_platform;
};

dictionary SyncConflict {
    string conflict_id;
    SyncConflictType conflict_type;
    SyncConflictSeverity severity;
    SyncConflictStatus status;
    string primary_path;
    sequence<SyncConflictAffectedFile> affected_files;
    i64 version_count;
    string? source_provider;
    i64? detected_at;
    string? summary;
};

dictionary SyncConflictVersionImpact {
    string path;
    i64? file_id;
    SyncConflictFileRole role;
    boolean will_keep;
    boolean will_be_canonical;
    boolean will_remain_user_visible;
    boolean will_move_to_trash;
    string? recovery_target;
    string? reason;
};

dictionary SyncConflictReplacePlan {
    string old_path;
    string new_path;
    string? old_hash_sha256;
    string? new_hash_sha256;
    i64? affected_file_id;
    string? backup_target;
    string database_update;
    string change_log_action;
    string recovery_note;
};

dictionary SyncConflictResolutionPreviewReport {
    string conflict_id;
    SyncConflictResolutionStrategy resolution;
    SyncConflictResolutionStrategy default_resolution;
    SyncConflictStatus status_after;
    sequence<SyncConflictVersionImpact> version_impacts;
    sequence<string> kept_paths;
    sequence<string> retained_paths;
    sequence<string> planned_trash_paths;
    sequence<i64> affected_file_ids;
    string? canonical_path;
    string change_log_action;
    boolean destructive;
    boolean requires_replace_confirmation;
    boolean trash_required;
    boolean trash_available;
    boolean can_apply;
    string? blocked_reason;
    string? preview_token;
    SyncConflictReplacePlan? replace_plan;
};

dictionary SyncConflictResolutionRequest {
    SyncConflictResolutionStrategy strategy;
    string preview_token;
    boolean replace_confirmed;
    string? replace_confirmation_id;
};

dictionary SyncConflictResolveReport {
    string conflict_id;
    SyncConflictResolutionStrategy resolution;
    SyncConflictStatus status;
    sequence<string> kept_paths;
    sequence<string> retained_paths;
    sequence<string> trashed_paths;
    sequence<i64> affected_file_ids;
    string change_log_action;
    string? undo_token;
    i64? resolved_at;
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

dictionary CloudStorageState {
    string repo_path;
    CloudStorageProviderKind provider_kind;
    CloudStorageRiskLevel risk;
    CloudPlaceholderState placeholder_state;
    CloudPermissionState permission_state;
    string status_summary;
    sequence<string> risk_reasons;
    CloudStorageRecommendedAction recommended_action;
    boolean requires_notice_acknowledgement;
    boolean notice_acknowledged;
    boolean can_retry;
    boolean requires_reconnect;
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

dictionary ManualRescanPreviewItem {
    ManualRescanPreviewItemKind kind;
    string relative_path;
    string reason;
    string suggested_action;
};

dictionary ManualRescanPreviewReport {
    i64 added;
    i64 updated;
    i64 missing_or_deleted_from_fs;
    i64 renamed_candidates;
    i64 conflicts;
    i64 unreadable;
    i64 unknown;
    i64 skipped;
    string snapshot_id;
    i64 created_at;
    boolean is_stale;
    sequence<ManualRescanPreviewItem> items;
};

dictionary ReindexReport {
    i64? scan_session_id;
    i64 inserted;
    i64 updated;
    i64 missing;
    i64 conflicts;
    i64 unreadable;
    i64 unknown;
    i64 skipped;
    sequence<string> errors;
};

dictionary RepairOptions {
    boolean preserve_diagnostics_snapshot;
    string preflight_token;
    string repository_locale_policy;
};

dictionary RepairMetadataPreflight {
    RepairMetadataLocaleState locale_state;
    string? repository_locale_policy;
    string? unsupported_locale;
    boolean requires_explicit_locale_selection;
    string preflight_token;
};

dictionary DiagnosticsSnapshot {
    string snapshot_path;
    i64 created_at;
    sequence<string> warnings;
};

dictionary RepairReport {
    string? diagnostics_snapshot_path;
    RepairMetadataOutcome outcome;
};

dictionary ScanSession {
    i64 id;
    ScanSessionKind kind;
    ScanSessionStatus status;
    string? last_path;
    i64 inserted;
    i64 updated;
    i64 missing;
    i64 conflicts;
    i64 unreadable;
    i64 unknown;
    i64 skipped;
    i64 started_at;
    i64 updated_at;
    i64? finished_at;
    sequence<string> errors;
};

dictionary RecoverableOperationContext {
    string operation_id;
    string? retry_of_operation_id;
    string operation_code;
    string operation_payload_json;
    ContentLocale? content_locale;
    i64 repository_revision;
    i64 format_contract_version;
    string? target_set_hash;
    i64 run_sequence;
};

dictionary OverviewRegenerationPlan {
    string operation_id;
    string plan_token;
    i64 repository_revision;
    ContentLocale content_locale;
    i64 format_contract_version;
    string target_set_hash;
    i64 target_count;
    i64 create_count;
    i64 replace_count;
    i64 delete_count;
    boolean includes_root_areamatrix_file;
    sequence<string> warnings;
};

dictionary OverviewRegenerationStartRequest {
    string operation_id;
    string plan_token;
    i64 expected_repository_revision;
    boolean confirmed;
};

dictionary OverviewRegenerationSession {
    RecoverableOperationContext context;
    OverviewRegenerationStatus status;
    i64 target_count;
    i64 staged_count;
    i64 applied_count;
    i64 restored_count;
    boolean cancellation_allowed;
    string? error_code;
    i64 created_at;
    i64 updated_at;
    i64? finished_at;
};

dictionary OverviewLanguageStatus {
    OverviewLanguageState state;
    ContentLocale content_locale;
    i64 target_count;
    i64 known_target_count;
    i64 missing_target_count;
    i64 obsolete_target_count;
    sequence<ContentLocale> known_locales;
    sequence<i64> known_format_versions;
    sequence<OverviewRegenerationReason> reasons;
};

dictionary ExternalEvent {
    string path;
    ExternalEventKind kind;
    i64 fs_event_id;
};

dictionary ExternalSyncLocaleRecoveryReceipt {
    i64 event_id;
    ExternalEventKind kind;
    string path;
};

dictionary ExternalSyncLocaleRecoveryPlan {
    string recovery_token;
    i64? cursor;
    sequence<ExternalSyncLocaleRecoveryReceipt> receipts;
};

dictionary ExternalSyncLocaleRecoveryReport {
    i64 recovered_receipts;
    ContentLocale content_locale;
};

dictionary SyncResult {
    i64 detected_creates;
    i64 detected_renames;
    i64 detected_deletes;
    i64 detected_modifies;
    sequence<string> errors;
};

dictionary PlatformWatcherEventSample {
    string path;
    ExternalEventKind kind;
    i64 fs_event_id;
    i64? occurred_at;
};

dictionary PlatformWatcherHealthSignal {
    PlatformWatcherBackend backend;
    PlatformWatcherStatus status;
    string watched_path;
    i64? last_event_id;
    i64? last_event_at;
    i64? last_sync_event_id;
    i64? last_sync_at;
    i64? last_rescan_at;
    i64 pending_event_count;
    i64? watch_count;
    string? error_summary;
    sequence<PlatformWatcherHealthReason> health_reasons;
    sequence<PlatformWatcherEventSample> recent_events;
    i64 reported_at;
};

dictionary PlatformWatcherSnapshot {
    string repo_path;
    PlatformWatcherBackend backend;
    PlatformWatcherStatus status;
    string watched_path;
    i64? last_event_id;
    i64? last_event_at;
    i64? last_sync_event_id;
    i64? last_sync_at;
    i64? last_rescan_at;
    i64 pending_event_count;
    i64? watch_count;
    string? error_summary;
    sequence<PlatformWatcherHealthReason> health_reasons;
    sequence<PlatformWatcherEventSample> recent_events;
    i64 reported_at;
};

dictionary ErrorMappingInput {
    ErrorKind kind;
    string? path;
    string? reason;
    string? message;
    i64? expected_revision;
    i64? current_revision;
};

dictionary ErrorArgument {
    string name;
    string value;
};

dictionary ErrorMapping {
    ErrorKind kind;
    string code;
    string? field;
    sequence<ErrorArgument> arguments;
    sequence<string> recovery_action_ids;
    ErrorSeverity severity;
    ErrorRecoverability recoverability;
    string? technical_details;
};

enum StorageMode { "Moved", "Copied", "Indexed" };
enum ImportSourceRemovalStatus { "NotRequested", "Removed", "Retained" };
enum FileOrigin { "Imported", "Adopted", "External" };
enum FileAvailabilityStatus { "Available", "Missing" };
enum RepoInitMode { "CreateEmpty", "AdoptExisting" };
enum RepoPathIssue {
    "MissingPath", "NotDirectory", "NotReadable", "NotWritable",
    "NonEmptyDirectory", "AlreadyInitialized", "InsideAreaMatrix",
    "ICloudPath", "OneDrivePath", "WindowsReservedName",
    "WindowsCaseInsensitive", "UnfinishedScanSession"
};
enum PlatformPathKind { "Local", "ICloudDrive", "OneDrive", "NetworkShare", "Unknown" };
enum OverviewOutput { "GeneratedOnly", "RootAreaMatrixFile" };
enum ContentLocale { "ZhHans", "En" };
enum RepositoryLocalePolicy { "FollowInterface", "ZhHans", "En" };
enum RepositoryLocalePolicyState { "Unknown", "FollowInterface", "ZhHans", "En", "Unsupported" };
enum RepairMetadataLocaleState {
    "Healthy", "MetadataAbsent", "DatabaseMissing", "DatabaseCorrupt",
    "LocaleMissing", "LocaleUnsupported"
};
enum RepairMetadataOutcome { "Verified", "Initialized", "Rebuilt" };
enum BindingTargetPlatform { "Swift", "Kotlin", "Python" };
enum BindingSupportStatus { "Supported", "Limited", "Missing" };
enum PlatformId { "Macos", "Ios", "Windows", "Linux", "Unknown" };
enum PlatformCapabilityStatus { "Available", "Limited", "NotAvailable", "Unknown" };
enum AiProviderPreference { "LocalFirst", "LocalOnly", "RemoteFirst" };
enum AiFeatureKind {
    "ClassificationSuggestions", "AutoSummaries", "AutoTags", "SemanticSearch"
};
enum RemoteAiProviderKind { "OpenAi", "Anthropic", "Other" };
enum RemoteProviderProbeMethod { "Get" };
enum RemoteProviderProbeAuthorization { "Bearer", "AnthropicApiKey" };
enum RemoteProviderProbeOutcome {
    "HttpResponse", "ConnectionFailed", "CredentialUnavailable"
};
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
enum AiContentOwnership { "Generated", "UserOwned" };
enum AiSummaryDraftStatus { "Draft", "Skipped", "Unavailable" };
enum AiSummarySkipReason {
    "AiDisabled", "FeatureDisabled", "ProviderUnavailable",
    "PrivacyRule", "NoEligibleInput", "CallLogUnavailable"
};
enum AiTagSuggestionRoute { "Local", "Remote" };
enum AiTagSuggestionInputField {
    "FileName", "RepoRelativePath", "ExtractedTextExcerpt",
    "AiSummary", "NoteSummary", "ExistingTags", "TagRegistry"
};
enum AiTagSuggestionReportStatus {
    "Suggested", "NoSuggestion", "Skipped", "Unavailable"
};
enum AiTagSuggestionSkipReason {
    "AiDisabled", "FeatureDisabled", "ProviderUnavailable",
    "PrivacyRule", "NoEligibleInput", "CallLogUnavailable"
};
enum AiTagSuggestionCandidateStatus {
    "Suggested", "LowConfidence", "AlreadyApplied", "Invalid", "Blocked"
};
enum AiTagSuggestionMergeAction {
    "CreateTag", "UseExistingTag", "MergeWithExistingTag"
};
enum AiTagSuggestionApplyStatus { "Applied", "AlreadyAdded", "Failed" };
enum AiPrivacyRuleKind { "Folder", "Category", "Keyword", "Extension", "Tag" };
enum AiPrivacyRuleAppliesTo { "RemoteAi", "LocalAndRemoteAi" };
enum AiPrivacyEvaluationRoute { "Local", "Remote" };
enum AiPrivacyInputField {
    "FileName", "RepoRelativePath", "Extension", "ExtractedTextExcerpt",
    "AiSummary", "NoteSummary", "TagCategoryContext"
};
enum AiPrivacyDecision { "Allowed", "Denied", "Skipped" };
enum AiPrivacySkippedReason {
    "PrivacyGateDisabled", "ScopeNotAllowed", "ProviderNotConfigured",
    "ProviderNotVerified", "ProviderDisabled", "PrivacyRule", "FieldRule",
    "NoEligibleInput"
};
enum AiPrivacyProviderGateReason {
    "PrivacyGateDisabled", "ScopeNotAllowed", "ProviderNotConfigured",
    "ProviderNotVerified", "ProviderDisabled"
};
enum AiFallbackOperation {
    "ClassificationSuggestion", "SemanticSearch", "EmbeddingIndexBuild"
};
enum AiFallbackProviderErrorKind {
    "LocalModelNotReady", "RemoteNotConfigured", "RemoteFailed",
    "ProviderUnavailable", "RateLimited", "Timeout", "CallLogUnavailable",
    "InternalFailure"
};
enum AiFallbackKind {
    "AiDisabled", "FeatureDisabled", "LocalModelNotReady",
    "RemoteNotConfigured", "RemoteFailed", "ProviderUnavailable",
    "PrivacySkipped", "SemanticIndexNotReady", "NoEligibleInput",
    "NormalSearchUnavailable", "CallLogUnavailable", "RateLimited",
    "Timeout", "InternalFailure"
};
enum AiFallbackCategory {
    "Disabled", "Skipped", "Unavailable", "Error"
};
enum AiFallbackAction {
    "Retry", "RetryLater", "OpenAiSettings", "OpenLocalModelStatus",
    "ConfigureRemoteAi", "ViewPrivacyRule", "ViewCallLog",
    "BuildSemanticIndex", "UseNormalSearch", "ClassifyManually"
};
enum SemanticSearchRoute { "Local", "Remote" };
enum SemanticSearchInputField {
    "FileName", "RepoRelativePath", "Category", "NoteSummary",
    "AiSummary", "ExtractedTextExcerpt"
};
enum SemanticIndexStatus {
    "Ready", "NotReady", "Building", "Paused", "Canceled", "Failed", "Partial"
};
enum SemanticSearchFallbackReason {
    "AiDisabled", "FeatureDisabled", "ProviderUnavailable", "PrivacyRule",
    "SemanticIndexNotReady", "CallLogUnavailable", "NoEligibleInput",
    "NormalSearchUnavailable", "RateLimited", "Timeout"
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
enum OverviewRegenerationStatus {
    "Running", "Staging", "ReadyToCommit", "Committing", "Completed",
    "RollbackRequired", "RolledBack", "Failed", "Canceled"
};
enum OverviewLanguageState {
    "NotGenerated", "Synchronized", "NeedsRegeneration", "Mixed", "Unknown"
};
enum OverviewRegenerationReason {
    "LocaleMismatch", "FormatMismatch", "MissingTargets", "ObsoleteTargets"
};
enum ManualRescanPreviewItemKind {
    "Added", "Updated", "Missing", "RenamedCandidate",
    "Conflict", "Unreadable", "Unknown", "Skipped"
};
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
enum SyncConflictStatus { "NeedsReview", "Resolved" };
enum SyncConflictType {
    "SameNameDifferentContent", "ConcurrentModification", "MetadataMismatch",
    "MissingVersion", "Unknown"
};
enum SyncConflictSeverity { "Low", "Medium", "High" };
enum SyncConflictFileRole {
    "Existing", "Incoming", "ConflictCopy", "Missing", "Unknown"
};
enum SyncConflictResolutionStrategy { "KeepBoth", "UseExisting", "UseIncoming" };
enum MissingFileReason {
    "PathMissing", "PermissionDenied", "CloudPlaceholder",
    "ExternalVolumeDisconnected", "Unknown"
};
enum MissingFileRecoveryStatus {
    "Missing", "Present", "Relinked", "HashMismatch", "RecordRemoved", "Blocked"
};
enum ICloudConflictStatus { "NeedsReview", "Resolved" };
enum ICloudConflictVersionRole { "Original", "ConflictedCopy" };
enum ICloudConflictPreviewStatus { "Available", "MetadataOnly", "Unavailable" };
enum ICloudConflictResolution { "KeepBoth", "KeepOriginal", "KeepConflictedCopy" };
enum CloudStorageProviderKind { "Local", "ICloudDrive", "OneDrive", "Unknown" };
enum CloudStorageRiskLevel { "NoRisk", "Low", "Medium", "High", "Unknown" };
enum CloudPlaceholderState { "NotPlaceholder", "Placeholder", "Unknown" };
enum CloudPermissionState { "Accessible", "PermissionDenied", "AccessExpired", "Unknown" };
enum CloudStorageRecommendedAction {
    "None", "AcknowledgeNotice", "RetryStatusCheck", "ReconnectFolder", "ChooseLocalFolder"
};
enum ImportConflictBatchConflictType { "DuplicateHash", "SameNameDifferentContent" };
enum ImportConflictBatchStrategy { "Skip", "KeepBoth", "Replace", "AskPerItem" };
enum ImportConflictBatchPreviewStatus {
    "Ready", "Pending", "NeedsConfirmation", "Blocked", "Failed"
};
enum ImportConflictBatchResultStatus {
    "Skipped", "KeptBoth", "Replaced", "QueuedForPerItem", "Pending", "Failed"
};
enum ExternalEventKind { "Created", "Removed", "Modified", "Renamed" };
enum PlatformWatcherBackend { "ReadDirectoryChangesW", "Inotify", "Unknown" };
enum PlatformWatcherStatus { "Starting", "Running", "Paused", "Error", "Unavailable" };
enum PlatformWatcherHealthReason {
    "PermissionDenied", "PathMissing", "BackendUnavailable", "DatabaseLocked",
    "LimitExceeded", "NetworkMount", "CloudSyncNoise", "Unknown"
};
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
    "Io", "Db", "DbLocked", "DbCorrupted", "Config", "Validation", "Classify", "Conflict", "RevisionConflict", "DuplicateFile",
    "FileNotFound", "ExpiredAction", "RepoNotInitialized", "InvalidPath",
    "ICloudPlaceholder", "StagingRecoveryRequired", "PermissionDenied", "Internal"
};
enum ErrorSeverity { "Low", "Medium", "High", "Critical" };
enum ErrorRecoverability {
    "Retryable", "UserActionRequired", "RefreshRequired", "Fatal"
};

[Error]
// error mapping contract: Swift maps these structured cases instead of
// branching on localized strings or string-contains checks.
interface CoreError {
    Io(string message);
    Db(string message);
    DbLocked(string message);
    DbCorrupted(string message);
    Config(string reason);
    Validation(string reason);
    Classify(string reason);
    Conflict(string path);
    RevisionConflict(string resource, i64 expected_revision, i64 current_revision);
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

dictionary CoreLogRecord {
    string level;
    string message;
    string? target;
    string? thread_name;
    string? repo_path;
};

callback interface CoreLogCallback {
    void on_log(CoreLogRecord record);
};

enum ObservabilityMode {
    "Disabled",
    "Standard",
    "Diagnostic",
    "Developer"
};

enum ObservabilitySeverity {
    "Trace",
    "Debug",
    "Info",
    "Warn",
    "Error"
};

enum ObservabilityLayer {
    "SwiftUi",
    "Platform",
    "Bridge",
    "Core",
    "Database",
    "Filesystem",
    "Network"
};

enum ObservabilityOutcome {
    "None",
    "Started",
    "Succeeded",
    "Failed",
    "Cancelled",
    "Skipped",
    "Degraded"
};

enum ObservabilityPrivacy {
    "Public",
    "Pseudonymous",
    "Sensitive",
    "Prohibited"
};

dictionary ObservabilityConfig {
    string session_id;
    ObservabilityMode mode;
    ObservabilitySeverity minimum_severity;
    u64 queue_capacity;
    boolean include_sensitive;
};

dictionary ObservabilityBuildContext {
    string producer;
    string version;
    string? build;
    string configuration;
    string platform;
    string architecture;
};

dictionary CoreTraceContext {
    string session_id;
    string trace_id;
    string? parent_span_id;
    string? incident_id;
    string? operation_id;
    string? retry_of_operation_id;
    string action_id;
    string component_id;
    sequence<CoreObservabilityResourceRef> resource_refs;
    sequence<CoreObservabilityAttribute> attributes;
};

dictionary CoreObservabilityAttribute {
    string key;
    string value;
    ObservabilityPrivacy privacy;
};

dictionary CoreObservabilityResourceRef {
    string resource_id;
    string alias;
    string? extension;
    string? size_bucket;
    string? storage_mode;
};

dictionary CoreObservabilityError {
    string code;
    string? kind;
    string? technical_details;
};

dictionary CoreObservabilityEvent {
    u64 schema_version;
    string event_id;
    i64 wall_timestamp_ms;
    u64 monotonic_timestamp_ns;
    u64 sequence_number;
    string session_id;
    string? incident_id;
    string trace_id;
    string span_id;
    string? parent_span_id;
    string? operation_id;
    string? retry_of_operation_id;
    string action_id;
    string component_id;
    ObservabilityLayer layer;
    string phase;
    ObservabilitySeverity severity;
    ObservabilityOutcome outcome;
    u64? duration_ms;
    sequence<CoreObservabilityResourceRef> resource_refs;
    CoreObservabilityError? error;
    sequence<CoreObservabilityAttribute> attributes;
    ObservabilityPrivacy privacy_level;
    string? message;
    string? target;
    string? thread_name;
    ObservabilityBuildContext build_context;
};

dictionary ObservabilityHealth {
    boolean initialized;
    ObservabilityMode mode;
    u64 queue_depth;
    u64 queue_capacity;
    u64 dropped_trace;
    u64 dropped_debug;
    u64 dropped_info;
    u64 dropped_warn;
    u64 dropped_error;
    u64 redaction_rejected;
    boolean callback_connected;
    boolean degraded;
    string? degraded_reason;
};

callback interface CoreObservabilitySink {
    void on_event(CoreObservabilityEvent event);
};
```

`RepoConfigSnapshot.locale_policy` 是资料库内容语言 policy，不控制 macOS 应用界面。规范持久化值为
`system`、`zh-Hans`、`en`；`system` 表示在每个新 operation 开始时跟随当前已解析的界面语言。平台层
兼容读取 `zh-CN` / `zh-SG`、`en-*` 等已知别名，但普通读取不得隐式写回。未知非空值必须保持 exact raw
value（精确原值）可见；已知显式/alias policy 的树和分类显示按 exact raw locale -> canonical concrete locale
-> `en` -> slug 回退，`system` 从平台传入的 current concrete locale 开始，unknown policy 只读浏览按 exact raw
locale -> `en` -> slug 回退。任何普通 mutation、新生成或内容写入都返回 `CoreError.Config`，直到用户明确提交支持的 policy。
locale canonicalization 是单独的显式 patch，不能夹带其他字段。custom classifier locale map 可以稀疏；
Core 不自动翻译缺失项，也不把跨语言近义 tag/category 做语义合并。

`RepoConfigSnapshot.revision` 是资料库配置的单调版本。Repository 设置只提交
`RepoConfigPatch.expected_revision` 加 dirty fields；Core 使用 SQLite immediate transaction 做 CAS。版本不
匹配时返回稳定 `repo_config_revision_conflict` code 和 expected/current revision，不写入任何字段；成功 patch
只递增一次 revision。最新 snapshot 通过显式 `load_repo_config` 获取，不嵌入 exception。多个窗口的 draft
不共享，旧窗口保留 dirty fields，并由用户选择 Reload latest 或 review 后基于新 revision 显式保存。

`AppLanguage.system` 的平台解析只检查 preferred languages 第一项：Simplified Chinese aliases 解析为
`zh-Hans`，`en-*` 解析为 `en`，其他第一项直接回退 `en`，不得扫描后续项。Core 不接收 macOS region。
瞬时应用 UI 的日期、数字、文件大小和货币由平台层按 `Locale.autoupdatingCurrent` 格式化；持久化
generated content 必须只依赖 concrete content locale 和稳定输入，以确定性日期、数值、大小与货币格式
输出，不能因运行或重放设备的 region 改变。

`ContentLocale` 与 repair 专用的 operation locale 都是 operation snapshot（操作快照），不是另一份持久化
设置。正式值只能是 `zh-Hans` 或 `en`，其他输入返回 `CoreError.Config`。新 attempt
在入口线性化点读取一次设置：设置提交要么完整发生在快照之前，要么完整发生在快照之后；一个用户 batch
只使用一个 locale。continuation、resume、replay、同一个 external sync window 和 automatic provider
fallback 必须复用原快照；用户显式开始的新 attempt 才重新捕获，按钮文案是否叫 Retry 不参与身份判断。
external window 在首次到达队首并准备第一次 Core 调用时冻结，AI 在进入 privacy/provider await 前冻结。

Core 不保存或读取进程级界面语言，也不在操作执行过程中重新解析语言。运行时 payload 必须显式携带
冻结值；更新任一语言设置本身不重写已有概览或 AI 摘要，之后正常发生且本来需要更新派生内容的
operation 可以使用新快照。

任何可在进程重启后继续的 Core 或平台 session 都必须在首次副作用/远程调用前持久化
`RecoverableOperationContext`。每次用户触发的 attempt 只有一个 `operation_id`；终态 Retry 创建新 ID 并以
`retry_of_operation_id` 关联，resume/replay/rollback 复用旧 ID，内部重入只递增 `run_sequence`，远程调用
另用 `call_id`。不暴露语义重叠的 `attempt_id`。

context 保存稳定 operation code、规范 payload、concrete locale、Repository revision、format version 和
target-set hash。payload 只包含恢复必需的 options、稳定标识或 hash，不保存 API key、完整 prompt，或仅为
恢复而复制可安全重建的用户正文。不得持久化 `AppDisplayText`、`LocalizedMessage`、catalog key 或翻译结果。
unknown field/code、非法 locale 或缺失必需字段均 fail closed。legacy session 不从当前设置补猜；需要该字段
才能继续时要求新 operation。`ScanSession.operation_context` 对不生成内容的历史 session 可以为 `nil`。

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
| `BindingTargetPlatform` | `enum BindingTargetPlatform` | `enum BindingTargetPlatform` | `enum class BindingTargetPlatform` |
| `BindingSupportStatus` | `enum BindingSupportStatus` | `enum BindingSupportStatus` | `enum class BindingSupportStatus` |
| `BindingContractRequest` | `dictionary BindingContractRequest` | `BindingContractRequest` | `data class BindingContractRequest` |
| `BindingApiContract` | `dictionary BindingApiContract` | `BindingApiContract` | `data class BindingApiContract` |
| `BindingTypeMapping` | `dictionary BindingTypeMapping` | `BindingTypeMapping` | `data class BindingTypeMapping` |
| `BindingMissingCapability` | `dictionary BindingMissingCapability` | `BindingMissingCapability` | `data class BindingMissingCapability` |
| `BindingContractReport` | `dictionary BindingContractReport` | `BindingContractReport` | `data class BindingContractReport` |
| `PlatformId` | `enum PlatformId` | `enum PlatformId` | `enum class PlatformId` |
| `PlatformCapabilityStatus` | `enum PlatformCapabilityStatus` | `enum PlatformCapabilityStatus` | `enum class PlatformCapabilityStatus` |
| `PlatformCapabilitySupport` | `dictionary PlatformCapabilitySupport` | `PlatformCapabilitySupport` | `data class PlatformCapabilitySupport` |
| `PlatformCapabilities` | `dictionary PlatformCapabilities` | `PlatformCapabilities` | `data class PlatformCapabilities` |
| `PlatformWatcherHealthSignal` | `dictionary PlatformWatcherHealthSignal` | `PlatformWatcherHealthSignal` | `data class PlatformWatcherHealthSignal` |
| `PlatformWatcherSnapshot` | `dictionary PlatformWatcherSnapshot` | `PlatformWatcherSnapshot` | `data class PlatformWatcherSnapshot` |
| `SyncConflict` | `dictionary SyncConflict` | `SyncConflict` | `data class SyncConflict` |
| `SyncConflictAffectedFile` | `dictionary SyncConflictAffectedFile` | `SyncConflictAffectedFile` | `data class SyncConflictAffectedFile` |
| `SyncConflictType` | `enum SyncConflictType` | `enum SyncConflictType` | `enum class SyncConflictType` |
| `SyncConflictSeverity` | `enum SyncConflictSeverity` | `enum SyncConflictSeverity` | `enum class SyncConflictSeverity` |
| `SyncConflictStatus` | `enum SyncConflictStatus` | `enum SyncConflictStatus` | `enum class SyncConflictStatus` |
| `SyncConflictFileRole` | `enum SyncConflictFileRole` | `enum SyncConflictFileRole` | `enum class SyncConflictFileRole` |
| `SyncConflictResolutionStrategy` | `enum SyncConflictResolutionStrategy` | `enum SyncConflictResolutionStrategy` | `enum class SyncConflictResolutionStrategy` |
| `SyncConflictVersionImpact` | `dictionary SyncConflictVersionImpact` | `SyncConflictVersionImpact` | `data class SyncConflictVersionImpact` |
| `SyncConflictReplacePlan` | `dictionary SyncConflictReplacePlan` | `SyncConflictReplacePlan` | `data class SyncConflictReplacePlan` |
| `SyncConflictResolutionPreviewReport` | `dictionary SyncConflictResolutionPreviewReport` | `SyncConflictResolutionPreviewReport` | `data class SyncConflictResolutionPreviewReport` |
| `SyncConflictResolutionRequest` | `dictionary SyncConflictResolutionRequest` | `SyncConflictResolutionRequest` | `data class SyncConflictResolutionRequest` |
| `SyncConflictResolveReport` | `dictionary SyncConflictResolveReport` | `SyncConflictResolveReport` | `data class SyncConflictResolveReport` |

---

## 函数总览

| 函数 | 类别 | Throws | 主要错误 |
|---|---|---|---|
| `get_version()` | meta | × | — |
| `get_observability_build_context()` | observability | × | — |
| `init_logging(level, callback)` | compatibility | √ | Config / Internal |
| `initialize_observability(config, sink)` | observability | √ | Config / Internal |
| `update_observability_config(config)` | observability | √ | Config / Internal |
| `get_observability_health()` | observability | × | — |
| `flush_observability(deadline_ms)` | observability | √ | Validation / Config |
| `import_file_observed(repo, src, options, trace_context)` | storage / observability | √ | Validation / import errors |
| `import_file_with_result_observed(repo, src, options, trace_context)` | storage / observability | √ | Validation / import errors |
| `inspect_binding_contract(request)` | ffi | √ | Config / Internal |
| `get_platform_capabilities(platform, app_version)` | platform | √ | Config |
| `validate_repo_path(repo)` | repo | √ | InvalidPath / PermissionDenied / ICloudPlaceholder / Io / Db |
| `validate_initialized_repo_path(repo)` | repo | √ | InvalidPath / PermissionDenied / ICloudPlaceholder / RepoNotInitialized / Io / Db |
| `init_repo(path, options)` | repo | √ | Io / Config / PermissionDenied |
| `load_repo_config(repo)` | repo | √ | Config / PermissionDenied / Io / Db |
| `update_repo_config(repo, patch)` | repo | √ | Config / Conflict / PermissionDenied / Io / Db |
| `load_ai_config(repo)` | ai | √ | Config / PermissionDenied / Io |
| `update_ai_config(repo, cfg)` | ai | √ | Config / PermissionDenied / Io |
| `get_local_model_status(repo, request)` | ai | √ | Config / PermissionDenied / Io / Db / DbLocked / DbCorrupted |
| `locate_local_model_folder(repo, request)` | ai | √ | Config / PermissionDenied / Io |
| `prepare_remote_ai_provider_probe(repo, request)` | ai | √ | Config / Internal |
| `complete_remote_ai_provider_probe(repo, observation)` | ai | √ | Config / PermissionDenied / Internal |
| `load_remote_ai_provider_config(repo)` | ai | √ | Config / Internal |
| `enable_remote_ai_provider(repo, request)` | ai | √ | Config / PermissionDenied / Internal |
| `disable_remote_ai_provider(repo, request)` | ai | √ | Config / Internal |
| `suggest_category_with_ai(repo, request)` | ai | √ | Config / PermissionDenied / Internal |
| `list_ai_calls(repo, filter, pagination)` | ai | √ | Db / PermissionDenied |
| `clear_ai_call_log(repo, request)` | ai | √ | Db / PermissionDenied |
| `generate_ai_summary(repo, request)` | ai | √ | Config / FileNotFound / PermissionDenied / Db |
| `save_ai_summary(repo, request)` | ai | √ | Config / FileNotFound / PermissionDenied / Db |
| `clear_ai_summary(repo, request)` | ai | √ | Config / FileNotFound / PermissionDenied / Db |
| `suggest_tags_with_ai(repo, request)` | ai | √ | Config / FileNotFound / Db |
| `apply_ai_tag_suggestions(repo, request)` | ai | √ | Config / FileNotFound / Db |
| `list_ai_privacy_rules(repo)` | ai/privacy | √ | Config / Db |
| `update_ai_privacy_rules(repo, request)` | ai/privacy | √ | Config / Db |
| `evaluate_ai_privacy(repo, request)` | ai/privacy | √ | Config |
| `get_ai_fallback_status(repo, request)` | ai/fallback | √ | Config / PermissionDenied / Internal |
| `semantic_search(repo, query, filter, pagination)` | ai/search | √ | Config / PermissionDenied / Db / Internal |
| `build_embedding_index(repo, scope)` | ai/search | √ | Config / PermissionDenied / Db / Internal |
| `recover_on_startup(repo)` | repo | √ | Db / DbLocked / DbCorrupted |
| `preview_manual_rescan(repo)` | repo | √ | Io / Db / PermissionDenied / Conflict |
| `reindex_from_filesystem(repo)` | repo | √ | Io / Db / PermissionDenied / Conflict |
| `create_diagnostics_snapshot(repo)` | repo | √ | InvalidPath / RepoNotInitialized / FileNotFound / PermissionDenied / Io / Internal |
| `preflight_repair_metadata(repo)` | repo | √ | InvalidPath / PermissionDenied / Io / Db |
| `repair_metadata(repo, options)` | repo | √ | InvalidPath / RepoNotInitialized / Conflict / Db / PermissionDenied / Io / Internal |
| `get_latest_scan_session(repo)` | repo | √ | Db |
| `resume_scan_session(repo, id)` | repo | √ | Io / Db |
| `get_overview_language_status(repo, locale)` | overview | √ | Config / Conflict / PermissionDenied / Io / Db |
| `prepare_overview_regeneration(repo, locale)` | overview | √ | Config / Conflict / PermissionDenied / Io / Db |
| `start_overview_regeneration(repo, request)` | overview | √ | Config / Conflict / PermissionDenied / Io / Db / Internal |
| `commit_overview_regeneration(repo, operation_id)` | overview | √ | Config / Conflict / PermissionDenied / Io / Db / Internal |
| `get_overview_regeneration(repo, operation_id)` | overview | √ | Config / FileNotFound / Db |
| `recover_overview_regeneration_on_startup(repo)` | overview recovery | √ | Config / Conflict / PermissionDenied / Io / Db / Internal |
| `resume_overview_regeneration(repo, operation_id)` | overview | √ | Config / Conflict / PermissionDenied / Io / Db / Internal |
| `cancel_overview_regeneration(repo, operation_id)` | overview | √ | Config / Conflict / Io / Db |
| `rollback_overview_regeneration(repo, operation_id)` | overview | √ | Config / Conflict / PermissionDenied / Io / Db / Internal |
| `predict_category(repo, name)` | classify | √ | RepoNotInitialized / Db / DbLocked / DbCorrupted / Config / Classify |
| `import_file(repo, src, options)` | storage | √ | Io / Db / DuplicateFile / Conflict / InvalidPath / ICloudPlaceholder / PermissionDenied |
| `import_file_with_result(repo, src, options)` | storage | √ | Io / Db / DuplicateFile / Conflict / InvalidPath / ICloudPlaceholder / PermissionDenied |
| `delete_file(repo, file_id)` | storage | √ | Io / Db / FileNotFound / PermissionDenied / Internal |
| `remove_index_entry(repo, file_id)` | storage | √ | Db / FileNotFound / PermissionDenied / Internal |
| `rename_file(repo, file_id, new_name, content_locale)` | storage | √ | Io / Db / Config / InvalidPath / Conflict / FileNotFound / PermissionDenied |
| `preview_move_to_category(repo, file_id, cat)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |
| `move_to_category(repo, file_id, cat)` | storage | √ | Classify / Conflict / FileNotFound / PermissionDenied / Io / Db |
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
| `list_classifier_rules(repo, editing_locale)` | classify | √ | Config / PermissionDenied / Io |
| `create_default_classifier(repo, confirmed, editing_locale)` | classify | √ | Config / PermissionDenied / Io |
| `restore_default_classifier(repo, confirmed, editing_locale)` | classify | √ | Config / PermissionDenied / Io |
| `restore_last_valid_classifier(repo, confirmed, editing_locale)` | classify | √ | Config / PermissionDenied / Io |
| `create_classifier_rule(repo, request)` | classify | √ | Config / Conflict / PermissionDenied / Io |
| `update_classifier_rule(repo, request)` | classify | √ | Config / Conflict / PermissionDenied / Io |
| `delete_classifier_rule(repo, request)` | classify | √ | Config / PermissionDenied / Io |
| `list_undo_actions(repo)` | undo | √ | Db / Io |
| `undo_action(repo, action_id)` | undo | √ | Conflict / FileNotFound / PermissionDenied / Db / Io |
| `list_redo_actions(repo)` | redo | √ | Db / Io |
| `redo_action(repo, action_id)` | redo | √ | Conflict / FileNotFound / ExpiredAction / PermissionDenied / Db / Io |
| `get_file(repo, file_id)` | query | √ | FileNotFound |
| `get_missing_file_state(repo, file_id)` | recovery | √ | FileNotFound / PermissionDenied / Db / DbLocked / DbCorrupted |
| `relink_missing_file(repo, request)` | recovery | √ | FileNotFound / PermissionDenied / Db / DbLocked / DbCorrupted |
| `remove_missing_file_record(repo, request)` | recovery | √ | FileNotFound / PermissionDenied / Db / DbLocked / DbCorrupted |
| `list_changes(repo, filter)` | query | √ | Db |
| `list_tree_json(repo, locale)` | query | √ | RepoNotInitialized / Db / DbLocked / DbCorrupted / Io |
| `detect_sync_conflicts(repo)` | sync/conflict | √ | Db / Io / Conflict |
| `preview_sync_conflict_resolution(repo, conflict_id, resolution)` | sync/conflict | √ | Conflict / PermissionDenied / Io / Db |
| `resolve_sync_conflict(repo, conflict_id, resolution)` | sync/conflict | √ | Conflict / PermissionDenied / Io / Db |
| `list_icloud_conflicts(repo)` | query | √ | ICloudPlaceholder / PermissionDenied / Io / Db |
| `preview_conflict_versions(repo, conflict_id)` | conflict | √ | ICloudPlaceholder / PermissionDenied / Conflict / Io / Db |
| `resolve_icloud_conflict(repo, conflict_id, resolution)` | conflict | √ | ICloudPlaceholder / PermissionDenied / Conflict / Io / Db |
| `detect_cloud_storage_state(repo)` | cloud | √ | ICloudPlaceholder / PermissionDenied / Io |
| `acknowledge_onedrive_risk_notice(repo)` | cloud | √ | ICloudPlaceholder / PermissionDenied / Io |
| `preview_import_conflict_batch(repo, request)` | conflict | √ | Conflict / FileNotFound / PermissionDenied / StagingRecoveryRequired / Io / Db |
| `apply_import_conflict_batch(repo, request, preview_token)` | conflict | √ | Conflict / FileNotFound / PermissionDenied / StagingRecoveryRequired / Io / Db |
| `read_note(repo, file_id)` | note | √ | InvalidPath / FileNotFound / PermissionDenied / Io / Db |
| `write_note(repo, file_id, content)` | note | √ | InvalidPath / FileNotFound / PermissionDenied / Io / Db |
| `sync_external_changes(repo, events, content_locale)` | sync | √ | InvalidPath / RepoNotInitialized / FileNotFound / ICloudPlaceholder / Conflict / PermissionDenied / Io / Db / Internal |
| `prepare_external_sync_locale_recovery(repo)` | sync recovery | √ | InvalidPath / RepoNotInitialized / Conflict / PermissionDenied / Io / Db / Internal |
| `resolve_external_sync_locale_recovery(repo, token, content_locale)` | sync recovery | √ | InvalidPath / RepoNotInitialized / Conflict / PermissionDenied / Io / Db / Internal |
| `get_fs_event_cursor(repo)` | sync | √ | InvalidPath / RepoNotInitialized / ICloudPlaceholder / PermissionDenied / Io / Db |
| `set_fs_event_cursor(repo, id)` | sync | √ | InvalidPath / RepoNotInitialized / ICloudPlaceholder / PermissionDenied / Io / Db |
| `record_watcher_health(repo, signal)` | sync/watcher | √ | Db / Io |
| `map_core_error(input)` | error | × | — |

---

## 合同边界与组合能力

本文件只记录 `core/area_matrix.udl` 已声明的正式合同。未进入 UDL 的候选接口、页面编排优化和历史缺口不属于当前 API；它们应在未来 workflow 中完成设计、风险确认和提升，不能由 UI 伪造成 Core 能力。

macOS 应用可以在平台层组合稳定 API：

- 文件详情当前先用 `get_file` + `list_changes` + `read_note` 组合；当前合同不提供详情聚合 DTO。
- 导入进度 / 队列语义由 Swift 侧编排多次导入调用，覆盖 copied-file import, moved-file import, indexed-file import；Core 不提供流式导入队列合同。
- `validate_initialized_repo_path` 负责 Core 的资料库基础校验。macOS 平台层如读取现有 metadata，只能以只读方式打开已存在的 `.areamatrix/index.db`；缺失、锁定、损坏或不兼容数据库必须返回错误，不得创建、迁移或修改数据库。
- 错误映射元数据由 `map_core_error` 提供稳定结构；每个错误返回 code、field、arguments、recovery action IDs、severity、recoverability 和可选 technical details，避免 UI 解析字符串。Swift 错误包装层（`AppSemanticError` 与 `AppErrorMappingProviding`）只负责本地化与展示编排。

Search、标签、批量操作、Undo/Redo、命令索引、分类规则、AI、隐私、语义搜索、冲突处理和平台能力矩阵均已进入 UDL。Search 包括 search query `search_files`、search facets `list_filter_facets` 和 saved search CRUD；调用方必须按各章节的副作用与错误合同使用。

---

## meta API

### `get_version() -> String`

```swift
let version = AreaMatrix.getVersion()
print("AreaMatrix Core \(version)")
```

返回 `Cargo.toml` 中的版本，形如 `"0.1.0"`。永不抛错。

### `get_observability_build_context() -> ObservabilityBuildContext`

无副作用返回当前已加载 Core 二进制的权威构建身份，包括固定 producer、Cargo version、可选 CI build ID、
debug/release configuration、目标平台与 Rust target architecture。macOS 平台层必须在注册
`CoreObservabilitySink` 前读取一次该值，并只接受 build context 与该值完全相等的 live Core event；不得在 Swift
复制 Cargo 版本或根据事件首包推断 Core 身份。

该 API 不初始化 observability runtime，不安装 subscriber，不访问用户文件、日志目录、DB 或网络。诊断包中的历史
schema version 2 事件仍按自身 build context 只读展示，不要求与当前加载 Core 相等。

### `init_logging(level: String, callback: CoreLogCallback) throws`

```swift
do {
    try AreaMatrix.initLogging(level: "info", callback: legacyCallback)
} catch let error as CoreError {
    print("logging init failed: \(error)")
}
```

`level` 只接受 `trace`、`debug`、`info`、`warn` 或 `error`。本函数是兼容入口：它将旧 callback 适配到
结构化 observability runtime，并只保证 legacy record 投影。新调用方使用 `initialize_observability`。

重复调用可以更新兼容 sink 与最小级别，但不会安装第二个 global subscriber。若结构化 runtime 已初始化，兼容入口
保留其 session ID 和首次固定的 queue 容量，避免 legacy reconnect 因默认容量不同而失败。非法 level 返回 `Config`。

### `initialize_observability(config: ObservabilityConfig, sink: CoreObservabilitySink) throws -> ObservabilityHealth`

初始化或重新连接进程级 Core observability runtime。subscriber 全进程只安装一次；sink 由 runtime 持有，函数返回后仍可
接收后续 Core event。重复调用原子替换 config 和 sink，不创建第二个 worker。

`queue_capacity` 范围为 64–65,536。`include_sensitive` 只允许 sensitive 字段进入已明确授权的本地 sink；
`Prohibited` 字段始终拒绝。Core 在进入有界 queue 前执行字段校验和 source redaction。

Core 发出的当前事件为 schema version 2，并携带 `ObservabilityBuildContext`：`producer`、`version`、可选
`build`、`configuration`、`platform` 与 `architecture`。该结构只描述产生事件的二进制；Core 不伪造 macOS
App build，macOS 也不补猜旧 Core 事件。schema version 1 仅保留为旧 JSONL/诊断包的只读兼容格式。

schema version 2 的事件 JSON 使用 snake_case 规范键；事件总隐私等级固定为 `privacy_level`，生命周期字段固定为
`phase`。`CoreObservabilityAttribute.privacy` 继续表示单个属性的隐私分类，两者不是同一字段。新 writer 不得生成
schema version 1 或旧的事件级 `privacy` 键；只读 reader 必须按 schema 版本解码，并拒绝新旧键混用。

`session_id` 必须是非空 UUID。session ID 和 queue 容量在首次初始化时固定；进程运行期间请求不同 session 或容量
返回 `Config`，模式、最小级别、sink 和 sensitive 授权仍可更新。新的 session 和容量在下次 App 启动生效。

该 API 不创建日志目录、不写 repository、不执行网络请求，也不依赖 AppKit/OSLog。Swift 平台层决定 OSLog、内存、
滚动 JSONL、界面和诊断包 sink。

### `update_observability_config(config: ObservabilityConfig) throws -> ObservabilityHealth`

更新 mode、minimum severity 和 sensitive 授权。runtime 未初始化时返回 `Config`；首次初始化固定的
`session_id` 与 `queue_capacity` 在当前进程内不可修改。模式更新不清除已有本地平台日志；retention 和删除由平台配置
单独负责。

### `get_observability_health() -> ObservabilityHealth`

无副作用返回初始化、mode、queue depth/capacity、按级别 drop count、callback 和 degraded 状态。健康读取不打开 DB、
不访问用户文件、不写日志，也不重置计数。

### `flush_observability(deadline_ms: UInt64) throws -> ObservabilityHealth`

等待已接受的 Core event 在 deadline 内交给 sink。deadline 范围为 1–5,000 ms，范围外返回 `Validation`；runtime
尚未初始化返回 `Config`。deadline 内未完成返回 degraded health，不无限阻塞，也不保证平台文件 writer 已
`fsync`；平台层对自己的 sink 执行独立 flush。

### `CoreTraceContext`

需要跨 Swift/Core 关联的请求 DTO 持有可选 `CoreTraceContext`。Swift 创建 session/trace/parent span，Core 创建本调用
span；不能用 thread-local 隐式跨越 `Task.detached`。context 的 `session_id` 必须与当前 observability runtime 一致。
`operation_id`、`retry_of_operation_id` 和 `incident_id` 只在对应业务/诊断生命周期存在时填写；retry 必须同时提供新的
`operation_id`，且两者不能相同。

`resource_refs` 只接收平台层已经生成的 privacy-safe resource identity。每次业务 operation 使用随机
`resource_id`；`alias` 使用安装范围随机密钥生成 keyed pseudonym，并固定为 `file.<24 lowercase hex>`，同一安装
可关联但不能由文件名直接反查。Core 只验证 wire shape，不接收 alias 密钥，也不从路径或文件名自行生成 alias。
`size_bucket` 只接受 `lt_1mb`、`1mb_10mb`、`10mb_100mb`、`100mb_1gb`、`gte_1gb`；`storage_mode`
只接受 `copied`、`moved`、`indexed`。根事件、子 span 和终态传播同一组 resource ref。

`attributes` 只包含受限结构化字段：单值最多 4,096 UTF-8 bytes，单个 context 的结构化 payload 总量最多
65,536 bytes。原文件名等用户识别信息必须显式标记为 `Sensitive`，默认在 Core source redaction 中替换为
`[REDACTED]`；表达 filename/path/URL/locator 的已知 key 具有不可降级的 Sensitive privacy floor。路径、用户正文、
翻译句子和 secret 不得作为普通 context identity。resource ref 至少把事件总隐私等级提升为 `Pseudonymous`，
保留的 sensitive 字段把事件总隐私等级提升为 `Sensitive`。

`action_id` 与 `component_id` 必须精确注册在 `core/resources/observability_catalog.json`。Core 先校验字符与
payload 边界，再校验 Catalog 成员资格；合法 ASCII 但未注册的 ID 返回 `Validation`，且 observed API 在任何
staging、用户文件或 DB 副作用前停止。macOS 控制台消费同一只读资源，不以字符串前缀扩展注册范围。

---

## ffi API

### `inspect_binding_contract(request: BindingContractRequest) throws -> BindingContractReport`

```swift
let report = try AreaMatrix.inspectBindingContract(
    request: BindingContractRequest(
        targetPlatform: .swift,
        bindingVersion: 1
    )
)
print(report.coreVersion)
```

cross-platform FFI contract 的平台中立 UniFFI 合同检查入口，服务 `platform differences`
的能力矩阵状态展示。返回 `BindingContractReport`：

- `target_platform`：请求检查的绑定家族。
- `binding_version`：请求的稳定绑定合同版本。
- `core_version`：AreaMatrix Core crate 版本。
- `supported_apis`：最小绑定能力报告中已核验的 API 子集，不是完整 UDL surface inventory。
- `type_mappings`：报告覆盖的基础 Rust / UDL / target-language 类型映射，不代表所有业务 DTO。
- `missing_capabilities`：当前绑定在该版本下缺失或受限的能力。

副作用边界：

- 只读检查，不读取 repo、不触碰文件系统、不生成绑定代码。
- 不执行平台 UI API，不推断平台能力，不补相邻多端能力。
- 页面需要的状态必须来自结构化 report，而不是 UI 自己猜测。

错误：

- `Config`：`binding_version` 不在支持范围内。
- `Internal`：报告无法暴露最小 API / type mapping 面。

---

## platform capability API

### `get_platform_capabilities(platform: PlatformId, appVersion: String) throws -> PlatformCapabilities`

```swift
let matrix = try AreaMatrix.getPlatformCapabilities(
    platform: .linux,
    appVersion: appVersion
)
if !matrix.trash.uiEnabled {
    disableReplace(reason: matrix.trash.reason)
}
```

platform capabilities 的平台能力矩阵入口，服务 `platform differences`、
`Linux local-folder notice` 和 `repository settings surface`。
调用方传入平台 id 和 app version，Core 返回结构化 `PlatformCapabilities`：

- `platform` / `app_version`：本次查询对应的平台和应用版本。
- `watcher`：文件系统 watcher 能力，供 watcher 状态入口和本地目录风险提示使用。
- `trash`：Trash / Recycle Bin 能力，供 Replace、删除和冲突解决前禁用危险操作。
- `share_extension`：Share Sheet / share extension 导入能力。
- `cloud_placeholder`：云盘 placeholder 检测能力。
- `security_bookmark`：security-scoped bookmark 或等价持久权限能力。

每个 `PlatformCapabilitySupport` 行包含：

- `status`：`Available`、`Limited`、`NotAvailable` 或 `Unknown`。
- `ui_enabled`：依赖该能力的 UI 是否可以启用。
- `requires_permission`：平台层是否还需要用户授权。
- `reason`：不可用、受限或未知时的稳定说明。

副作用边界：

- 只返回平台能力合同，不读取 repo、不写 DB、不触碰用户文件。
- 不启动 watcher，不触发 manual rescan，不执行 `sync_external_changes`。
- 不检测 Trash / Recycle Bin，不移动到 Trash，不执行 Replace 或删除。
- 不触发 iCloud placeholder 下载，不调用 iCloud / OneDrive / 分享扩展 SDK。
- 不刷新 security-scoped bookmark，不读取或导出用户文件内容。
- 本合同不新增 control map 之外的页面能力；能力矩阵不能替代真实操作前 preflight。

页面消费：

- `platform differences surface` 可以从各能力行的 `status`、`ui_enabled` 和 `reason`
  渲染能力矩阵；`Unknown` 必须显示为未知，不得显示成可用。
- `Linux local-folder notice surface` 可以从 `watcher` 与 `cloud_placeholder` 行展示本地目录、
  网络挂载或第三方同步目录的风险提示。
- `repository settings surface` 可以从 `watcher`、`trash`、`cloud_placeholder` 和
  `security_bookmark` 行禁用不可用设置和诊断入口。

错误：

- `Config`：`platform = Unknown`，或 `appVersion` 为空、过长、含非法字符。

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
- `isReadable` / `isWritable`：Core 是否可读取目录内容、是否具备初始化所需的写入能力。
- `isEmpty`：目录是否没有用户可见条目。
- `isInitialized`：目录下是否已有 `.areamatrix/` 元数据。
- `isInsideAreaMatrix`：选择位置是否为 `.areamatrix/` 或其子路径。
- `isIcloudPath`：是否疑似 iCloud 管理路径。
- `isOnedrivePath`：是否疑似 OneDrive 管理路径；UI 用它进入 OneDrive 风险确认，不控制同步。
- `platformPathKind`：平台无关的位置类型，取值为 `Local`、`ICloudDrive`、`OneDrive`、
  `NetworkShare` 或 `Unknown`。
- `isCaseSensitivePath`：路径比较是否应按大小写敏感处理；Windows-shaped 路径默认返回 `false`。
- `hasUnfinishedScanSession`：是否存在未完成的 adopt / reindex scan session。
- `recommendedMode`：路径可用于初始化时推荐 `CreateEmpty` 或 `AdoptExisting`，不可用时为 `nil`。
- `issues`：结构化问题列表，UI 不需要解析错误字符串即可展示风险；Windows / OneDrive
  场景会包含 `OneDrivePath` 或 `WindowsCaseInsensitive`。Windows 保留名不进 issues，
  直接按 `InvalidPath` 硬错误拒绝；`WindowsReservedName` 是合同中预留的 issue 值，当前不构造。

错误：

- `InvalidPath`：路径为空、不是可接受的文件系统路径、含 Windows 保留名、或位于 `.areamatrix/` 内部。
- `PermissionDenied`：无法读取目录 metadata、列出目录内容或确认写权限。
- `ICloudPlaceholder`：候选路径或关键 metadata 仍是未下载的 iCloud 占位符。
- `Io`：目录 metadata 读取失败且无法归入以上错误。
- `Db`：scan session 状态读取失败。
- `RepoNotInitialized`：不由本入口返回；调用方要求已初始化语义时使用
  `validate_initialized_repo_path`。

副作用边界：

- 只读检查：metadata、权限、子项数量、`.areamatrix/` 探测、scan session 状态读取。
- 不创建、不删除、不移动、不重命名、不覆盖任何文件。
- 不触发 iCloud 占位符下载。
- 不调用 OneDrive SDK，不读取 OneDrive 客户端同步状态，不修改 OneDrive 同步设置。
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
- `Io` / `Db`：同 `validate_repo_path`，metadata 读取兜底与 scan session 状态读取失败。

### `init_repo(repoPath: String, options: RepoInitOptions) throws`

```swift
let options = RepoInitOptions(
    mode: .adoptExisting,
    createDefaultCategories: false,
    overviewOutput: .generatedOnly,
    contentLocale: resolvedRepositoryContentLocale
)
do {
    try AreaMatrix.initRepo(repoPath: selectedURL.path, options: options)
} catch CoreError.Config {
    // 已初始化、目录非空、有未完成 scan session 等一律归一为
    // Config("configuration error")；按错误变体分支，不解析 reason 字符串。
    await showAlert("这个目录当前不能初始化为 AreaMatrix 资料库")
} catch {
    throw error
}
```

执行：

- `content_locale` 必须是调用开始时已解析的 `zh-Hans` 或 `en`，用于本次初始化创建的 generated root
  和可选根 `AREAMATRIX.md`；新资料库持久化的 `RepoConfigSnapshot.locale_policy` 默认是 `system`（跟随界面）。
- `CreateEmpty`：目录必须为空或仅包含系统隐藏文件；可按 `classifier.yaml` 创建分类目录
- `AdoptExisting`：目录可以非空；不移动、不重命名、不删除、不覆盖已有内容
- 创建 `.areamatrix/{staging, archives, generated}/`
- 复制默认 `classifier.yaml`
- 创建默认 `ignore.yaml`
- 创建 SQLite 并写入当前初始 schema；新库直接落在最新 `schema_version`（当前为 3），不重放历史迁移
- `AdoptExisting` 模式下启动 `scan_sessions(kind=Adopt)` 并执行内部接管扫描
- 默认生成 `.areamatrix/generated/root.md`
- 仅当 `overview_output = RootAreaMatrixFile` 时写入/维护根目录 `AREAMATRIX.md`

约束：

- 永不写入或覆盖已有 `README.md`
- 选中 `.areamatrix/` 子目录 → `CoreError.InvalidPath`
- 目录不可写 → `CoreError.PermissionDenied`

### `load_repo_config(repoPath: String) throws -> RepoConfigSnapshot`

```swift
let cfg = try AreaMatrix.loadRepoConfig(repoPath: repoPath)
print("default mode: \(cfg.defaultMode)")
print("locale: \(cfg.localePolicy.rawValue)")
print("revision: \(cfg.revision)")
```

`.areamatrix/index.db` 不存在时返回默认值（不抛错），且不创建 metadata、
配置文件或生成文件。metadata 存在但无法读取、解码或打开时，按
`Config`、`PermissionDenied`、`Io`、`Db` 传播。

#### repository settings contract

`load_repo_config` 是 repository settings `repository-settings-cross-platform` 的 repo config
读取入口，和 `get_platform_capabilities(platform, appVersion)` 组合服务
`repository settings surface`。页面消费方可从合同中得到：

- 当前 repository path、storage mode、overview output、locale、iCloud warning、
  classifier rule toggles、fallback 和 import replace 默认设置。
- 平台 capability snapshot 中的 watcher、Trash / Recycle Bin、cloud placeholder
  和 security bookmark 支持状态、禁用状态和稳定说明。
- `Config`、`PermissionDenied`、`Io`、`Db` 的结构化错误，用于区分配置损坏、
  权限阻断、文件系统读取失败和 metadata DB 失败。

页面消费边界：

- `repository settings surface` 可用 `RepoConfigSnapshot` 渲染当前设置值，用 `PlatformCapabilities`
  禁用平台不支持的设置和诊断入口。
- 本合同不提供 repo name、last opened、watcher runtime health、diagnostics export、
  reconnect picker、recent repo、安全书签续期或 ACL/POSIX permission 生命周期；
  这些由 platform capabilities、manual rescan、平台层或对应页面能力覆盖。
- 本调用只读，不检测 watcher、Trash、云盘 SDK 或 security bookmark，也不读取、
  移动、删除、重命名、覆盖或下载用户文件。

### `update_repo_config(repoPath: String, patch: RepoConfigPatch) throws -> RepoConfigSnapshot`

```swift
let cfg = try AreaMatrix.loadRepoConfig(repoPath: repoPath)
let updated = try AreaMatrix.updateRepoConfig(
    repoPath: repoPath,
    patch: RepoConfigPatch(
        expectedRevision: cfg.revision,
        repoPath: nil,
        defaultMode: .copied,
        overviewOutput: .generatedOnly,
        aiEnabled: nil,
        localePolicy: .zhHans,
        icloudWarn: nil,
        enableExtensionRules: nil,
        enableKeywordRules: nil,
        fallbackToInbox: nil,
        allowReplaceDuringImport: nil
    )
)
```

通过 SQLite immediate transaction 比较 `expected_revision`，只更新 patch 中非空的 dirty fields，并在
成功提交时把 revision 单调加一。stale revision 返回 `Conflict`，所有字段保持旧值。该调用不写 tmp 文件、不
rename，也不创建或更新 `README.md`、`AREAMATRIX.md` 或
`.areamatrix/classifier.yaml`。

`repo_path` 仅用于资料库目录移动后的元数据自同步，值必须与调用参数 `repoPath` 完全一致；
`enable_extension_rules`、`enable_keyword_rules` 与 `fallback_to_inbox`
支撑 `classifier rule toggle` 分类规则开关；`allow_replace_during_import` 支撑 `replace import setting`
危险导入选项的默认关闭策略。它们只保存设置状态，不执行分类、导入或
替换行为。

`expected_revision` 必须来自最近读取的 snapshot。unknown locale policy 下只接受 locale 和/或 path-only patch；
普通字段 patch 与生成操作均 fail closed。任一校验、权限、IO 或 DB 持久化失败时，事务回滚，旧配置保持
可读；主要错误码为 `Config`、`Conflict`、`PermissionDenied`、`Io`、`Db`。

#### repository settings contract

`update_repo_config` 是 repository settings `repository-settings-cross-platform` 的 repo config
更新入口。调用方必须先读取 `get_platform_capabilities` 并在 UI 层禁用平台不支持的
设置项；Core 只校验和持久化 `RepoConfigPatch`，不接受 control map 之外的页面能力。

repository settings 输入：

- `repoPath`：已初始化资料库根目录。
- `patch`：`expected_revision` 与 dirty fields；未编辑字段必须为 `nil`。
- `platform`：不直接传入本函数；页面通过 `get_platform_capabilities` 查询平台约束。

repository settings 输出：

- 成功时返回包含新 revision 的完整 snapshot；页面不拼装或猜测未修改字段。
- stale save 返回 `Conflict`；其他失败返回 `Config`、`PermissionDenied`、`Io` 或 `Db`，旧配置必须保持可读。

repository settings 副作用边界：

- 只通过 SQLite 事务更新 `.areamatrix/index.db` 的 `repo_config` 行。
- 不写临时业务文件，不更新 `README.md`、`AREAMATRIX.md`、
  `.areamatrix/classifier.yaml` 或用户文件。
- 不移动、删除、重命名、覆盖用户文件，不触发 importer、overview generation、
  watcher、manual rescan、cloud placeholder 下载、Trash / Recycle Bin preflight、
  diagnostics export、账号级云同步或 security bookmark refresh。

### `load_ai_config(repoPath: String) throws -> AiConfigSnapshot`

```swift
let snapshot = try AreaMatrix.loadAiConfig(repoPath: repoPath)
if !snapshot.config.aiEnabled {
    print("AI is off")
}
```

AI settings 的 AI settings 读取入口，服务 `AI settings surface ai-settings` 和 `AI privacy rules surface
ai-privacy-rules` 对远程 gate 的只读状态展示。返回 `AiConfigSnapshot`：

- `config.ai_enabled`：AI 总开关，默认关闭；关闭时不得调用本地或远程模型。
- `config.provider_preference`：`LocalFirst`、`LocalOnly` 或 `RemoteFirst`，只表达
  设置偏好，不代表 provider 已可用。
- `config.local_ai_enabled` / `config.remote_ai_allowed`：本地和远程路线是否允许进入
  provider gate。
- `config.privacy_gate_enabled` / `privacy_policy_ref`：AI privacy rules surface 远程隐私 gate 状态和
  可选策略引用；不内嵌隐私规则列表。
- `config.feature_toggles`：`ClassificationSuggestions`、`AutoSummaries`、
  `AutoTags`、`SemanticSearch` 四个功能开关及是否允许远程路线。
- `capabilities`：每个功能的派生可用性、local/remote 允许状态和禁用原因，供 UI
  直接显示 provider 要求、远程 scope/gate 状态和 VoiceOver 文案。
- `updated_at`：实现持久化后返回最近更新时间；默认或未持久化状态可为 `nil`。

副作用边界：

- 读取配置不得启动本地模型、测试远程 provider、发起网络、写 AI 调用日志、读取用户文件内容、
  清理建议或写入用户文件。
- 不得传入或返回 API key；API key 只允许平台安全存储，AI settings 合同只引用状态或策略。
- 不返回 provider 连接测试结果、模型列表、AI 调用日志、隐私规则 CRUD 结果或语义索引状态；
  这些分别属于 local model status、remote provider configuration、AI call log、AI privacy rules 和 semantic search。

错误：

- `Config`：`repoPath` 为空、位于 `.areamatrix/` 内部，或持久化配置结构无效。
- `PermissionDenied`：AI settings metadata 无法读取。
- `Io`：AI settings metadata inspection 失败。

页面消费状态：

- AI settings surface 可以从合同得到 AI 总开关、provider preference、本地/远程路线开关、功能开关、
  远程 gate 摘要、禁用原因和更新时间。
- AI privacy rules surface 可以从合同得到 `privacy_gate_enabled`、`remote_ai_allowed`、功能远程允许状态和
  策略引用，用于判断本页是 privacy gate 而非 provider 禁用页。
- AI settings 不新增 control map 之外的页面能力；remote provider settings surface 仍负责 provider/key/scope/测试连接，
  AI privacy rules surface 仍负责隐私规则 CRUD/evaluate。

### `update_ai_config(repoPath: String, newConfig: AiConfig) throws -> AiConfigSnapshot`

```swift
var snapshot = try AreaMatrix.loadAiConfig(repoPath: repoPath)
snapshot.config.aiEnabled = false
let updated = try AreaMatrix.updateAiConfig(
    repoPath: repoPath,
    newConfig: snapshot.config
)
```

AI settings 的 AI settings 更新入口，只保存 AI 设置元数据：总开关、provider preference、
本地/远程路线开关、privacy gate 引用和四个功能开关。成功后返回更新后的
`AiConfigSnapshot`，让 AI settings surface/AI privacy rules surface 直接刷新设置状态和禁用原因。

约束：

- `newConfig.repo_path` 必须等于 `repoPath`。
- `feature_toggles` 必须包含且只包含 AI settings 四个功能：
  `ClassificationSuggestions`、`AutoSummaries`、`AutoTags`、`SemanticSearch`。
- 该 API 不接受 API key、provider endpoint、model id、prompt、用户文件路径列表或文件内容。
- 启用远程路线只表达“允许 gate 将远程路线纳入候选”；不测试远程 provider、不启用远程 provider、
  不调用模型、不上传数据。
- Pause all AI 可通过 `ai_enabled = false` 表达；清除未采纳建议和草稿属于独立清理能力，
  不由 AI settings 更新入口隐式执行。

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
- 不实现 local model status 本地模型状态、remote provider configuration 远程 provider 配置、AI call log 调用日志、AI privacy rules 隐私规则
  CRUD/evaluate、AI fallback 或任何 AI 结果生成。

页面消费状态：

- AI settings surface 可以从返回快照更新总开关、功能开关、provider preference、远程 gate 摘要、
  禁用原因和保存失败后的回退基线。
- AI privacy rules surface 可以更新 `privacy_gate_enabled` 并继续保持 provider 配置、Keychain key、
  `remote_provider_enabled` 和 `feature_scope` 不变；真正禁用 remote provider 只能走 remote provider settings surface。
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

local model status 的本地模型状态读取入口，服务 `local model status surface`。输入
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
- `feature_statuses`：`ClassificationSuggestions`、`AutoTags`、`SemanticSearch` 等 local model status surface 展示的
  本地模型功能支持状态。该字段只描述本地模型支持能力，不代表远程 provider 可用。

副作用边界：

- 状态检查只读本地模型 manifest、模型目录 metadata、磁盘占用、缓存状态和 runtime 健康 metadata；
  每次成功检查会把脱敏快照写入 AreaMatrix-owned status cache（repo DB 状态表），这是唯一写入。
- 不下载、安装、删除、训练模型，不改写模型权重，不读取用户文件内容，不调用远程 provider，
  不写 AI call log，不自动启用远程 fallback。
- 本地模型不可用时，调用方只能显示本地修复、安装帮助、诊断或非 AI 回退；不得把返回状态解释成
  允许启用远程 AI。
- 轻量 `RepairMetadata` 只是 UI 可展示的建议动作；实际 repair 行为必须由独立能力实现。

错误：

- `Config`：`repoPath`、`model_id`、`storage_location` 或 `cached_status` 无效，或本地模型
  metadata schema 不可用。
- `PermissionDenied`：模型目录、manifest、runtime 状态或 AreaMatrix-owned status cache 不可读。
- `Io`：读取模型 manifest、目录 metadata、磁盘占用或 runtime health metadata 失败。
- `Db` / `DbLocked` / `DbCorrupted`：写入 AreaMatrix-owned status cache 时发生通用、锁定或损坏错误；
  locked 保持可重试，corrupted 进入阻断恢复，不压扁为 `Config`。

页面消费状态：

- local model status surface 可以从合同得到 Ready、Not installed、Path unreadable、Version incompatible、
  Checking、Verifying、Loading、Corrupted、Runtime failed、Error 和 Unknown 状态。
- local model status surface 可以从 `recommended_action` 渲染 `Check status`、`Retry status check`、
  `Open install help`、`Open model location`、`Run health check`、`Repair`、`Open diagnostics`
  和非 AI 回退说明。
- local model status surface 可以从 `diagnostics_summary` 打开本地诊断入口，但该入口只展示脱敏摘要，不提供远程
  provider、模型下载、删除缓存或训练能力。
- 本合同不新增 control map 之外的页面能力；remote provider settings surface 仍负责远程 provider/key/连接测试，AI fallback 仍负责
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

local model status 的本地模型目录定位入口，服务 local model status surface 的 `Open model location`。返回
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

- local model status surface 可以从 `exists`、`readable`、`openable` 和 `unavailable_reason` 决定
  `Open model location` 的启用、禁用和错误说明。
- 本合同不提供下载、删除、训练、远程 provider 或 fallback 能力。

### `prepare_remote_ai_provider_probe(repoPath: String, request: RemoteProviderTestRequest) throws -> RemoteProviderProbePlan`

```swift
let plan = try AreaMatrix.prepareRemoteAiProviderProbe(
    repoPath: repoPath,
    request: RemoteProviderTestRequest(
        provider: .openAi,
        modelId: "gpt-4.1-mini",
        endpointUrl: nil,
        keyReference: "keychain:remote-openai"
    )
)
```

remote provider configuration 的连接测试准备入口。输入只包含 provider、model、可选自定义 endpoint
和平台安全存储 key reference；不接受 API key 明文。Core 校验输入、生成不可伪造的 `probe_token`，
并返回由平台层执行的最小网络计划。

自定义 endpoint 只允许 HTTPS，或开发用途的 loopback HTTP；不得包含 URL userinfo
（例如 `https://user:password@host/`），避免凭据进入 plan、临时记录或 provider config。

返回 `RemoteProviderProbePlan`：

- `method`、`url` 和 `headers`：不含 secret 的最小 HTTP 请求计划；认证 header 只通过
  `authorization` 指示，由平台层读取 Keychain 后临时装配。
- `key_reference`：平台安全存储引用，不是 API key 明文。
- `timeout_millis`、`maximum_response_body_bytes` 和 `follow_redirects`：平台层必须执行的网络限制。
  当前计划只读取 HTTP status，不消费响应正文，也不跟随 redirect。
- `probe_token`：只用于把平台观测结果绑定到当前准备记录，不是 enable token。

副作用边界：

- Core 只写入当前 probe 的临时绑定记录；不读取 Keychain、不启动外部进程、不访问网络。
- 计划不得包含文件名、repo-relative path、提取文本、note summary、tag/category context、prompt
  或任何用户文件内容。
- prepare 不启用远程 provider，不保存 `feature_scope`，不修改 `privacy_gate_enabled`，不生成 AI 结果。

错误：

- `Config`：`repoPath`、provider、model、endpoint 或 key reference 无效。
- `Internal`：临时 probe 记录无法持久化。

### `complete_remote_ai_provider_probe(repoPath: String, observation: RemoteProviderProbeObservation) throws -> RemoteProviderTestResult`

```swift
let result = try AreaMatrix.completeRemoteAiProviderProbe(
    repoPath: repoPath,
    observation: RemoteProviderProbeObservation(
        probeToken: plan.probeToken,
        outcome: .httpResponse,
        httpStatus: 200
    )
)
```

平台层必须使用 Keychain 和受限 `URLSession` 执行 `RemoteProviderProbePlan`，并只回传
`RemoteProviderProbeObservation`。观测只允许包含 probe token、传输结果和 HTTP status；不得回传
响应 header、响应正文、API key、请求 header 或底层错误原文。

返回 `RemoteProviderTestResult`：

- `status`：Core 根据 provider、HTTP status 或连接失败映射为 `Succeeded`、`ProviderRejected`、
  `ConnectionFailed` 或 `UnsupportedProvider`。
- `provider_verified`：当前 provider/model/endpoint/key 组合是否通过测试。
- `verification_token`：成功后用于 enable 的不透明 token；不得包含 API key 或 key 片段。
- `sanitized_message`：稳定、可展示的脱敏结果说明。

副作用边界：

- complete 只消费净化观测；Core 不接收 provider 原始响应，也不重新执行网络请求。
- 失败观测不会生成 enable token，并清理当前临时 probe 记录。
- Swift 调用任务被取消时，平台层必须取消正在执行的 `URLSession` 请求，并以失败观测清理临时
  probe 记录；取消路径不得生成 verification token。
- 成功观测把临时 probe 记录转换为待 enable 的 verification 记录；不启用远程 provider。
- 平台探测不得发送文件名、repo-relative path、提取文本、note summary、tag/category context、
  prompt 或任何用户文件内容。

错误：

- `Config`：probe token、观测 shape 或临时记录无效、过期或与当前 probe 不匹配。
- `PermissionDenied`：平台报告 credential reference 无法读取或 credential 不可用。
- `Internal`：临时记录读取、清理或 verification 持久化失败。

页面消费状态：

- remote provider settings surface 可以从 `status`、`provider_verified` 和 `sanitized_message` 渲染连接成功、key 被拒绝、
  网络失败、unsupported provider 和 Enable 禁用原因。
- AI privacy rules surface 不应从本合同开启 privacy gate；它只读取 enable 快照中的 provider 状态。

### `load_remote_ai_provider_config(repoPath: String) throws -> RemoteProviderConfigSnapshot`

```swift
let snapshot = try AreaMatrix.loadRemoteAiProviderConfig(repoPath: repoPath)
```

remote provider configuration 的远程 provider 快照读取入口，服务 remote provider settings surface 打开 sheet 时读取已配置 provider，
也服务 AI privacy rules surface 只读展示 provider consent 状态。

返回 `RemoteProviderConfigSnapshot`：

- `provider_configured`、`provider_verified`、`remote_provider_enabled`、`credential_configured`
  和 `feature_scope`：供 remote provider settings surface/AI privacy rules surface 判断 provider gate。
- `provider`、`model_id`、`endpoint_url`：已保存的 provider metadata；不包含 API key 明文、
  key 片段或平台安全存储原始 secret。
- `disabled_reason`：远程不可用时供 remote provider settings surface/AI privacy rules surface 展示的稳定原因。

副作用边界：

- 该 API 只读取 metadata，不测试 provider、不启用远程、不禁用远程、不修改 `privacy_gate_enabled`、
  不读取用户文件、不写 AI call log、不执行任何远程 AI 调用。
- 空配置返回 disabled 快照，不创建 provider、credential、scope 或 privacy rule。

错误：

- `Config`：`repoPath` 无效或持久化 metadata 无法解析。
- `Internal`：provider metadata 无法从已初始化仓库读取。

页面消费状态：

- remote provider settings surface 可以在打开配置 sheet 时恢复 provider/model/endpoint、credential presence、测试状态、
  enabled 状态和 scope。
- AI privacy rules surface 可以只读展示 remote provider settings surface 的 provider 配置、测试状态、远程启用状态和 scope，但不得通过本合同
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

remote provider configuration 的远程 provider 显式启用入口，服务 remote provider settings surface 的 `Enable remote AI`。输入必须包含
provider/model/key reference、非空 `feature_scope`、成功测试产生的 `verification_token` 和用户
数据流向确认。

返回 `RemoteProviderConfigSnapshot`：

- `provider_configured`：provider、model 或 endpoint 已保存。
- `provider_verified`：当前 provider/model/endpoint/key 组合已经通过测试；任一字段变化后必须重置。
- `remote_provider_enabled`：用户显式启用后的 provider gate。
- `credential_configured`：是否存在安全存储引用；不返回 API key 明文或片段。
- `feature_scope`：允许使用远程 provider 的功能范围，包含
  `ClassificationSuggestions`、`AutoSummaries`、`AutoTags` 或 `SemanticSearch`。
- `disabled_reason`：远程不可用时供 remote provider settings surface/AI privacy rules surface 展示的稳定原因。

副作用边界：

- 该 API 只保存远程 provider metadata、Keychain reference 和 scope；API key 明文只允许在平台安全
  存储中处理，不进入 Core 返回值、日志、诊断或错误文案。
- 启用远程不会执行 AI 调用、发送用户内容、修改 privacy rules、编辑字段过滤、生成建议、写用户文件、
  清理 AI 结果或实现 fallback。
- `privacy_gate_enabled` 由 AI privacy rules 管理；remote provider settings surface 首次成功启用时可以请求默认打开 gate，但该 gate 的持久化
  和规则评估仍属于 AI privacy rules，不由本合同替代。

错误与回滚：

- `Config`：provider settings 无效、scope 为空或重复、verification token 无效、未确认数据流向。
- `PermissionDenied`：credential reference 或 provider metadata 无法 inspection。
- `Internal`：provider metadata 持久化或启用状态写入失败。
- 任一失败必须保留上一次成功的 remote provider state；已写入但未被启用的 credential 必须保持
  unused credential 状态，供 remote provider settings surface 提供 retry 或 cleanup。

页面消费状态：

- remote provider settings surface 可以从返回快照得到 `provider_configured`、`provider_verified`、
  `remote_provider_enabled`、`feature_scope`、credential presence 和禁用原因。
- AI privacy rules surface 可以只读展示 provider 配置、测试状态、远程启用状态和 scope，并继续把
  `privacy_gate_enabled`、字段过滤和规则匹配作为独立 gate。
- 本合同不新增 control map 之外的页面能力；AI 调用日志属于 AI call log，隐私规则/evaluate 属于 AI privacy rules，
  fallback 属于 AI fallback。

### `disable_remote_ai_provider(repoPath: String, request: RemoteProviderDisableRequest) throws -> RemoteProviderConfigSnapshot`

```swift
let snapshot = try AreaMatrix.disableRemoteAiProvider(
    repoPath: repoPath,
    request: RemoteProviderDisableRequest(removeStoredCredential: false)
)
```

remote provider configuration 的远程 provider 禁用入口，服务 remote provider settings surface 的 `Disable remote AI`。输入只包含用户是否勾选
`Also remove stored API key`；不接受 API key 明文。

返回禁用后的 `RemoteProviderConfigSnapshot`：

- `remote_provider_enabled` 必须为 false。
- 未删除 credential 时保留 `provider_configured`、`provider_verified`、credential presence 和
  `feature_scope`，方便用户之后重新启用前仍能看到已配置状态。
- 删除 credential 时 `credential_configured` 为 false，`provider_verified` 为 false，且
  `disabled_reason` 稳定说明 provider 未配置或需要重新测试。

副作用边界：

- 该 API 只关闭 remote provider gate，并在用户显式选择时忘记 Core 中的 credential reference；
  真正 Keychain 删除由平台安全存储层执行并回传新的 reference 状态。
- 禁用远程不会删除本地 AI 设置、privacy rules、字段过滤、AI call log、已有摘要/标签/建议或任何用户文件。
- 该 API 不修改 `privacy_gate_enabled`；remote provider settings surface 成功禁用后关闭 privacy gate 的持久化仍由 AI privacy rules 入口负责。

错误与回滚：

- `Config`：`repoPath` 无效或持久化 metadata 无法解析。
- `Internal`：provider metadata 持久化或禁用状态写入失败。
- 任一失败必须保留上一次成功的 remote provider state，不能写入半禁用状态。

页面消费状态：

- remote provider settings surface 可以从返回快照立即刷新 Off 状态和 credential presence。
- AI privacy rules surface 继续只读展示 provider gate 状态；`Block remote AI with privacy gate` 不能被实现为本 API。
- 本合同不新增 control map 之外的页面能力；隐私 gate、日志、fallback 和 AI 调用仍由各自 AI 能力合同覆盖。

### `suggest_category_with_ai(repoPath: String, request: AiCategorySuggestionRequest) throws -> AiCategorySuggestion`

```swift
let suggestion = try AreaMatrix.suggestCategoryWithAi(
    repoPath: repoPath,
    request: AiCategorySuggestionRequest(
        fileId: file.id,
        contextPolicy: .limitedTextSummary,
        privacyPolicyRef: snapshot.config.privacyPolicyRef,
        contentLocale: frozenRepositoryContentLocale
    )
)
```

AI category suggestion 的 AI 分类建议入口，服务 `AI category suggestion surface ai-classification-suggestion` 的
`Ask AI for suggestion...`，并为 `AI fallback` 提供可展示的 skipped /
unavailable 状态。输入是已初始化 `repoPath` 和一个 `AiCategorySuggestionRequest`：

- `file_id`：一个 active file row。实现必须拒绝缺失、删除态或不可访问的 file id。
- `context_policy`：调用方允许的最大上下文提取范围：
  `FileNameOnly`、`FileNameAndPath` 或 `LimitedTextSummary`。
- `privacy_policy_ref`：可选稳定隐私策略引用。规则内容和 CRUD 属于 AI privacy rules，不内嵌在本请求。
- `content_locale`：在进入 privacy/provider await 前冻结的 `zh-Hans` 或 `en`，用于本次可持久化的自然语言
  建议与理由。local -> remote automatic fallback 属于同一 attempt，必须复用该值；用户新建 attempt 才重取。

返回 `AiCategorySuggestion`：

- `status`：`Suggested`、`NoSuggestion`、`Skipped` 或 `Unavailable`。
- `current_category` / `suggested_category`：当前分类和建议目标分类。只有
  `Suggested` 状态可包含建议目标分类。
- `confidence`：0.0 到 1.0 的置信度；低置信建议由 AI category suggestion surface 弱化展示并禁止批量一键采纳。
- `reason`：脱敏、可展示的建议理由；不得包含 provider 原始响应、API key 或完整文件内容。
- `route`：`Local` 或 `Remote`，用于 AI category suggestion surface badge 和 AI call log surface 追溯。
- `used_context`：实际使用或允许展示的字段，包含 filename、extension、repo-relative path
  或 limited text summary。
- `skipped_reason`：`AiDisabled`、`FeatureDisabled`、`RuleResultConfident`、
  `NoEligibleContext`、`PrivacyRule` 或 `ProviderUnavailable`。
- `privacy_rule_id` / `call_log_id`：供页面跳转隐私规则和调用日志；具体日志读写属于 AI call log，
  隐私规则详情属于 AI privacy rules。
- `requires_user_confirmation`：必须为 true。采纳、修改、拒绝、移动确认或规则沉淀不由本 API
  隐式执行。

副作用边界：

- 本 API 只生成建议草稿；不得写 `files.category`，不得移动、删除、重命名、覆盖用户文件，
  不得保存 classifier rule，不得执行 classifier save-rule surface/classifier impact preview surface 规则沉淀，也不得替代分类纠错入口。
- 自动触发只能发生在规则分类失败、进入 inbox 兜底或低置信度时；高置信规则结果必须返回
  `NoSuggestion` / `RuleResultConfident`，而不是覆盖规则分类。
- 远程路线必须同时通过 AI settings、remote provider gate、AI privacy gate、
  feature scope 和调用日志 gate；本 API 不启用远程 provider，不保存 API key，不绕过隐私规则。
- 隐私规则命中时必须返回 `Skipped` / `PrivacyRule`，`used_context` 为空或只包含允许展示字段，
  sent fields 由 AI call log 记录为 none。
- 失败或跳过不得改变文件、分类、标签、摘要、notes、saved searches、change log、undo/redo、
  generated overview 或任何用户文件。

错误：

- `Config`：`repoPath`、`file_id`、`context_policy`、`privacy_policy_ref` 或 AI gate 配置无效；
  AI 关闭或功能关闭也可返回结构化 `Skipped`，由实现按 UX 需要选择。
- `PermissionDenied`：repository metadata、允许的上下文字段、本地模型状态或 provider credential
  reference 无法 inspection。
- `Internal`：AI runtime、provider adapter、脱敏后的模型执行或结果解析发生未归类失败。

页面消费状态：

- AI category suggestion surface 可以从合同得到当前分类、建议分类、confidence、reason、local/remote route、
  used context、privacy skipped、call log id、privacy rule id 和“必须确认后才能写入”的状态。
- AI fallback surface 可以从 `status`、`skipped_reason`、`route` 和 `call_log_id` 渲染 AI off、provider
  unavailable、privacy skipped、local/remote failure 和非 AI 回退入口。
- 本合同不新增 control map 之外的页面能力；AI 调用日志仍由 AI call log 覆盖，隐私规则由 AI privacy rules
  覆盖，fallback reason matrix 由 AI fallback 覆盖，分类采纳/移动仍复用对应分类与文件操作能力。

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

AI call log 的 AI 调用日志读取入口，服务 `AI call log surface ai-call-log` 的表格、详情、过滤、
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

`AiCallLogRecord` 只暴露 AI call log surface 需要的状态：

- `feature`、`route`、`provider_name`、`model_name`、`status`、`duration_ms`、`error_code`。
- `file_id`、`file_display_name`、`batch_id`、`scope`。Provider Test 记录固定可表达
  `feature = ProviderTest`、`scope = Provider verification`、无文件或批次。
- `sent_fields` 只包含字段类型：`FileName`、`RepoRelativePath`、`Extension`、
  `ExtractedTextExcerpt`、`AiSummary`、`NoteSummary`、`TagCategoryContext`。
- `privacy_rules_checked`、`privacy_rule_id`、`privacy_rule_name`、`matched_field_type`。
- `privacy_rules_checked` 表示 producer 已完成 privacy gate 评估，和是否命中规则相互独立；允许但未命中规则的
  调用仍为 `true`。`privacy_rule_id` / name / matched field 只在命中规则时存在。
- 兼容旧 schema 时，非空 rule id 可证明 checked；rule id 为空的历史行只能保守返回 `false`，表示
  “没有可证明的检查记录”，不能据此断言旧调用绕过了规则。
- `result_summary` 是脱敏摘要，不得包含完整 prompt、完整输出或原始 provider 响应。

隐私和副作用边界：

- 不返回 API key、key 片段、Keychain 引用值、完整文件正文、完整 prompt、完整模型输出、
  完整用户 Note、provider 原始响应体、绝对路径用户名或未脱敏诊断。
- 读取日志不得执行 AI 调用、导出文件、打开 Finder、清除日志、修改 AI 设置、修改 provider
  配置、编辑隐私规则、删除 AI 结果或触碰用户文件。
- 隐私规则命中记录必须能表达 `Skipped`、sent fields none、rule id/name、feature、
  file/batch、provider gate 和 result `No AI call was made`。
- AI/feature 在 privacy gate 之前被禁用的记录使用 `privacy_rules_checked = false`；成功、失败、no-input、
  privacy skip 等已经经过 gate 的记录使用 `true`。

错误：

- `Db`：filter/pagination 无效，`ai_call_log` schema 或 SQLite 查询失败。
- `PermissionDenied`：repository metadata 或 SQLite 文件不可读。

页面消费状态：

- AI call log surface 可以从合同得到加载成功后的表格、详情、过滤空态、远程标记、隐私 skipped 说明、
  Provider Test 详情和默认 90 天保留说明。
- remote provider settings surface/AI category suggestion surface/AI summary editor surface/AI tag suggestion surface/semantic search surface/AI privacy rules surface/AI fallback surface 只能通过 `call_log_id` 或过滤条件跳转到
  AI call log surface；本合同不提供这些页面的 AI 生成、隐私规则 CRUD、fallback 或 provider enable 能力。
- 本合同不新增 control map 之外的页面能力。

### `clear_ai_call_log(repoPath: String, request: AiCallLogClearRequest) throws -> AiCallLogClearReport`

```swift
let report = try AreaMatrix.clearAiCallLog(
    repoPath: repoPath,
    request: AiCallLogClearRequest(scope: .all, entryIds: [], olderThan: nil)
)
```

AI call log 的 AI 调用日志清理入口，服务 AI call log surface 的 `Clear log...`、`Delete selected`
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

- AI call log surface 可以从 `deleted_count`、`remaining_count` 和 `cleared_at` 刷新空态、toast 和表格。
- 本合同不实现 redacted export、保存面板、Reveal file、AI 调用执行或相邻页面能力。

### `generate_ai_summary(repoPath: String, request: AiSummaryGenerationRequest) throws -> AiSummaryDraft`

```swift
let draft = try AreaMatrix.generateAiSummary(
    repoPath: repoPath,
    request: AiSummaryGenerationRequest(
        operationId: UUID().uuidString.lowercased(),
        retryOfOperationId: nil,
        fileId: file.id,
        providerScope: .localPreferred,
        contextPolicy: .metadataAndExtractedText,
        privacyPolicyRef: snapshot.config.privacyPolicyRef,
        regenerateExisting: false,
        contentLocale: resolvedRepositoryContentLocale
    )
)
```

AI summary 的 AI 摘要草稿生成入口，服务 `AI summary editor surface ai-summary-editor` 的
`Generate summary` 和确认后的 `Regenerate...`。输入是已初始化 `repoPath` 和一个
`AiSummaryGenerationRequest`：

- `file_id`：一个 active file row。实现必须拒绝缺失、删除态或不可访问的 file id。
- `operation_id`：本次用户触发 attempt 的唯一 UUID；必须在 privacy/provider await 前持久化冻结 context。
- `retry_of_operation_id`：仅在终态失败后用户显式 Retry 时指向前一次；resume/fallback 必须继续使用旧 ID。
- `provider_scope`：`LocalOnly`、`LocalPreferred` 或 `RemoteAllowed`，只表达本次生成允许的
  provider 路线；远程仍必须经过 AI settings、remote provider configuration 和 AI privacy rules gate。
- `context_policy`：`MetadataOnly`、`MetadataAndExtractedText` 或
  `MetadataTextAndNotes`，表示调用方允许的最大上下文字段集合。
- `privacy_policy_ref`：可选稳定隐私策略引用。规则内容和 CRUD 属于 AI privacy rules，不内嵌在本请求。
- `regenerate_existing`：调用方已完成 Regenerate 二次确认时为 true；取消确认不得调用本 API。
- `content_locale`：调用开始时已解析并冻结的 `zh-Hans` 或 `en`。该值同时写入 local/remote runtime
  payload；runtime 不得读取应用或资料库的可变全局语言。

返回 `AiSummaryDraft`：

- `operation_id`：逐字回传本次 attempt identity，后续 Save 必须使用同一个值。
- `status`：`Draft`、`Skipped` 或 `Unavailable`。
- `summary_text`：生成的摘要草稿。只有 `Draft` 状态可包含文本，用户点击 Save 前不得持久化。
- `draft_id`：不透明草稿 id，供 save 时关联同一生成结果；不得包含 prompt、文件内容或 provider
  原始响应。
- `route`：`Local` 或 `Remote`，用于来源 badge 和 AI 调用日志追溯。
- `model_name`：脱敏模型或 provider 展示名，不得包含 API key、key 片段或原始 provider 响应。
- `generated_at`：草稿生成时间，未知时为 nil。
- `used_context`：实际使用或允许展示的字段类型，包含 filename、repo-relative path、
  extracted text excerpt、existing AI summary、note summary、tag/category context。
- `skipped_reason`：`AiDisabled`、`FeatureDisabled`、`ProviderUnavailable`、`PrivacyRule` 或
  `NoEligibleInput`。`CallLogUnavailable` 是合同预留值，当前实现对 call log gate 失败直接返回
  `Db` 错误而不是结构化 Skipped。
- `privacy_rule_id` / `call_log_id`：供页面跳转隐私规则和调用日志；具体日志读写属于 AI call log，
  隐私规则详情属于 AI privacy rules。
- `requires_user_save`：必须为 true。生成结果默认是草稿，不能直接写正式摘要。
- `character_count`：摘要长度，供 AI summary editor surface 字数提示和 VoiceOver 文案使用。

副作用边界：

- 本 API 只生成摘要草稿；不得保存正式摘要，不得覆盖用户 Note，不得写入或修改用户原文件，
  不得修改 tags、categories、saved searches、generated overview、change log 或 undo/redo。
- `Regenerate...` 只能在 UI 已确认后调用；若 gate 失败，必须保留现有草稿或已保存摘要。
- 远程路线必须同时通过 AI settings、remote provider gate、AI privacy gate、
  feature scope 和 AI call log gate；本 API 不启用远程 provider，不保存 API key，不绕过隐私规则。
- 隐私规则命中时必须返回 `Skipped` / `PrivacyRule`，`used_context` 为空或只包含允许展示字段；
  sent fields 由 AI call log 记录为 none。
- 失败、跳过或取消不得改变文件、摘要、notes、tags、分类、AI settings、provider metadata、
  privacy rules、generated overview 或任何用户文件；AI call log 除外，skip / 失败 / 不可用
  同样登记调用日志行并返回 `call_log_id`（隐私跳过的 sent fields 记录为 none）。

错误：

- `Config`：`repoPath`、`file_id`、`provider_scope`、`context_policy`、`privacy_policy_ref` 或
  AI gate 配置无效；AI 关闭或功能关闭也可返回结构化 `Skipped`，由实现按 UX 需要选择。
- `FileNotFound`：目标 file id 不存在、已删除或实现无法找到对应 active file metadata。
- `PermissionDenied`：repository metadata、允许的上下文字段、本地模型状态或 provider credential
  reference 无法 inspection。
- `Db`：summary metadata、AI call log gate 或相关 repository metadata 读取/写入失败。

页面消费状态：

- `operation_id`、`content_locale` 与 `format_contract_version` 是生成开始时冻结的完整 provenance；保存时必须
  原样带回，Swift 不复制 Core 的 format 常量，也不从当前设置重新解析 locale。
- AI summary editor surface 可以从合同得到 Draft、Generated locally/remotely、model、generated time、used fields、
  skipped by privacy rule、call log id、privacy rule id、character count 和“必须 Save 才能持久化”的状态。
- AI fallback surface 可以从 `status`、`skipped_reason`、`route` 和 `call_log_id` 渲染摘要生成的 AI off、
  provider unavailable、privacy skipped、local/remote failure 和非 AI 回退入口。
- 本合同不新增 control map 之外的页面能力；隐私规则由 AI privacy rules 覆盖，AI 调用日志由 AI call log
  覆盖，fallback reason matrix 由 AI fallback 覆盖，多文档摘要和知识库摘要不属于本合同范围。

### `save_ai_summary(repoPath: String, request: AiSummarySaveRequest) throws -> AiSummarySaveReport`

```swift
let report = try AreaMatrix.saveAiSummary(
    repoPath: repoPath,
    request: AiSummarySaveRequest(
        fileId: file.id,
        expectedContentRevision: savedState.contentRevision,
        confirmReplaceUserOwned: replacementConfirmationAccepted,
        summaryText: draftText,
        draftId: draft.draftId,
        route: draft.route,
        modelName: draft.modelName,
        generatedAt: draft.generatedAt,
        usedContext: draft.usedContext,
        privacyRuleId: draft.privacyRuleId,
        callLogId: draft.callLogId,
        ownership: didEditDraft ? .userOwned : .generated,
        operationId: draft.operationId,
        contentLocale: frozenContentLocale,
        formatContractVersion: currentAiSummaryFormatVersion
    )
)
```

AI summary 的 AI 摘要保存入口，服务 AI summary editor surface 的 `Save`、`Retry save` 和保存后来源信息刷新。输入：

- `file_id`：一个 active file row。
- `expected_content_revision`：调用方观察到的 content revision；没有历史摘要时为 0。Core 在 immediate
  transaction 中比较，不匹配返回结构化 conflict 并零写入。
- `confirm_replace_user_owned`：当前已保存 ownership 为 `user_owned` 时必须为 true；该位不能绕过 revision CAS。
- `summary_text`：要保存的摘要文本，可来自 AI 草稿或用户编辑后的草稿；不能为空，也不得超出实现
  定义的长度上限。
- `draft_id`：生成入口返回的不透明草稿 id；没有 AI 生成来源时可为空。
- `route` / `model_name` / `generated_at` / `used_context`：保存后的来源信息，只存脱敏 provenance。
- `privacy_rule_id` / `call_log_id`：用于跳转隐私规则和 AI 调用日志。
- `ownership`：未编辑 AI 草稿为 `Generated`；用户编辑后的摘要为 `UserOwned`。不能把已有 user-owned
  内容降级为 generated。
- `operation_id` / `content_locale` / `format_contract_version`：不可伪造为显示文案的稳定 provenance；
  operation 必须存在并与生成 draft/context 相符。

返回 `AiSummarySaveReport`：

- `saved_summary`：持久化后的摘要文本，供编辑区刷新和失败恢复基线使用。
- `content_revision` / `ownership`：保存后的新 revision 和所有权状态。
- `saved_at`：保存完成时间。
- `route`、`model_name`、`generated_at`、`used_context`、`privacy_rule_id`、`call_log_id`、
  `operation_id`、`content_locale`、`format_contract_version`：保存后的来源和追溯字段。
- `character_count`：保存摘要长度，供 AI summary editor surface 计数器、状态文案和 VoiceOver 使用。

副作用边界：

- 只允许保存 AreaMatrix-owned summary metadata；不得覆盖用户 Note，不得写入、删除、移动、重命名、
  Trash 或覆盖用户原文件。
- 不删除 extracted text、tags、AI call log、AI settings、provider metadata、Keychain/API key、
  privacy rules、classifier rules、change log、undo/redo 或 generated overview。
- 保存失败必须保留草稿内容和上一次已保存摘要；不得写入半成品导致 UI 无法恢复。
- 任何保存都禁止静默覆盖；generated 结果也必须由用户显式 Save。user-owned replacement 还必须经过
  old/new preview confirmation。stale revision、缺少确认或 provenance 不匹配全部零写入失败。
- 本 API 不生成摘要、不发起 AI 调用、不启用远程 provider、不编辑隐私规则、不实现多文档摘要。

错误：

- `Config`：`repoPath`、`file_id`、`summary_text`、`draft_id`、ownership 或 provenance 字段无效。
- `RevisionConflict(resource = ai_summary_content_revision)`：content revision stale，并携带调用方观察到的
  `expected_revision` 与事务内最新 `current_revision`；Swift 必须显式加载最新摘要并保留本地草稿。
- `Conflict`：user-owned replacement 未确认或 operation provenance 不匹配。
- `FileNotFound`：目标 file id 不存在、已删除或实现无法找到对应 active file metadata。
- `PermissionDenied`：summary metadata 不可写。
- `Db`：summary metadata 或相关 repository metadata 持久化失败。

页面消费状态：

- AI summary editor surface 可以从返回值刷新保存成功后的摘要文本、Saved/Edited by you 状态、来源信息、字符数、
  View AI call 和 View privacy rule 链接。
- 本合同不新增 control map 之外的页面能力。

### `clear_ai_summary(repoPath: String, request: AiSummaryClearRequest) throws -> AiSummaryClearReport`

```swift
let report = try AreaMatrix.clearAiSummary(
    repoPath: repoPath,
    request: AiSummaryClearRequest(
        fileId: file.id,
        expectedContentRevision: savedState.contentRevision,
        confirmed: true
    )
)
```

AI summary 的 AI 摘要清除入口，服务 AI summary editor surface 的 `Clear summary...` 确认 sheet。输入：

- `file_id`：一个 active file row。
- `expected_content_revision`：清除也必须 CAS，不能让旧窗口删除较新的用户编辑。
- `confirmed`：调用方已经展示并确认 `Clear AI summary?`；为 false 必须返回结构化 `Config` 错误。

返回：

- `cleared`：是否确实清除了已保存摘要。
- `content_revision`：清除后仍单调递增的 revision；revision tombstone 防止旧 expected=0 草稿重新覆盖。
- `cleared_at`：清除完成时间。

副作用边界：

- 只清除 AreaMatrix-owned AI summary metadata。
- 不删除、移动、重命名、Trash、覆盖或重新分类用户文件。
- 不删除用户 Note、extracted text、tags、AI call log、AI settings、provider metadata、Keychain/API key、
  privacy rules、classifier rules、change log、undo/redo 或 generated overview。
- 清除失败必须保留原已保存摘要和来源信息；不得静默吞错。
- content revision stale 返回
  `RevisionConflict(resource = ai_summary_content_revision, expected_revision, current_revision)`；Swift 重新加载
  最新摘要后，用户必须再次检查并确认 Clear，不能使用旧 revision 静默重试。

错误：

- `Config`：`repoPath`、`file_id` 无效，或缺少确认。
- `FileNotFound`：目标 file id 不存在、已删除或实现无法找到对应 active file metadata。
- `PermissionDenied`：summary metadata 不可写。
- `Db`：summary metadata 或相关 repository metadata 持久化失败。

页面消费状态：

- AI summary editor surface 可以从 `cleared` 和 `cleared_at` 刷新 `No AI summary yet.` 空态、toast 和来源信息隐藏。
- 本合同不实现 Note 清除、文件删除、日志清理、隐私规则编辑、AI 调用执行或相邻页面能力。

### `suggest_tags_with_ai(repoPath: String, request: AiTagSuggestionRequest) throws -> AiTagSuggestionReport`

```swift
let report = try AreaMatrix.suggestTagsWithAi(
    repoPath: repoPath,
    request: AiTagSuggestionRequest(
        fileId: file.id,
        candidateTags: ["finance", "invoice"],
        privacyPolicyRef: snapshot.config.privacyPolicyRef,
        contentLocale: frozenRepositoryContentLocale
    )
)
```

AI tag suggestions 的 AI 标签建议入口，服务 `AI tag suggestion surface ai-tags-suggestion` 的 review sheet。输入：

- `file_id`：一个 active file row。实现必须拒绝缺失、删除态或不可访问的 file id。
- `candidate_tags`：调用方可提供的候选标签或 tag registry 摘要，用来提示合并、复用或避免重复。
  候选标签只作为建议上下文，不代表要写入的标签。
- `privacy_policy_ref`：可选稳定隐私策略引用。规则内容和 CRUD 属于 AI privacy rules，不内嵌在本请求。
- `content_locale`：在进入 privacy/provider await 前冻结的 `zh-Hans` 或 `en`。它控制本次可持久化的
  suggestion display name 和 reason；automatic provider fallback 不能重新解析语言。

返回 `AiTagSuggestionReport`：

- `status`：`Suggested`、`NoSuggestion`、`Skipped` 或 `Unavailable`。
- `suggestions`：建议标签行，包含 `suggestion_id`、`slug`、`display_name`、`confidence`、
  `reason`、行状态、合并动作、匹配到的现有标签和默认选择状态。
- `route` / `model_name` / `generated_at`：脱敏来源信息，不得包含 API key、完整 prompt、
  provider 原始响应或文件内容。
- `used_context`：实际使用或允许展示的字段类型，包含 filename、repo-relative path、limited
  extracted text excerpt、AI summary、note summary、existing tags 或 tag registry。
- `skipped_reason`：`AiDisabled`、`FeatureDisabled`、`ProviderUnavailable`、`PrivacyRule` 或
  `NoEligibleInput`。`CallLogUnavailable` 是合同预留值，当前实现对 call log gate 失败直接返回
  `Db` 错误而不是结构化 Skipped。
- `privacy_rule_id` / `call_log_id`：供页面跳转隐私规则和调用日志；具体日志读写属于 AI call log，
  隐私规则详情属于 AI privacy rules。
- `requires_user_confirmation`：必须为 true。建议在用户采纳前不得写入正式标签。
- `confidence_threshold`、`contents_read`、`ai_used`、`network_used`：供 AI tag suggestion surface 展示高置信阈值、
  内容读取、AI 使用和远程调用边界。

副作用边界：

- 本 API 只生成建议草稿；不得创建、修改、删除或采纳标签，不得写 `change_log`、undo/redo、
  AI settings、provider metadata、privacy rules、generated overview、notes 或任何用户文件。
- 远程路线必须同时通过 AI settings、remote provider gate、AI privacy gate、
  feature scope 和 AI call log gate；本 API 不启用远程 provider，不保存 API key，不绕过隐私规则。
- 隐私规则命中时必须返回 `Skipped` / `PrivacyRule`，`suggestions` 为空，
  `used_context` 为空或只包含允许展示字段，且不得调用 provider。
- 低置信度建议只能作为可审阅行返回；`Accept high confidence` 由页面按 `confidence_threshold`
  选择，不得由生成 API 写入标签。

错误：

- `Config`：`repoPath`、候选标签、隐私策略引用或 AI gate 配置无效。
- `FileNotFound`：目标 file id 不存在、已删除或实现无法找到对应 active file metadata。
- `Db`：file metadata、tag registry、AI call log gate 或相关 repository metadata 读取失败。

页面消费状态：

- AI tag suggestion surface 可以从合同得到建议标签、confidence、reason、local/remote route、used fields、
  existing/merge hints、privacy skipped、call log id、privacy rule id、高置信阈值，以及
  “必须确认后才能写入”的状态。
- 本合同不新增 control map 之外的页面能力；隐私规则由 AI privacy rules 覆盖，AI 调用日志由 AI call log
  覆盖，真实 tag 写入只通过 `apply_ai_tag_suggestions` 的用户确认入口。

### `apply_ai_tag_suggestions(repoPath: String, request: ApplyAiTagSuggestionsRequest) throws -> AiTagSuggestionApplyReport`

```swift
let report = try AreaMatrix.applyAiTagSuggestions(
    repoPath: repoPath,
    request: ApplyAiTagSuggestionsRequest(
        fileId: file.id,
        suggestions: selectedSuggestions,
        callLogId: report.callLogId,
        privacyRuleId: report.privacyRuleId,
        confirmed: true
    )
)
```

AI tag suggestions 的 AI 标签建议采纳入口，服务 AI tag suggestion surface 的 `+`、`Accept selected` 和确认后的
batch apply。输入：

- `file_id`：一个 active file row。
- `suggestions`：用户明确选中或编辑后的建议行。未选、Reject、Cancel 或低置信度未选择行不得提交。
- `call_log_id` / `privacy_rule_id`：来自生成结果的可选追溯信息。
- `confirmed`：调用方已经完成 single action 或 batch 确认；为 false 必须返回结构化 `Config` 错误。

输出 `AiTagSuggestionApplyReport`：

- `requested_count`、`applied_count`、`skipped_count`、`failed_count`：供 single/batch 结果和部分失败 UI 使用。
- `item_results`：逐建议行结果，`status` 为 `Applied`、`AlreadyAdded` 或 `Failed`。
- `tag_set`：采纳后的当前标签状态，供详情 Tags 区和导入结果刷新。
- `undo_token`：新增关系进入 undo action log stack 后的 token；没有新增关系时为 `nil`。
- `call_log_id`：保留 AI 生成来源追溯。
- `refresh_targets`：稳定刷新建议，至少覆盖 `tags`、`change_log`、`undo_actions` 和 `ai_call_log`。

副作用边界：

- 只允许在用户确认后创建或复用规范化 tag、写当前文件 tag relation、记录 change log、
  关联 AI call log provenance，并返回 undo token。
- 不生成 AI 建议、不执行 provider、不启用远程 AI、不修改隐私规则、不自动采纳未提交建议、
  不移动、删除、重命名、Trash、覆盖或读取用户文件内容。
- 部分失败时已成功写入的标签保持，失败项必须在 `item_results` 中可见，不得静默吞错。

错误：

- `Config`：`repoPath`、确认状态、建议行、编辑后的 tag 名称或追溯 id 无效。
- `FileNotFound`：目标 file id 不存在、已删除或实现无法找到对应 active file metadata。
- `Db`：tag metadata、change log、undo action 或 AI call log provenance 持久化失败。

页面消费状态：

- AI tag suggestion surface 可以从合同得到成功/失败/重复数量、逐行失败原因、刷新后的 tag set、undo token 和
  AI call log 追溯状态。
- 本合同不实现 AI privacy rules 隐私规则编辑、AI call log surface 日志列表、undo action 执行或 batch 页面状态管理。

### `list_ai_privacy_rules(repoPath: String) throws -> AiPrivacyRulesSnapshot`

```swift
let snapshot = try AreaMatrix.listAiPrivacyRules(repoPath: repoPath)
if !snapshot.privacyGateEnabled {
    print("Remote AI is blocked by privacy gate")
}
```

AI privacy rules 的 AI 隐私规则读取入口，服务 `AI privacy rules surface ai-privacy-rules` 的规则表、
远程字段过滤、全局 `privacy_gate_enabled` 和只读 provider scope 状态。返回
`AiPrivacyRulesSnapshot`：

- `privacy_gate_enabled`：AI privacy rules surface 管理的远程隐私 gate。关闭时所有远程 AI 调用必须 skipped。
- `rules`：持久化的 Folder、Category、Keyword、Extension、Tag 规则，包含启用状态、匹配计数和最近命中时间。
- `remote_allowed_fields`：远程可发送字段设置，覆盖 filename、repo-relative path、extension、
  extracted text excerpt、AI summary、note summary、tag/category context。
- `provider_scope`：来自 remote provider configuration 的只读 provider gate 快照，只包含 configured、verified、
  enabled 和 feature scope，不包含 API key、Keychain reference 或 provider 原始响应。
- `remote_blocked_by_default`：默认保守策略。无规则时远程 AI 仍默认关闭，模板不得自动创建。

副作用边界：

- 读取规则不得启用或禁用 remote provider，不删除 Keychain key，不执行 AI，不写 AI call log，
  不读完整用户文件内容，不修改 AI 结果、tags、summaries、notes、classifier rules 或用户文件。
- 推荐模板只能作为 UI 候选；本 API 不自动创建默认规则。

错误：

- `Config`：`repoPath` 无效、位于 `.areamatrix/` 内部，或持久化 privacy metadata 结构无效。
- `Db`：privacy rules、字段过滤、provider gate metadata 或匹配计数无法读取。

页面消费状态：

- AI privacy rules surface 可以从合同得到规则列表、字段控制、provider 状态、默认保守策略和 gate 状态。
- AI fallback surface 可通过其他 AI 合同返回的 rule id 跳转回 AI privacy rules surface 定位规则；本读取入口不提供 fallback
  reason matrix。

### `update_ai_privacy_rules(repoPath: String, request: AiPrivacyRulesUpdateRequest) throws -> AiPrivacyRulesSnapshot`

```swift
let updated = try AreaMatrix.updateAiPrivacyRules(
    repoPath: repoPath,
    request: AiPrivacyRulesUpdateRequest(
        privacyGateEnabled: false,
        rules: editedRules,
        remoteAllowedFields: editedFields,
        providerScope: providerScope,
        confirmed: true
    )
)
```

AI privacy rules 的隐私规则保存入口。输入是 replace-style 请求：

- `privacy_gate_enabled`：AI privacy rules surface 的全局远程隐私 gate。关闭只阻止远程 AI 调用，不修改 remote provider configuration。
- `rules`：完整规则集合。规则类型固定为 Folder、Category、Keyword、Extension、Tag；
  `applies_to` 固定为 `RemoteAi` 或 `LocalAndRemoteAi`。
- `remote_allowed_fields`：完整远程字段过滤设置。缺失或重复字段必须拒绝。
- `provider_scope`：只读 provider 快照，用于校验开启 gate 时 provider 已 configured、verified、
  enabled 且 feature scope 非空；不得借本入口启用 provider。
- `confirmed`：保存、删除、模板添加或 block remote 操作已经由 UI 明确确认；为 false 必须返回
  `Config`。

返回更新后的 `AiPrivacyRulesSnapshot`，让 AI privacy rules surface 刷新规则表、字段状态、gate 状态和 provider
scope 摘要。

副作用边界：

- 只允许写 AreaMatrix-owned privacy rules、remote field filters 和 `privacy_gate_enabled` metadata。
- 不启用或禁用 remote provider，不删除 provider 配置或 Keychain key，不清理 AI call log，
  不删除既有 AI 结果，不重跑 AI，不移动、删除、重命名、Trash、覆盖或读取用户文件内容。
- 保存失败必须保留上一份可读规则和 gate 状态，不得写入半规则集。

错误：

- `Config`：规则、pattern、字段集合、provider scope 或确认状态无效。
- `Db`：privacy metadata 无法原子写入或写后读取失败。

页面消费状态：

- AI privacy rules surface 可以从返回快照恢复保存成功基线、展示失败回滚状态，并继续区分 privacy gate 与 provider
  disable。
- 本合同不新增 control map 之外的页面能力；provider key/scope/test 属于 remote provider configuration，AI call log 属于
  AI call log，AI 结果生成和保存属于各自 AI 能力合同。

### `evaluate_ai_privacy(repoPath: String, request: AiPrivacyEvaluationRequest) throws -> AiPrivacyEvaluationReport`

```swift
let report = try AreaMatrix.evaluateAiPrivacy(
    repoPath: repoPath,
    request: AiPrivacyEvaluationRequest(
        feature: .autoSummaries,
        route: .remote,
        requestedFields: [.fileName, .extractedTextExcerpt],
        privacyGateEnabled: snapshot.privacyGateEnabled,
        providerScope: snapshot.providerScope,
        rules: editedRules,
        remoteAllowedFields: editedFields,
        context: fileContext
    )
)
```

AI privacy rules 的隐私 gate 评估入口。AI 分类、摘要、标签和语义搜索实现必须在准备本地或远程输入前调用
等价评估逻辑。输入包含：

- `feature`：发起调用的 AI 功能，必须受 AI settings/remote provider configuration scope 和 AI privacy rules gate 联合约束。
- `route`：`Local` 或 `Remote`。远程路线还必须通过 provider scope、privacy gate 和字段过滤。
- `requested_fields`：候选输入字段集合；为空或重复必须拒绝。
- `privacy_gate_enabled`、`provider_scope`、`rules`、`remote_allowed_fields`：本次评估使用的 gate
  快照。
- `context`：文件 id、repo-relative path、file name、category、extension 和 tags。合同不接受完整
  文件正文、完整用户 Note、prompt 或 provider response。

返回 `AiPrivacyEvaluationReport`：

- `decision`：`Allowed`、`Denied` 或 `Skipped`。
- `skipped_reason`：`PrivacyGateDisabled`、`ScopeNotAllowed`、`ProviderNotConfigured`、
  `ProviderNotVerified`、`ProviderDisabled`、`PrivacyRule`、`FieldRule` 或 `NoEligibleInput`。
- `provider_gate_reason`：单独暴露 provider / privacy gate 阻断来源，供 AI fallback surface 和 AI call log surface 展示。
- `matched_rules`、`matched_field_type`：跳转 AI privacy rules surface 和 AI call log surface 追溯所需的规则、字段信息。
- `allowed_fields`、`blocked_fields`、`sent_fields`：实际可发送字段类别。任何 privacy skipped
  都必须让 `sent_fields` 为空。
- `message`：脱敏、可展示状态说明，不得包含完整路径、文件内容、API key 或 provider 原始响应。

副作用边界：

- 评估只产生决策报告；不得执行 AI、写 AI call log、保存摘要/标签/分类、编辑隐私规则、启用 provider
  或触碰用户文件。
- Retry、fallback、日志持久化和具体 AI 调用由各自能力负责；本合同只定义可复用隐私决策形状。

错误：

- `Config`：`repoPath`、字段集合、规则、provider scope 或 context 无效。

页面消费状态：

- AI privacy rules surface 的 `Test rules` 可以从报告得到 allow/deny/skipped、provider gate reason、命中规则和字段。
- AI fallback surface 可以从 skipped reason、provider gate reason、matched rule id、matched field type、
  sent fields none 和 display-safe message 渲染隐私跳过与非 AI 回退。
- 本合同不新增 control map 之外的页面能力；它只覆盖 AI privacy rules 的规则、字段和 gate 决策。

### `get_ai_fallback_status(repoPath: String, request: AiFallbackStatusRequest) throws -> AiFallbackStatus`

```swift
let status = try AreaMatrix.getAiFallbackStatus(
    repoPath: repoPath,
    request: AiFallbackStatusRequest(
        operation: .semanticSearch,
        route: .remote,
        providerError: .remoteFailed,
        providerErrorCode: "ProviderUnavailable",
        privacyDecision: .allowed,
        privacySkippedReason: nil,
        categorySkippedReason: nil,
        semanticFallbackReason: nil,
        callLogStatus: .failed,
        callLogId: callLogId,
        privacyRuleId: nil,
        retryAfter: nil
    )
)
```

AI fallback 的 AI fallback 状态标准化入口，服务 `AI fallback`，并接收 AI category suggestion 和
semantic search 已返回的 fallback metadata。输入是已初始化 `repoPath` 和一个
`AiFallbackStatusRequest`：

- `operation`：`ClassificationSuggestion`、`SemanticSearch` 或 `EmbeddingIndexBuild`。
- `route`：失败或跳过发生在 `Local` / `Remote` 路线时提供；未进入 AI 路线时为 `nil`。
- `provider_error` / `provider_error_code`：脱敏后的 provider/runtime 分类与稳定错误码。
  不得传入 provider 原始响应、API key、prompt、文件正文或完整路径。
- `privacy_decision` / `privacy_skipped_reason`：AI privacy rules 已评估出的隐私决策。
- `category_skipped_reason`：AI category suggestion 分类建议的 skipped/unavailable reason。
- `semantic_fallback_reason`：semantic search 语义搜索或索引构建的 fallback reason。
- `call_log_status` / `call_log_id`：AI call log 调用日志状态和跳转 id。
- `privacy_rule_id`：命中隐私规则时用于跳转 AI privacy rules surface 的稳定规则 id。
- `retry_after`：rate limit 的建议重试时间戳；没有时立即 retry 必须禁用。

返回 `AiFallbackStatus`：

- `kind`：`AiDisabled`、`FeatureDisabled`、`LocalModelNotReady`、`RemoteNotConfigured`、
  `RemoteFailed`、`ProviderUnavailable`、`PrivacySkipped`、`SemanticIndexNotReady`、
  `NoEligibleInput`、`NormalSearchUnavailable`、`CallLogUnavailable`、`RateLimited`、
  `Timeout` 或 `InternalFailure`。
- `category`：`Disabled`、`Skipped`、`Unavailable` 或 `Error`，供 UI 区分中性跳过和错误。
- `title` / `message`：可展示文案，不包含 provider 原始输出、密钥、完整 prompt、完整文件内容或
  绝对用户路径。
- `retryable` / `retry_disabled_reason`：Retry 是否可立即提供，以及禁用原因。
- `primary_action` / `secondary_action`：标准恢复动作，如 `Retry`、`OpenLocalModelStatus`、
  `ConfigureRemoteAi`、`ViewPrivacyRule`、`ViewCallLog`、`BuildSemanticIndex` 或
  `UseNormalSearch`。
- `non_ai_fallback_action`：宿主级非 AI 回退动作。分类宿主必须渲染为 `Classify manually`，
  语义搜索宿主必须渲染为 `Use normal search`，不得显示抽象占位。
- `route`、`call_log_id`、`privacy_rule_id`、`retry_after`：保留追溯和 action enablement 状态。

副作用边界：

- 本 API 只标准化 fallback 状态；不得执行 AI、切换 provider、自动启用远程 AI、评估或修改隐私规则、
  写分类/标签/摘要、保存 provider key、读取用户文件正文、写用户文件或触碰 `apps/**`。
- 隐私跳过不得提供 Retry；remote failed / timeout 只能 retry 同一 provider、model、scope 和输入快照，
  且 retry 前仍必须重新检查 AI privacy rules。
- 自动 provider failover 不在当前 AI fallback 合同内；本地失败不得自动启用远程 AI。
- 实现可以按 AI call log 合同记录 AI call failure，但记录内容必须保持 sent fields、error code 和
  result summary 脱敏。

错误：

- `Config`：`repoPath`、reason metadata、provider error code、privacy rule id、call log id 或
  retry timestamp 无效。
- `PermissionDenied`：实现需要 inspection fallback metadata、call log 或 privacy metadata 但被权限阻断。
- `Internal`：fallback 状态从脱敏 metadata 解析失败。

页面消费状态：

- AI fallback surface 可以从 `kind`、`category`、`title`、`message`、`retryable`、action 字段、`route`、
  `call_log_id`、`privacy_rule_id` 和 `retry_after` 渲染失败、禁用、隐私跳过、模型不可用、语义索引未就绪、
  rate limit、timeout、日志入口和非 AI 回退。
- AI category suggestion surface 能从 `non_ai_fallback_action = ClassifyManually` 得到分类手动回退状态。
- semantic search surface 能从 `non_ai_fallback_action = UseNormalSearch` 和 `BuildSemanticIndex` 得到普通搜索与索引构建入口。
- 本合同不新增 control map 之外的页面能力；AI 调用日志仍由 AI call log 覆盖，隐私规则由 AI privacy rules 覆盖，
  分类/标签/摘要写入和普通搜索仍由各自能力覆盖。

### `semantic_search(repoPath: String, query: String, filter: SearchFilter, pagination: SearchPagination) throws -> SemanticSearchResultPage`

```swift
let page = try AreaMatrix.semanticSearch(
    repoPath: repoPath,
    query: "上个月的发票",
    filter: currentSearchFilter,
    pagination: SearchPagination(limit: 50, offset: 0)
)
```

semantic search 的语义搜索入口，服务 `semantic search results` 的语义结果组，
并为 `AI fallback` 提供语义不可用、隐私跳过、provider 不可用和普通搜索
回退状态。输入复用普通搜索 `SearchFilter` 和 `SearchPagination`，使 filters、
scope 和分页与普通搜索保持同一合同。

返回 `SemanticSearchResultPage`：

- `query`：自然语言 query 回显。
- `semantic_total_count` / `normal_total_count`：语义组和普通搜索组分页前数量。
- `semantic_matches`：第一组 `Semantic matches`，每行包含 `SearchFileResult`、
  `relevance`、`matched_reason`、`used_fields`、`route`、dedupe 标记、call log id 和
  privacy rule id。
- `normal_matches`：第二组 `Normal search matches`，复用普通搜索结果并标记
  `deduped_by_semantic`。
- `deduped_normal_count`：被语义组折叠的普通搜索重复数量。
- `index_status`：`Ready`、`NotReady`、`Building`、`Paused`、`Canceled`、`Failed` 或
  `Partial`。
- `route`：`Local` 或 `Remote`；未进入 AI 路线时为 `nil`。远程路线在 remote provider 已配置且 privacy / call-log 门禁均通过时执行外部 runtime；`RateLimited` / `Timeout` 由远程 runtime 映射为稳定 fallback。
- `fallback_reason` / `fallback_message`：`AiDisabled`、`FeatureDisabled`、
  `ProviderUnavailable`、`PrivacyRule`、`SemanticIndexNotReady`、`CallLogUnavailable`、
  `NoEligibleInput`、`NormalSearchUnavailable`、`RateLimited` 或 `Timeout`。
- `call_log_id` / `privacy_rule_id`：跳转 AI call log surface / AI privacy rules surface 所需的追溯 id。
- `low_confidence`：语义组存在低置信结果时为 true。

副作用边界：

- 语义搜索只读取 repository metadata、semantic index metadata、允许的安全上下文和普通搜索
  fallback 数据；不得写 tags、分类、摘要、notes、saved searches、change log、undo/redo、
  generated overview 或用户文件。
- 远程语义路线必须同时通过 AI settings、remote provider gate、AI privacy gate、
  feature scope 和 AI call log gate；不得自动启用远程 provider，不保存 API key 明文，
  不把 key、provider 原始响应、完整 prompt、完整输出、完整文件内容或绝对路径用户名放入返回值、
  日志、诊断或错误文案。
- Core 必须以 `Semantic matches` / `Normal search matches` 两组表达结果，不生成不可解释的单一
  混合分数。普通搜索失败不得清空已可用的语义组；语义失败也不得阻断普通搜索回退展示。
- 本 API 不创建或刷新 embedding index；索引构建只通过 `build_embedding_index`。

错误：

- `Config`：`repoPath`、query、filter、pagination、privacy metadata 或 AI gate 配置无效。
- `PermissionDenied`：repository metadata、允许的上下文字段、本地模型状态或 provider credential
  reference 无法 inspection。
- `Db`：semantic index metadata、普通搜索 fallback、AI call log 或 file metadata 无法读取。
- `Internal`：AI runtime、provider adapter、embedding runtime 或脱敏后的结果解析发生未归类失败。

页面消费状态：

- semantic search surface 可以从合同得到 query、semantic/normal 分组结果、relevance、matched reason、used fields、
  local/remote badge、index status、low-confidence、dedupe、分页、call log id、privacy rule id 和
  普通搜索 fallback 状态。
- AI fallback surface 可以从 `fallback_reason`、`fallback_message`、`route`、`call_log_id` 和
  `privacy_rule_id` 渲染 semantic index not ready、AI disabled、provider unavailable、
  privacy skipped、timeout/rate-limit 的承接状态，并显示 `Use normal search` 或 `Build semantic index`。
- 本合同不新增 control map 之外的页面能力；普通搜索仍由 search query 覆盖，Smart List 保存仍由 saved searches/Smart List execution
  覆盖，AI 调用日志由 AI call log 覆盖，隐私规则由 AI privacy rules 覆盖，fallback reason matrix 由 AI fallback 覆盖。

### `build_embedding_index(repoPath: String, scope: SemanticIndexScope) throws -> SemanticIndexBuildReport`

```swift
let report = try AreaMatrix.buildEmbeddingIndex(
    repoPath: repoPath,
    scope: SemanticIndexScope(
        filter: currentSearchFilter,
        route: .local,
        privacyPolicyRef: snapshot.config.privacyPolicyRef,
        confirmed: true
    )
)
```

semantic search 的 embedding index 构建入口，服务 semantic search surface `Build semantic index` 确认后的
启动/重试路径。输入 `SemanticIndexScope`：

- `filter`：索引范围，复用普通搜索 filter/scope。
- `route`：可选 `Local` / `Remote` 偏好；为 `nil` 时实现按 AI settings 和 provider gate 选择。
- `privacy_policy_ref`：可选隐私策略引用。
- `confirmed`：semantic search surface `Build semantic index?` 已确认；为 false 必须返回 `Config` 错误。

返回 `SemanticIndexBuildReport`：

- `status`：索引构建后的状态。
- `route`、`provider_name`：选中的本地/远程路线和脱敏 provider/model 名称。
- `total_count`、`processed_count`、`skipped_count`、`failed_count`、`privacy_skipped_count`：
  构建状态、部分失败和隐私跳过计数。
- `call_log_id`：构建或跳过记录的追溯 id。
- `fallback_reason` / `message`：无法开始构建时的稳定阻断原因和脱敏说明。

副作用边界：

- 允许的写入仅限 AreaMatrix-owned semantic index metadata、embedding metadata、索引批次状态和
  AI call log；不得移动、删除、重命名、覆盖、Trash、导入或改写任何用户文件。
- 远程 embedding 只在远程 AI 显式启用、SemanticSearch scope 允许、测试连接成功、隐私规则通过且
  call-log gate 可用后进入；隐私命中文件不得进入远程队列，sent fields 必须为 none。
  远程路线通过 `AREAMATRIX_AI_SEMANTIC_REMOTE_RUNTIME` 外部 runtime 执行；`RateLimited` / `Timeout`
  映射为稳定 fallback，不泄漏 provider 原始输出。
- 取消、暂停、清理未提交 index batch 和远程队列停止语义由独立的 semantic search
  recovery / queue-management 合同承载；本合同只定义启动和报告形状。

错误：

- `Config`：`repoPath`、scope、privacy reference、route 或确认状态无效。
- `PermissionDenied`：repository metadata、允许的上下文字段、本地模型或 provider credential
  reference 无法 inspection。
- `Db`：embedding index metadata、AI call log 或 file metadata 无法读写。
- `Internal`：embedding runtime、provider adapter 或脱敏后的索引构建结果发生未归类失败。

页面消费状态：

- semantic search surface 可以从合同得到构建状态、文件数、已处理/跳过/失败数量、隐私跳过数量、provider、
  local/remote 路线、call log id 和 gate 阻断原因。
- AI fallback surface 可以把 `SemanticIndexNotReady` 映射到 `Build semantic index`，失败时仍保留
  `Use normal search`。
- 本合同不实现 pause/cancel/retry 队列控制、Smart List 保存、普通搜索 UI、provider 配置或隐私规则编辑。

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

副作用补充：启动 recovery 还会 purge `files.status = 'deleted'` 且 `deleted_at` 超过 30 天的元数据行（及相关 AreaMatrix 拥有 sidecar）；不硬删用户源文件、不二次清空系统 Trash。成功 purge 时会写入 `RecoveryReport.warnings` 说明。

### `preview_manual_rescan(repoPath: String) throws -> ManualRescanPreviewReport`

```swift
let preview = try await Task.detached(priority: .background) {
    try AreaMatrix.previewManualRescan(repoPath: repoPath)
}.value
print("added: \(preview.added), missing: \(preview.missingOrDeletedFromFs)")
```

rescan confirmation surface 在启用 `Run Rescan` 前必须调用该只读预览入口。Core 会扫描 repo 和
active metadata snapshot，返回 Added / Updated / Missing / Renamed candidates /
Conflicts / Unreadable / Unknown / Skipped 的结构化摘要，以及最多若干可展示样例项。

副作用边界：

- 不创建 `scan_sessions`，不写 `files`，不写 `change_log`，不修改 DB 记录。
- 不移动、不重命名、不删除、不覆盖、不 Trash、不下载用户文件。
- `Unknown` / `Missing` / `Conflicts` / `Unreadable` 只作为 Needs Review 信号，
  不会被预览当作删除或自动合并。
- 已有 `scan_sessions(kind=Reindex,status=Running)` 时返回 `Conflict`，页面必须禁用第二次 rescan。

### `reindex_from_filesystem(repoPath: String) throws -> ReindexReport`

```swift
let report = try await Task.detached(priority: .background) {
    try AreaMatrix.reindexFromFilesystem(repoPath: repoPath)
}.value
print("inserted: \(report.inserted), missing: \(report.missing), skipped: \(report.skipped)")
```

耗时与文件数成正比（1 万文件 ≈ 30s）。建议显示进度条。该 API 会跳过 `.areamatrix/`、系统临时文件、可配置忽略目录，以及 AreaMatrix 自身生成的概览文件。

实现要求：

- 创建或复用 `scan_sessions(kind=Reindex)` 行，并在 `ReindexReport.scan_session_id` 返回。
- 启动后的全量重建或外部补扫写入 `FileEntry.origin = .external`。
- 首次接管扫描由 `init_repo(mode=.adoptExisting)` 的内部流程触发，写入 `FileEntry.origin = .adopted`。
- `README.md` 作为普通用户文件索引；`AREAMATRIX.md` 与 `.areamatrix/generated/` 始终跳过。
- `ReindexReport` 和对应 `ScanSession` 返回 `inserted` / `updated` / `missing` /
  `conflicts` / `unreadable` / `unknown` / `skipped` 计数。`missing`、`conflicts`、
  `unreadable`、`unknown` 表示 UI 需要进入 Needs Review 或诊断路径，不表示 Core
  已删除、合并或解决这些项目。
- 已有 `scan_sessions(kind=Reindex,status=Running)` 时返回 `Conflict`，防止并发启动第二次手动 rescan。

错误与副作用边界：

- `Db`：scan session、`files` metadata 或诊断状态读写失败。
- `PermissionDenied`：资料库文件、目录 metadata 或 `.areamatrix/` 写入被阻断。
- `Conflict`：已有手动 rescan 正在运行。
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

metadata repair 的只创建诊断入口。调用方在用户确认修复后、任何 metadata 修复前调用，
用于保留损坏 DB 或 repair context 的 AreaMatrix-owned 引用。返回的
`snapshot_path` 必须位于 `.areamatrix/` 内，Swift 只展示引用，不解析用户文件。

输入：

- `repoPath`：已初始化资料库根目录。

输出：

- `DiagnosticsSnapshot.snapshot_path`：仓库相对路径，指向 `.areamatrix/` 下的诊断快照。
- `DiagnosticsSnapshot.created_at`：Unix 秒级时间戳。
- `DiagnosticsSnapshot.warnings`：无法完整采集但未破坏用户文件的诊断说明。

错误与副作用边界：

- `InvalidPath`：`repoPath` 为空、不安全，或命中 metadata 内部路径。
- `RepoNotInitialized`：候选目录没有 `.areamatrix/` 元数据。
- `FileNotFound`：诊断材料源路径不存在。
- `PermissionDenied`：无法写入 `.areamatrix/` 诊断位置。
- `Io`：复制或读取诊断材料失败。
- `Internal`：诊断快照路径不在 `.areamatrix/` 内等不变量失败。
- 诊断快照只做文件级复制，不打开 SQLite，因此不返回 `Db`。
- 不修改 `files`、`scan_sessions` 或用户文件。
- 不写 `AREAMATRIX.md`、`README.md` 或 `.areamatrix/generated/`。
- 云端备份恢复和自动上传诊断不属于当前诊断合同。

### `preflight_repair_metadata(repoPath: String) throws -> RepairMetadataPreflight`

```swift
let preflight = try AreaMatrix.preflightRepairMetadata(repoPath: repoPath)
repairState.apply(preflight)
```

这是 metadata repair 的只读前置检查。它只读取 `.areamatrix/`、`index.db` 和 `repo_config`，不创建、
迁移、修复或覆盖任何文件。`preflight_token` 绑定本次观察到的状态与 raw policy，mutation 必须原样
带回；Core 在 mutation 前重新执行同一 preflight，token 或状态变化返回 `Conflict`，不得把旧确认升级为
新的写入授权。

`RepairMetadataPreflight.locale_state` 的含义：

| 状态 | `repository_locale_policy` | UI 行为 |
|---|---|---|
| `Healthy` | 返回 DB 中的 exact raw policy（包括兼容别名），不做隐式规范化 | 可保留该值，显示 concrete preview |
| `MetadataAbsent` | `nil` | 不预选，用户必须选择 canonical `system` / `zh-Hans` / `en` |
| `DatabaseMissing` | `nil` | 不预选，用户必须选择 canonical policy |
| `DatabaseCorrupt` | `nil` | 不预选，用户必须选择 canonical policy |
| `LocaleMissing` | `nil` | 不预选，用户必须选择 canonical policy |
| `LocaleUnsupported` | `nil`；`unsupported_locale` 保留 exact raw 供显示 | 不预选；未知值可见但不能生成 |

只有 `Healthy` 才把 raw policy 当作可复用的 persisted policy。其他状态的用户选择必须是 canonical
`system` / `zh-Hans` / `en`，不能把 unknown raw 值带回 mutation。`requires_explicit_locale_selection`
为上述五种非健康状态置 `true`。

### `repair_metadata(repoPath: String, options: RepairOptions) throws -> RepairReport`

```swift
let report = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.repairMetadata(
        repoPath: repoPath,
        options: RepairOptions(
            preserveDiagnosticsSnapshot: true,
            preflightToken: preflight.preflightToken,
            repositoryLocalePolicy: selectedOrPreservedPolicy
        )
    )
}.value
```

metadata repair 的用户确认后入口。调用方必须先完成 `preflight_repair_metadata`，并把同一观察窗口的
token 和 repository policy 一起传入。该 API 只验证、初始化或重建 metadata DB，不启动 filesystem
reindex，不生成 overview，也不创建或恢复 scan session。`preserve_diagnostics_snapshot = true`
且现有 DB 可读取为文件时，修复前必须先保留诊断快照，并在
`RepairReport.diagnostics_snapshot_path` 返回引用。DB 缺失时没有旧数据库可复制，该字段为空。
`repository_locale_policy` 是要保留或明确写入的资料库 policy：健康状态必须逐字复用 preflight 返回的
raw 值；非健康状态必须是用户明确选择的 canonical `system` / `zh-Hans` / `en`。Core 会重新执行
preflight：健康状态要求 raw policy 和 token 仍一致；非健康状态要求仍处于对应可修复状态。任何竞态、
缺失选择或不支持的 policy 都返回 `Conflict` / `Config` 并保持原状态。

locale row 缺失或包含 unsupported exact raw value 时，repair 只能在 `BEGIN IMMEDIATE` 事务中更新该
locale row 并递增 `repo_config_revision`；不得以 locale 恢复为由重建数据库或丢失 tags、notes、history、
saved searches 等 DB-only metadata。只有 metadata / database 缺失或数据库损坏才创建 replacement DB。

输入：

- `repoPath`：资料库根目录；允许 metadata 或 DB 尚未初始化。
- `RepairOptions.preserve_diagnostics_snapshot`：是否先保留损坏状态诊断引用。
- `RepairOptions.preflight_token`：只读 preflight 返回的状态绑定 token，不能为空。
- `RepairOptions.repository_locale_policy`：保留或用户明确选择的 raw/canonical policy。

输出：

- `RepairReport.diagnostics_snapshot_path`：修复前保留的诊断快照引用，可为空。
- `RepairReport.outcome`：`Verified`、`Initialized` 或 `Rebuilt`；不包含 reindex 计数。

错误与副作用边界：

- `InvalidPath`：路径为空、不安全、不是目录或无法作为资料库根目录使用。
- `RepoNotInitialized`：`.areamatrix/` / `index.db` 是不安全的非目录、非普通文件或符号链接状态。
- `Conflict`：preflight token、metadata identity、raw policy 或观察状态已经变化。
- `Db`：SQLite 损坏、schema 读取或 replacement DB 持久化失败。
- `PermissionDenied`：`.areamatrix/` 诊断、DB 或 metadata 写入被阻断。
- `Io`：文件系统遍历、诊断材料复制或 metadata 读取失败。
- `Internal`：修复后 DB/FS 一致性检查无法满足。
- 修复只处理 `.areamatrix/` metadata；不移动、不重命名、不删除用户文件，也不覆盖用户文件。
- 修复失败不得删除用户文件，也不得清空已生成的诊断信息。
- `Initialized` / `Rebuilt` 后文件索引为空；UI 必须通过独立的 rescan confirmation 再调用
  `reindex_from_filesystem`，不能把 repair 成功当作已经恢复文件索引。

### `get_latest_scan_session(repoPath: String) throws -> ScanSession?`

返回最近一次未完成或刚完成的接管 / 重建扫描，用于首次启动向导恢复状态。

### `resume_scan_session(repoPath: String, scanSessionId: Int64) throws -> ReindexReport`

继续 `Paused` / `Interrupted` / `Failed` 的扫描。Core 需要按 `last_path` 与幂等 upsert 规则续扫；若 session 已 `Completed`，返回空 report。

### 全库 overview regeneration

### `get_overview_language_status(repoPath, contentLocale) throws -> OverviewLanguageStatus`

`get_overview_language_status(repoPath, contentLocale)` 只读计算五种状态：`NotGenerated`、`Synchronized`、
`NeedsRegeneration`、`Mixed`、`Unknown`。`NeedsRegeneration` 通过 typed reasons 精确说明
`LocaleMismatch`、`FormatMismatch`、`MissingTargets` 或 `ObsoleteTargets`；`Unknown` 表示现有输出缺少可信
provenance 或当前 bytes 与记录 hash 不符。状态计算不得检查自然语言正文。Unknown 状态下普通增量 overview
写入 fail closed；只有下面的显式全库流程可以在确认与恢复保护下替换异常 generated bytes。

### `prepare_overview_regeneration(repoPath, contentLocale) throws -> OverviewRegenerationPreflight`

`prepare_overview_regeneration(repoPath, contentLocale)` 是严格只读 preflight。它创建新的候选
`operation_id`，冻结 Repository revision、完整目标集合、concrete locale、format contract version 和
target-set hash，并返回签名 `plan_token`；它不创建 session、staging、journal 或输出文件。

### `start_overview_regeneration(repoPath, request) throws -> OverviewRegenerationSession`

`start_overview_regeneration(repoPath, request)` 要求逐字回传 operation ID、plan token、expected revision 和
显式确认。Core 在首次 staging 写入前持久化 `RecoverableOperationContext` 与全部 journal items，生成完整
staging 与 backup 后停在 `ReadyToCommit`。

### `commit_overview_regeneration(repoPath, operationId) throws -> OverviewRegenerationSession`

`commit_overview_regeneration` 再次比较 Repository revision，并在
全量验证当前目标、staging 与 backup 后进入不可取消的短 commit；发生变化、任何目标不安全或 token 失效时
零提交并保持全旧。

### `get_overview_regeneration(repoPath, operationId) throws -> OverviewRegenerationSession`

`get_overview_regeneration` 只读返回 durable 状态。Repository 启动或重新打开时调用
并且不改变 session、journal、staging、backup 或 active output。

### `recover_overview_regeneration_on_startup(repoPath) throws -> OverviewRegenerationSession?`

`recover_overview_regeneration_on_startup` 在数据库内查找唯一非终态 overview operation，无未完成操作时
返回空值，发现多个未完成操作时返回 `Db` 并保持普通 mutation 阻断。找到唯一操作后，Core 使用其 durable
operation ID、locale、payload、revision、target hash 和 format version 自动执行既有恢复流程，调用方不提供
operation ID，也不选择 roll-forward 或 rollback 方向。该入口可重复调用；settled 后再次调用返回空值。

### `resume_overview_regeneration(repoPath, operationId) throws -> OverviewRegenerationSession`

`resume_overview_regeneration` 是已知 operation ID 的显式恢复和诊断入口，复用原 operation ID、locale、
payload 和 format version，不能从当前设置补猜。

### `cancel_overview_regeneration(repoPath, operationId) throws -> OverviewRegenerationSession`

`cancel_overview_regeneration` 只在 commit 前成立，并收敛为 Canceled/全旧；Committing 后返回 conflict。
崩溃恢复先验证每个目标是否仍为 journal 中的 old/new hash：
staged plan 可验证时 roll-forward，否则仅在全部 backup 和目标状态可验证时 rollback；两侧证据都不可验证时
保持 `RollbackRequired` 并阻断普通写入。

### `rollback_overview_regeneration(repoPath, operationId) throws -> OverviewRegenerationSession`

`rollback_overview_regeneration` 只处理 Failed 或
RollbackRequired，恢复旧字节和旧 provenance，绝不覆盖第三方 hash drift。

目标白名单只有 `.areamatrix/generated/root.md`、`.areamatrix/generated/nodes/*.md` 和已启用且 marker 合法
的根 `AREAMATRIX.md` managed block。API 永远不处理 AI summary、classifier、note、tag、`README.md`、
managed block 外文本或其他用户文件。崩溃后 Repository 打开流程必须先收敛未完成 journal；收敛前所有
普通 mutation fail closed。稳定结果只能是全旧或全新，不承诺多个文件的瞬时文件系统原子交换。

错误：

- `Config`：locale、operation ID、token、target path 或 format contract 非法。
- `Conflict`：revision/token 已过期、已有 regeneration、commit 已不可取消或状态不允许该动作。
- `PermissionDenied` / `Io`：AreaMatrix-owned staging、generated 输出或合法 managed block 无法安全读写。
- `Db`：operation journal/provenance 无法事务持久化。
- `Internal`：hash、journal、rollback 或 settled-state 不变量无法满足。

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

无写入副作用：只读取 Repository 语言策略和 `.areamatrix/classifier.yaml`，不创建、不移动、
不删除文件，也不写 DB 或 SQLite sidecar。缺失、不可读或无效 classifier 不使用内置规则静默回退；
unknown Repository 策略阻断该生成式分类建议。UI 在拖入时调用以填充 ImportSheet。

错误：

- `Config`：`repoPath` / `filename` 为空，或 `classifier.yaml` 的 YAML 语法、
  schema、default category、slug、extension、keyword 无效，或 Repository 语言策略尚未规范化。
- `Classify`：classifier 规则源无法作为文件读取，分类引擎无法产生可用预览。
- `RepoNotInitialized` / `Db` / `DbLocked` / `DbCorrupted`：无法以只读方式确认 Repository 语言策略。

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
        duplicateStrategy: .skip,
        contentLocale: resolvedRepositoryContentLocale
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
    } catch CoreError.PermissionDenied(let p) {
        await showAlert("没有读取或写入权限：\(p)")
    } catch {
        await showAlert("导入失败：\(error.localizedDescription)")
    }
}
```

可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath` / `ICloudPlaceholder` / `PermissionDenied` / `Internal`。

桌面 Windows / Linux 导入页面需要展示 Move 后源文件处理结果时，应使用
`import_file_with_result`。`import_file` 保留为兼容入口，只返回已提交的
`FileEntry`。

`ImportOptions.destination` 语义：

| destination | 使用字段 | 目标规则 |
|---|---|---|
| `AutoClassify` | `override_category` 可选 | 根据 classifier 规则推断；无命中走默认分类 `inbox/` |
| `SelectedDirectory` | `target_directory` 必填 | 放入用户显式 drop 的目录，不再自动分类 |
| `Category` | `override_category` 必填 | 放入指定系统分类目录，必要时创建 `<slug>/` |

`ImportOptions.content_locale` 是本次导入开始时冻结的 `zh-Hans` 或 `en`，只供成功提交后的 generated
overview 使用。duplicate、staging、replacement、DB rollback 和源文件移除必须复用既有事务边界，不能因
语言参数改变。

### `import_file_with_result(repoPath, sourcePath, options) throws -> ImportResult`

```swift
let result = try AreaMatrix.importFileWithResult(
    repoPath: repoPath,
    sourcePath: url.path,
    options: options
)

switch result.sourceRemovalStatus {
case .removed:
    showResult("Imported")
case .retained:
    showResult("Imported, original retained")
    showDetails(result.sourceRemovalFailure)
case .notRequested:
    showResult("Imported")
}
```

desktop import flow 的 Windows / Linux 页面使用该入口作为最终提交
API。它复用 `import_file` 的真实事务式导入路径，返回：

- `entry`：成功写入 FS 和 DB 的 active `FileEntry`。
- `source_removal_status`：`NotRequested` / `Removed` / `Retained`。
- `source_removal_failure`：源文件移除失败时的结构化原因。

`StorageMode::Moved` 的执行顺序是：先 copy-to-staging、写入 repository
final 文件、写 DB、写导入日志、刷新生成概览，再尝试移除原始 source。
如果最后的 source removal 失败，不回滚已安全导入的 repository 文件；
结果必须标记 `Retained`，UI 显示 `Imported, original retained`，并且不得把
该项标记为完整 Move。

### observed import variants

`import_file_observed(repoPath, sourcePath, options, traceContext)` 与
`import_file_with_result_observed(repoPath, sourcePath, options, traceContext)` 分别保持上述两个导入入口的
返回值和事务语义，仅增加显式 `CoreTraceContext`。macOS 等支持结构化诊断的 shell 使用 observed variant；
兼容调用方可以继续使用原入口。

Core 在任何 staging、用户文件或 DB 操作前验证 context 中的 UUID、session/retry 关系、action/component catalog ID、
resource ref 和 typed attribute。无效 context 返回 `Validation` 且零副作用。有效调用为同一 Core span 发出
`started` 和 terminal `succeeded` / `failed` / `degraded` 事件；Move 已提交但原件保留时使用 `degraded`，不能误记为
完整成功。失败事件只携带稳定错误码，不携带 `CoreError` 中的原路径、文件名或底层错误字符串。事件队列、callback
或平台 writer 失败不能改变导入返回值、文件系统提交、DB 事务或 rollback 结果。

Replace 仍属于 replace confirmation / `replace confirmation surface`。Swift 平台/UI 层负责宿主 Trash / Recycle
Bin availability probe、危险确认、文件夹展开、拖拽入口和多项进度；确认后的实际 Trash mutation、DB/change
log/Undo 写入及失败回滚由 Core 负责。

可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath` / `ICloudPlaceholder` / `PermissionDenied` / `Internal`。

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
写入 `change_log.action = deleted`，并创建可撤销状态。Swift 在调用前只负责宿主 availability
probe、危险确认和 UI 状态，不得自行移动文件、写 DB/change log 或拼装 Undo。

副作用边界：

- 不提供永久删除参数，不直接物理删除目标文件。
- 不删除、移动、重命名或覆盖任何其他用户文件。
- 不清空 notes / tags 等关联 metadata。
- Indexed、Adopted、External 条目的索引移除必须使用
  `remove_index_entry`；repo-owned Missing 条目的记录移除走
  `remove_missing_file_record`。
- 如果 Trash mutation 已发生，但 metadata、change log 或 Undo 持久化失败，Core 必须尝试把文件恢复到
  原 repo 路径并回滚本次 DB 变更；回滚失败必须返回明确错误，不得报告成功或留下无 Undo 的已删除状态。

错误：

- `FileNotFound`：`fileId` 对应的 active row 不存在，或 repo-owned 文件已消失。
- `PermissionDenied`：系统 Trash、目标文件或 metadata 写入被权限阻断，或条目不是
  repo-owned（此类条目走 `remove_index_entry`）。
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
metadata（含其 Missing 状态；repo-owned Missing 记录走 `remove_missing_file_record`），
不移动、不删除、不重命名、不覆盖、不 Trash 外部源文件。
成功时 Core 只更新 metadata，使该条目不再出现在默认 list/detail 中，并写入
`change_log.action = removed_from_index`。

副作用边界：

- 不触碰外部源文件，即使 `files.source_path` 指向的文件存在。
- 不触发 iCloud placeholder 下载。
- 不删除 notes / tags 等关联 metadata，除非独立恢复/清理能力明确扩展。
- 不替代 Finder/FSEvents 外部删除同步；外部 removed 仍属于
  `sync_external_changes`。

错误：

- `FileNotFound`：`fileId` 对应的 removable active row 不存在。
- `PermissionDenied`：metadata 写入被权限阻断，或条目是 repo-owned
  （此类条目走 `delete_file`）。
- `Db`：SQLite 查询、索引移除或 change log 写入失败。
- `Internal`：状态转换出现未预期错误。

### `rename_file(repoPath, fileId, newName, contentLocale) throws -> FileEntry`

```swift
let updated = try await Task.detached {
    try AreaMatrix.renameFile(
        repoPath: repoPath,
        fileId: entry.id,
        newName: "新名字.pdf",
        contentLocale: resolvedRepositoryContentLocale
    )
}.value
appState.replaceFile(updated)
```

`newName` 是文件名而不是路径，使用与 `ImportOptions.override_filename` 相同的校验边界。
空名、路径分隔符、metadata 内部路径或禁用字符（`/ \\ : * ? " < > |`）会抛
`InvalidPath`。
`contentLocale` 是 rename 开始时冻结的 `zh-Hans` 或 `en`，只用于 repo-owned rename 成功后的
generated overview；Indexed display-name rename 仍不写 generated 文件。

副作用边界：

- Copy / Move 等 repo-owned 文件只在当前目录内执行安全 rename，更新
  `files.path`、`files.current_name`、`updated_at`，并写入 `change_log.action =
  renamed`。
- Indexed 文件只更新 `files.current_name` 和 change log，保留 `files.path`、
  `files.source_path`，且不移动、重命名或覆盖外部源文件。
- 成功 rename 不改变 `file_id`、category、tags、notes、hash、storage mode、origin
  或 source path。
- 同目录同名时复用 name-conflict resolution 的安全编号策略，不覆盖已有文件；只有编号耗尽或竞态无法
  解析时抛 `Conflict`。
- Copy / Move rename 成功后触发 generated overview 再生成；默认只写
  `.areamatrix/generated/**`，仅当配置显式允许时维护根目录 `AREAMATRIX.md`，
  不触碰用户 `README.md`。Indexed display-name rename 不触发文件系统 rename，也不
  触碰外部源文件。

错误：

- `InvalidPath`：`repoPath` 或 `newName` 为空、不安全，或命中 metadata 内部路径。
- `FileNotFound`：`fileId` 对应的 active row 不存在，或 repo-owned 文件已消失。
- `Conflict`：安全目标名无法解析，或伴生 note sidecar 的目标名已被占用。
- `PermissionDenied`：文件系统 rename 或 metadata 写入被权限阻断。
- `Io`：文件系统读写失败。
- `Db`：SQLite 查询、更新或 change log 写入失败。sidecar 内容与 DB note 不一致时也归一为 Db。
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

`preview_move_to_category` 是 category move 的确认前目标路径解析入口。输入与
`move_to_category` 相同，输出 `MoveToCategoryPreview`，包含原分类、目标分类、
当前路径、确认后最终路径、最终文件名、storage mode、是否 Index-only、是否因
name-conflict resolution 自动编号改名、确认后是否会移动 repo-owned 文件。

该函数只允许读取 classifier、DB 和文件系统状态。它必须复用
`move_to_category` 的目标路径解析、同名编号、repo-owned / Indexed 分流和
错误映射，但不得创建分类目录、移动文件、重命名文件、删除文件、更新
`files` 或写入 `change_log`。category move confirmation 的 `Cancel` 和目标分类下拉预检必须使用此
类无副作用路径，不能用会写入的 `move_to_category` 代替 preview。

副作用边界：

- Copy / Move 等 repo-owned 文件返回确认后将使用的 repository-relative
  `target_path` 和 `target_name`；目标分类目录尚不存在时也只计算路径，不创建目录。
- 同名目标按 name-conflict resolution 安全编号策略解析，`name_conflict_resolved = true` 时 UI 必须
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

`move_to_category` 是 category move 的单文件改分类入口。输入是初始化后的
`repoPath`、active `fileId` 和目标分类 slug `newCategory`；输出是同一个
`file_id` 更新后的 `FileEntry`。`newCategory` 必须存在于
`.areamatrix/classifier.yaml` 或内置默认 classifier，否则抛 `Classify`，Core
不得隐式创建新分类。

副作用边界：

- Copy / Move 等 repo-owned 文件移动到目标分类目录，更新 `files.category`、
  `files.path`、`updated_at`，并写入 `change_log.action = moved`。
- 目标分类目录不存在时可创建该分类目录；同名目标按 name-conflict resolution 安全编号策略解析，
  不覆盖已有文件，编号耗尽或竞态无法解析时抛 `Conflict`。
- Indexed 文件只更新 `files.category`、`updated_at` 和 `change_log.moved`，
  保留 `files.path` / `files.source_path`，不移动、重命名或覆盖外部源文件。
- 成功改分类不改变 `file_id`、`original_name`、hash、storage mode、origin、
  source path、tags 或 notes；repo-owned 移动在目标同名时按安全编号解析，
  `current_name` 会同步为最终落位名（与 preview 的 `name_conflict_resolved` 一致）。

错误：

- `Classify`：目标分类不存在或 classifier 规则不可用。
- `FileNotFound`：`fileId` 对应的 active row 不存在，或 repo-owned 文件已消失。
- `Conflict`：目标同名安全路径无法解析，或伴生 note sidecar 的目标已被占用。
- `PermissionDenied`：文件系统移动或 metadata 写入被权限阻断。
- `Io`：文件系统读写失败。
- `Db`：SQLite 查询、更新或 change log 写入失败。sidecar 内容与 DB note 不一致时也归一为 Db。

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

按 `imported_at DESC` 排序。`limit > 1000` 自动 clamp。每个返回的
`FileEntry.availability_status` 会结构化标记 backing file 是否 `Missing`，供
mobile library surface 显示状态徽标和保留缺失文件行；该查询仍然只读，不触发 rescan、recovery
或 metadata 写入。

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

search query 的只读搜索入口，服务 `search results surface search-results`、`search sidebar surface search-empty`
和 `search empty state query-error`。输入包含原始 `query`、搜索范围、过滤条件、排序和分页。
输出 `SearchResultPage`：

- `query`：回显本次查询，便于 UI 在 debounce 与重试期间保持状态。
- `total_count`：分页前命中文件总数；为 `0` 且 diagnostics 没有 error 时进入搜索空态。
- `results`：每个 `SearchFileResult` 包含原有 `FileEntry`、相关性分数、命中字段和可高亮片段。
- `diagnostics`：结构化 query parse diagnostics，包含 `UnknownField`、`InvalidDate`、
  `UnclosedQuote`、`UnbalancedParentheses`、`InvalidOperator` 等，供 `search empty state`
  展示错误 token、位置和安全替换建议。
- `index_status`：`Ready`、`Indexing` 或 `Unavailable`，供搜索结果页和空态区分
  正常空结果、索引中、索引不可用。

搜索对象：

- 文件名、相对路径、伴生笔记、分类和 change log。
- 普通关键词支持大小写不敏感、fuzzy 和 pinyin initials 命中；高级查询字段不走模糊纠错。
- `SearchFilter` 必须携带当前搜索 UI 的 search facets 过滤状态，包括 tags 的
  Any/All 匹配模式和 storage mode。`search_files` 用同一份 filter 刷新真实结果，
  facet counts 仍由 search facets `list_filter_facets` 返回；保存搜索属于 saved searches，
  Smart List 执行属于 Smart List execution。

错误与副作用边界：

- `InvalidPath`：`repoPath` 或 `filter.current_path` 不合法或越过资料库边界。
- `Config`：query/filter/sort 配置无法解析或字段组合无效。
- `Db`：搜索索引、文件元数据、笔记或 change log 无法读取。
- 该 API 只读，不写 DB，不写 `change_log`，不创建或更新 FTS/索引表，不修改标签、分类、
  笔记、generated overview 或任何用户文件。
- OCR、文件内容全文、语义搜索和远程 AI 不属于当前普通搜索合同。

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

search facets 的只读 filter/facet 入口，服务 `search filters surface search-filters`、`tag filter`
和 `search results surface search-results` 中 search facets 负责的过滤器状态。输入 `SearchFacetQuery`
承载当前搜索文本、scope/current path、category、file kind、tags、Any/All tag match mode、
imported/modified date range、storage mode 和 include deleted。输出 `SearchFacets`：

- `query`：回显本次 facet 查询对应的搜索文本。
- `total_count`：当前 query + filters 下匹配的文件总数。
- `categories`：category facet counts，供 Category 行显示可选项、选中态和 disabled 状态。
- `file_kinds`：file kind / extension facet counts，供 Type 行显示可选项、选中态和 disabled 状态。
- `tags`：tag facet counts，供 tag filter surface 显示标签列表、已选态、文件数量和 count 加载失败后的重试恢复。
- `storage_modes`：Copied / Moved / Indexed 等 storage mode facet counts。
- `date_bounds`：当前查询下可用 imported/modified timestamp 边界，供自定义日期控件限制范围。
- `active_filter_count`：不含原始 query 文本的 active filters 数量，供 Filters 按钮、chips 和 VoiceOver 读出状态。

错误与副作用边界：

- `Config`：filter state 无效，例如 CurrentNode 缺少合法 current path、category 为空、
  file kind 非法、tag 为空、date range 反转或字段组合无法表达。
- `Db`：读取文件元数据、tag/facet 统计或必要搜索索引失败。
- 该 API 只读，不写 DB，不写 `change_log`，不创建、更新、删除或重命名标签。
- 该 API 不保存搜索、不创建或执行 Smart List，不实现 saved search CRUD 或
  Smart List execution。
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

saved searches 的保存搜索入口，服务 `saved search sheet`。输入 `CreateSavedSearchRequest`
包含名称、`SavedSearchQuery`、可选 icon/color 和 sidebar pin 状态。`SavedSearchQuery`
保存原始 query、完整 `SearchFilter`（含 scope/current path/tags/storage mode/include deleted）
和 `SearchSort`，因此保存成功后 `Smart Lists` 可以从返回记录恢复同一搜索条件。

输出 `SavedSearch`：

- `id`：稳定 saved search 标识，供 update/delete 和 sidebar selection 使用。
- `name`：用户可见 Smart List 名称。
- `query`：可复现搜索的 query/filter/sort/scope 状态。
- `icon` / `color`：用户选择的显示元数据；不得表达语义、AI 或多端能力依赖。
- `pinned`：sidebar 固定状态。
- `created_at` / `updated_at`：排序、恢复和编辑 UI 使用的时间戳。

错误与副作用边界：

- `Config`：repoPath 为空、名称为空、名称超过 64 字符、名称重复、query parser
  diagnostics、filter state 无效、icon/color 元数据无效。
- `Db`：读取或写入 `saved_searches` 元数据失败。
- 该 API 只写 saved search 元数据；不写 `change_log`，不移动、复制、删除、重命名、
  retag、reclassify、reindex 或修改任何文件。
- 0 结果的有效搜索可以保存；query 无效时必须返回结构化 `Config`，不能写入半成品。
- 该 API 不执行 Smart List、不返回 `SearchResultPage`、不实现 Smart List execution `run_smart_list`。
- 共享 Smart List、跨端同步、语义/AI Smart List 依赖不属于 saved searches 合同范围。

### `update_saved_search(repoPath, request) throws -> SavedSearch`

更新已有 saved search 元数据，服务 `Smart Lists` 的 Rename、Duplicate 后编辑、
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

删除一个 saved search 记录，服务 `Smart Lists` 的删除确认流程。

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

只读列出 saved search 元数据，服务 `Smart Lists` sidebar 分组、管理菜单、
空态/错误态、query 恢复提示和 command-palette 的 Smart List execution 发现前置数据。

排序：

- pinned first。
- pinned 内按 pin 时间或 updated_at 倒序。
- 非 pinned 按名称 A-Z。
- 当前 saved searches 合同不支持拖拽排序，也不暴露手动排序字段。

错误与副作用边界：

- `Config`：repoPath 为空。
- `Db`：saved search metadata 无法读取。
- 该 API 只读，不执行 Smart List，不计算结果数量，不返回 `SearchResultPage`。
- Smart List 打开执行属于 Smart List execution；调用方需要拿到 `SavedSearch.query` 后显式调用搜索执行入口。

### `run_smart_list(repoPath, savedSearchId, pagination) throws -> SearchResultPage`

```swift
let page = try AreaMatrix.runSmartList(
    repoPath: repoPath,
    savedSearchId: saved.id,
    pagination: SearchPagination(limit: 50, offset: 0)
)
```

Smart List execution 的 Smart List 执行入口，服务 `Smart Lists` 点击进入搜索模式，以及
`command palette` 打开已保存 Smart List 的导航命令。输入只包含
`savedSearchId` 和分页；Core 从 saved search 记录读取已保存的 query、完整
`SearchFilter` 和 `SearchSort`，再返回与 `search_files` 相同的 `SearchResultPage`：

- `query`：回显 Smart List 保存的查询文本，供搜索 banner 显示 `Smart List: name` 时同步展示。
- `total_count` 和 `results`：当前保存查询的分页结果；0 结果进入 Smart List 空态。
- `diagnostics`：保存的查询或过滤条件已经失效时的结构化诊断，供 UI 显示 warning dot、
  `Edit query...` 和恢复提示。
- `index_status`：让 Smart Lists surface 区分正常结果、索引中、索引不可用和 API 失败。

错误与副作用边界：

- `Config`：`repoPath` 为空、`savedSearchId <= 0`、pagination 无效，或已保存的
  filter/sort 状态无法表达。
- `FileNotFound`：`savedSearchId` 没有对应 saved search 记录。
- `Db`：读取 saved search metadata、搜索索引、文件元数据、笔记或 change log 失败。
- 该 API 只读，不创建、更新、重命名、复制、pin 或删除 saved search 记录；这些仍属于
  saved searches。
- 该 API 不写 `change_log`，不移动、删除、重命名、trash、retag、reclassify、reindex、
  duplicate 或修改任何文件，不更新 generated overview 或用户文件。
- Command palette 只能用该 API 打开已存在 Smart List 的结果页；命令索引、最近命令、
  危险命令确认和 command index 不属于本合同。
- 当前 Smart List 合同不注册超出普通搜索字段的 Smart List；智能推荐、语义搜索、OCR 和远程 AI
  不属于本合同范围。

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

command index 的命令索引入口，服务 `command palette`。输入包含 `repoPath` 和当前
selection context，其中 context 承载命令搜索文本、当前选中文件 ID、当前路径和是否返回
文件候选。输出 `CommandIndex` 提供可执行命令、导航目标、当前选择命令、最近命令、
Smart List 和文件候选：

- `commands`：普通命令行，例如 Import、Open repository、Settings、Help。
- `navigation_targets`：Settings、Smart Lists、Needs Review 等导航入口。
- `current_selection_targets`：Rename、Add tags、Change category、Delete 等依赖当前选择的入口。
- `recent_targets`：最近使用的命令或导航目标。
- `smart_lists`：已保存 Smart List 的命令面板目标；打开结果页仍由 Smart List execution
  `run_smart_list` 执行。
- `file_candidates`：可聚焦的文件候选；只在 context 要求时返回，不搜索文件内容。
- 每个 `CommandTarget` 必须携带 `group`、`kind`、`action`、可选 `route`、可选
  `shortcut`、禁用状态和 `requires_confirmation`，让 UI 能显示分组、VoiceOver 文案、
  快捷键和确认边界。

错误与副作用边界：

- `Db`：读取命令 registry metadata、saved-search metadata、recent-command metadata
  或文件候选 metadata 失败。
- 该 API 是只读索引，不执行 Smart List；打开 Smart List 结果仍调用 Smart List execution
  `run_smart_list`。
- 危险命令只返回跳转确认或预览页的目标，必须设置 `requires_confirmation`，不得在命令
  面板中直接执行。
- 该 API 不移动、删除、重命名、retag、reclassify、redo、解决导入冲突、应用分类规则、
  写 recent-command 历史、调用 AI/网络 provider、修改 generated overview 或任何用户文件。
- 该 API 不实现插件命令市场，不注册智能化、OCR、语义搜索或多端专属命令。

### `add_tag(repoPath, fileId, tag) throws -> TagSet`

```swift
let tags = try AreaMatrix.addTag(
    repoPath: repoPath,
    fileId: entry.id,
    tag: "clientA"
)
detailView.updateTags(tags.fileTags)
```

tag CRUD 的单文件标签添加入口，服务 `tag editor`。输入是已初始化
`repoPath`、active `fileId` 和用户输入或候选行提供的 `tag`。Core 负责对
tag 做 trim、大小写归一和非法字符校验；成功后返回 `TagSet`，让 UI 直接刷新
当前文件标签、候选列表、recent tags、已添加/禁用状态和更新时间。

输出 `TagSet`：

- `file_id`：本次操作对应的文件 ID。
- `file_tags`：当前文件添加后拥有的标签集合，按稳定顺序返回，供 Detail Meta
  chip 刷新。
- `available_tags`：仓库中可搜索/选择的 tag registry，包含 `file_count`、
  `selected`、`disabled` 和 `updated_at`，供 tag editor surface 候选列表和 tag filter surface 标签筛选入口使用。
- `recent_tags`：最近使用标签，供 tag editor surface 空输入状态显示。
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
- 批量加标签属于 batch tag mutation；Undo token/history 属于 undo action log；非 AI 标签建议属于
  deterministic tag suggestions；AI 自动标签不在本合同内。

### `remove_tag(repoPath, fileId, tag) throws -> TagSet`

```swift
let tags = try AreaMatrix.removeTag(
    repoPath: repoPath,
    fileId: entry.id,
    tag: "clientA"
)
detailView.updateTags(tags.fileTags)
```

tag CRUD 的单文件标签关系移除入口，服务 `tag editor` 中 chip 删除动作。
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

tag CRUD 的只读标签状态入口。`tag editor` 使用它加载当前文件 tag chips、
已有标签候选、最近使用标签、空态、加载失败和 Retry 状态。`tag filter`
可以复用 `available_tags` 作为 tag registry；标签计数和当前 search scope 下的
selected/disabled facet 状态仍由 search facets `list_filter_facets` 返回。

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

batch tag mutation 的批量加标签入口，服务 `batch add-tags`，并向 `undo toast`
提供可撤销操作状态。输入是已初始化 `repoPath`、多选得到的 `fileIds` 和用户确认
后的 `tags`。Core 复用 tag CRUD 的 tag trim、大小写归一、长度和非法字符校验；批量
页在 Apply 前应已完成本地校验，但 Core 必须再次校验，不能把非法 pending tag
静默跳过。

输出 `BatchMutationReport`：

- `requested_file_count`：合同接受的去重后文件数，供 batch add-tags surface 显示影响范围。
- `requested_tag_count`：合同接受的去重后标签数。
- `added_count`：本次新写入的 file/tag relation 数量。
- `skipped_count`：目标文件已经拥有对应 tag 的数量；这类行不得写重复 relation，
  也不得进入 Undo 反向操作。
- `failed_count`：失败的 file/tag relation 数量。
- `item_results`：逐 file/tag 结果，`status` 为 `Added`、`AlreadyHadTag` 或
  `Failed`，`error` 承载失败摘要，供 `View details`、Retry 和可访问性文本使用。
- `undo_token`：成功写入可撤销关系后返回给 undo toast/history；没有新增关系
  或实现无法创建 undo action 时为 `nil`。

错误与副作用边界：

- `FileNotFound`：`fileIds` 为空、包含 `<= 0`，或运行时发现目标 active file 不存在。
- `Db`：`repoPath` 的 tag metadata 不可用、tag 输入无法归一化、读取/写入 `tags`、
  写入 `change_log` 或写入 undo action 失败。
- 成功新增、重复跳过和失败项都必须在 `BatchMutationReport` 中可追踪；部分失败不得
  把失败项显示为成功。
- 重复 file id 和重复 tag 在写入前按稳定顺序去重；重复 tag relation 必须作为
  `AlreadyHadTag` 计入 `skipped_count`，不得写入重复行。
- 成功新增的关系写入 `change_log` 并进入 undo action log；原本已有的标签关系
  不进入 Undo 反向操作。Undo 执行本身属于 undo action log。
- 该 API 只写标签 metadata、change log 和 undo action；不移动、不重命名、不删除、
  不 Trash、不改分类、不写 note、不保存搜索、不 reindex、不更新 generated overview、
  不触发 AI/网络，也不触碰任何用户文件内容或路径。
- 批量 AI 标签建议、批量改分类、批量删除、批量重命名、Undo/Redo 执行、
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

deterministic tag suggestions 的非 AI 标签建议入口，服务 `tag suggestions`。输入是已初始化
`repoPath`、目标 active `file_id`、可选来源上下文和建议数量上限。Core 只能基于
文件名、仓库相对路径、来源目录关键词和已有标签词库生成确定性建议；不得读取文件正文、
不得调用 AI 或远程 provider、不得发生网络访问。该入口只读，不写 tag metadata。

输出 `TagSuggestionReport`：

- `file_id`：本次建议对应的文件 ID。
- `suggestions`：建议行集合，包含 `suggestion_id`、`slug`、`display_name`、
  `reason`、`source`、`match_strength`、`already_exists`、`needs_create`、`status`、
  `selected_by_default` 和 `disabled_reason`，供 tag suggestions surface 展示候选、理由、Strong/Weak、
  New tag、Already added、Invalid 和 Blocked 状态。
- `tag_set`：当前文件标签与仓库 tag registry 快照，供页面避免重复添加并在空态回到
  tag editor surface 手动标签入口。
- `contents_read` / `ai_used` / `network_used`：隐私边界标记，该非 AI 建议合同必须全部为
  `false`，页面据此显示“非 AI、非内容读取”的说明。

错误与副作用边界：

- `FileNotFound`：`file_id <= 0`，或没有对应 active file row。
- `Validation`：`limit` 不在 `1..=50`，来源上下文为空白、超长、含 NUL 或看起来像
  URL/远程来源。
- `Conflict`：文件 metadata、既有标签或来源上下文无法形成确定性建议状态。
- `Db`：读取 active file、tag registry 或 tag relation 失败。
- 该 API 只读，不创建、更新、移除、重命名或采纳标签，不写 `change_log` 或
  `undo_actions`，不改变搜索筛选，不移动、删除、重命名、读取或上传任何用户文件。
- AI 标签建议、语义理解、OCR/正文读取和远程 provider 属于 AI tag suggestions，
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

deterministic tag suggestions 的建议采纳入口，服务 `tag suggestions` 的 `Apply selected` 与
`Apply edited`。输入是同一个 active `file_id` 和用户明确选中或编辑后的建议行。
Core 创建或复用规范化后的 tag，写入当前文件 tag relation，记录 change log，并在
至少新增一个关系时返回 undo action log token。未选、Ignore、Cancel edit 或 Already added
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
- `undo_token`：新增关系进入 undo action log stack 后的 token；没有新增关系时为 `nil`。
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
- tag CRUD 仍负责手动 add/remove/list tag；undo action log 负责执行 undo；本合同不新增
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

batch category change 的只读批量改分类预览入口，服务 `batch change-category surface batch-change-category`。输入是已初始化
`repoPath`、多选得到的 `fileIds`、目标分类 slug `targetCategory`，以及是否把
repo-owned 文件移动到目标分类目录的 `moveRepoOwnedFiles`。目标分类必须已经存在于
classifier 规则或默认分类中；本 API 不创建新分类，`Create new category...` 仍属于
`classifier rule editor surface classifier-rule-editor` / classifier rule editor。

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
- `FileNotFound`：`fileIds` 为空、包含非法 id，或运行时发现必须阻断的 active row 缺失。
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

batch category change 的批量改分类执行入口，服务 `batch change-category surface batch-change-category` 的 Apply，并向
`undo toast` / undo action log 提供可撤销操作状态。输入必须绑定最近一次有效
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
  undo action log。
- `moveRepoOwnedFiles = false` 或 Indexed 文件只更新 `files.category/updated_at` 与
  change log，不移动、重命名或覆盖源文件。
- 成功改分类不改变 `file_id`、`original_name`、hash、storage mode、origin、source path、
  tags 或 notes；note sidecar 只有在对应 repo-owned 文件移动时跟随文件安全移动。
- 部分失败必须在 `item_results` 中可追踪。失败项不得显示为成功；成功项可以保留并进入
  undo action，Undo 执行仍属于 undo action log。
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

- batch change-category surface 可以从 preview 合同得到选中文件数、当前分类分布、目标分类、移动选项、影响数量、
  每行状态、Apply 是否可用和禁用原因。
- batch change-category surface 可以从执行报告得到成功/失败/跳过摘要、刷新用 `updated_files`、失败详情和
  `undo_token`。
- undo toast surface / undo action log 只消费 `undo_token` 和 `list_undo_actions` / `undo_action` 状态；
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

batch delete 的只读批量删除预览入口，服务 `batch delete confirmation`。输入是已初始化
`repoPath`、多选得到的 `fileIds` 和 `deleteMode`。当前批量删除合同只允许两种模式：

- `MoveToTrash`：计划把 AreaMatrix repo-owned 的 `Copied` / `Moved` 文件移到系统 Trash。
- `RemoveFromIndex`：计划只移除 Indexed / Adopted / External 或 Missing metadata 记录。

输出 `BatchDeletePreviewReport`：

- `requested_file_count`：去重后的选中文件数，供 sheet 标题和影响摘要使用。
- `delete_mode`：回显本次预览模式，避免 UI 混淆 Trash 删除和 index-only 移除。
- `preview_token`：绑定本次选择集、模式、Trash 可用性和已检查文件状态的确认令牌；执行
  API 必须带回该值。
- `trash_available`：Core 对当前 repo-owned 删除请求执行安全复核后的 Trash 可用状态；Swift 仍须先做
  宿主 availability probe。任一侧为 `false` 时 UI 必须禁用 `Move to Trash`，不得提供永久删除替代。
- `undo_available`：本次可处理项是否能创建 undo action log；为 `false` 时 batch delete confirmation
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

- 只读检查 DB、文件状态、操作级 Trash 前置条件和权限；Swift 的宿主 availability probe 只用于 UI
  gate，不能替代 Core 执行前复核。
- 不移动文件到 Trash，不移除 index row，不写 `files`、`change_log`、`undo_actions`、
  notes、tags、saved searches、generated overview 或任何用户文件。
- 不提供永久删除，不清空 Trash，不删除外部源文件，不触发 iCloud placeholder 下载。
- 预览必须覆盖每个去重后的 file id；不可处理项必须显示为 `Skipped` 或 `Blocked`，
  不得静默消失或当作成功项。

错误：

- `FileNotFound`：`fileIds` 为空、包含非法 id，或运行时发现必须阻断的 active row 缺失。
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

batch delete 的批量删除执行入口，服务 `batch delete confirmation` 的
`Move to Trash` / `Remove from index`，并向 `undo toast` / undo action log 提供可撤销操作状态。
输入必须带回用户刚确认的 `preview_token`，并与 preview 状态一致；如果选择集、模式、
Trash 可用性或 inspected state 变化，Core 必须拒绝不安全写入并让 UI 重新 Preview。
Swift 负责 availability probe、危险确认和报告呈现；不得在调用前后自行执行 Trash mutation、
DB/change log 写入或 Undo 拼装。

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
  并进入 undo action log。
- `MoveToTrash` 如果已经移动文件和软删除 metadata，但批量 undo action 写入失败，Core
  必须把已处理项从 Trash 恢复到原 repo 路径并回滚对应 `files` / `change_log` 变更，
  然后返回 `Db` 或回滚失败对应的 `Io` / `Db` 错误；不得留下无 undo token 的已删除状态。
- `RemoveFromIndex` 只能处理 Indexed / Adopted / External 或 Missing metadata。成功时
  只更新 metadata，使该条目不再出现在默认 list/detail 中，并写
  `change_log.action = removed_from_index`；不得移动、删除、重命名、覆盖或 Trash 外部源文件。
- 部分失败必须在 `item_results` 中可追踪。失败项不得显示为成功；成功项可以保留并进入
  undo action，Undo 执行仍属于 undo action log。
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

- batch delete confirmation 可以从 preview 合同得到选中文件数、Trash 可用性、Undo 可用性、将进入 Trash /
  仅移除索引 / missing / skipped / blocked 数量、每行状态、Apply 是否可用和禁用原因。
- batch delete confirmation 可以从执行报告得到成功/失败/跳过摘要、刷新用 `affected_file_ids`、失败详情和
  `undo_token`。
- undo toast surface / undo action log 只消费 `undo_token` 和 `list_undo_actions` / `undo_action` 状态；
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

batch rename 的只读批量重命名预览入口，服务 `batch rename surface`。输入是已初始化
`repoPath`、按当前 List 排序的 `fileIds` 和 `BatchRenameRule`。`fileIds` 顺序是合同的一部分：
`KeepBaseSequence` 必须按该顺序稳定生成序号，用户改变排序、选择集或规则后旧
`preview_token` 失效。

`BatchRenameRule` 支持四种批量重命名策略：

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
- `FileNotFound`：`fileIds` 为空、包含非法 id，或运行时发现必须阻断的 active row 缺失。
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

batch rename 的批量重命名执行入口，服务 `batch rename surface` 的 Apply，并向
`undo toast` / undo action log 提供可撤销操作状态。输入必须带回最近一次有效
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
  `files.path/current_name/updated_at`，写 `change_log.action = renamed`，并进入 undo action log。
- Indexed 文件只更新 `files.current_name/updated_at` 与 change log，不移动、重命名、覆盖或 Trash
  外部源文件。
- 成功批量 rename 不改变 `file_id`、category、tags、notes、hash、storage mode、origin、
  source path 或文件扩展名。
- 部分失败必须在 `item_results` 中可追踪。失败项不得显示为成功；成功项可以保留并进入
  undo action，Undo 执行仍属于 undo action log。
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

- batch rename surface 可以从 preview 合同得到选中文件数、规则回显、逐行 original/new 名称、冲突详情、
  index-only display-name 行、unchanged 行、阻塞原因、Apply 是否可用和禁用原因。
- batch rename surface 可以从执行报告得到成功/失败/跳过摘要、刷新用 `updated_files`、失败详情和
  `undo_token`。
- undo toast surface / undo action log 只消费 `undo_token` 和 `list_undo_actions` / `undo_action` 状态；
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

classifier correction 的分类纠错入口，服务 `classifier correction surface classifier-correct` 的 `Apply correction`。
输入是初始化后的 `repoPath`、active `fileId`、目标分类 slug、是否移动 repo-managed
文件的 `moveFile`，以及是否需要规则草稿 handoff 的 `remember`。`category` 必须已存在于
classifier 规则或默认分类中；本 API 不创建新分类。

输出 `ClassifierCorrectionResult`：

- `updated_file`：纠错后最新 `FileEntry`，供 List/Detail/Tree 刷新。
- `rule_draft`：当 `remember = true` 且 Core 能生成安全候选时返回，供 classifier save-rule surface/classifier impact preview surface 继续确认。
  classifier correction 不保存该草稿。
- `move_file_requested`：回显本次是否请求移动 repo-managed 文件。
- `remember_requested`：回显本次是否请求未来规则 handoff。
- `rule_confirmation_required`：当存在规则草稿或用户请求记住规则时为 true，提醒 UI 必须进入
  classifier save-rule surface/classifier impact preview surface 确认后才能保存规则。

副作用边界：

- 对 repo-managed `Copied` / `Moved` 文件，`moveFile = true` 时可执行安全移动，更新
  `files.category/path/updated_at` 并写 `change_log.action = moved` 或等价纠错记录；同名目标不得覆盖。
- `moveFile = false`、Indexed、adopted、missing 或不可写状态只能更新分类 metadata 和
  change log，不移动、重命名或覆盖外部源文件。
- `remember = true` 只返回 `ClassifierRuleDraft`，不得写入 `.areamatrix/classifier.yaml`、
  不保存 classifier rule、不预览大面积影响、不应用到历史文件。
- 不创建新分类，不实现 classifier rule save、classifier impact preview、classifier rule editor，不调用
  AI/network providers。

错误：

- `Classify`：目标分类不存在、为空、格式非法或 classifier 规则不可用。
- `Conflict`：安全目标路径无法解析或存在不可覆盖同名目标。
- `Io`：文件移动、路径检查或权限读取失败。
- `Db`：SQLite 查询、`files` 更新或 change log 写入失败。

页面消费状态：

- classifier correction surface 可以从合同得到更新后的文件、是否执行了 move preference、是否请求 Remember、是否仍需
  规则确认，以及可传给 classifier save-rule surface/classifier impact preview surface 的规则草稿。
- classifier correction surface 不能从本合同直接保存规则、创建分类、预览历史影响或应用批量重分类；这些能力分别属于
  classifier rule save、classifier rule editor、classifier impact preview 和批量重分类能力。本合同不新增 control map 之外的页面能力。

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

classifier rule save 的分类规则保存入口，服务 `classifier save-rule surface classifier-save-rule` 的 `Save rule`。
输入是已初始化 `repoPath` 和一个 `ClassifierRule`。`target_category` 必须是已存在的
classifier category slug；`keywords` 和 `extensions` 是追加到目标分类的独立匹配值，
不是 keyword AND extension 复合规则；`extensions` 必须是不带点的小写值；`priority`
范围是 `-1000..=1000`；`preview_confirmed` 表示 UI 已经完成必需的影响预览确认。

输出 `ClassifierRule`：

- `target_category`：最终写入的目标分类 slug。
- `keywords`：保存后的关键词匹配值，供 classifier save-rule surface 显示成功后的规则摘要。
- `extensions`：保存后的扩展名匹配值，不带点且小写。
- `priority`：保存后的目标分类优先级。
- `preview_confirmed`：回显本次保存是否已经由 classifier save-rule surface/classifier impact preview surface 完成必要预览确认。

副作用边界：

- 只允许原子更新 classifier 配置：`.areamatrix/classifier.yaml` 或等价 classifier metadata。
- 保存规则只影响未来分类；不得重分类、移动、重命名、删除、Trash、导入、reindex、
  写 notes、tags、saved searches、generated overview 或任何用户文件。
- 不创建新分类，不写 `path`、`source_folder`、独立 rule `enabled` 字段或 compound AND 规则。
- 不实现 classifier impact preview、classifier rule editor CRUD、AI 自动生成规则或批量应用历史文件。

错误：

- `Config`：`repoPath`、目标分类、关键词、扩展名、priority、classifier schema
  无效，规则重复，或过宽规则尚未完成必要预览确认。
- `PermissionDenied`：classifier metadata 或 `.areamatrix/classifier.yaml` 写入被权限阻断。
- `Io`：读取、备份、原子写入或恢复 classifier 配置失败。

页面消费状态：

- classifier save-rule surface 可以从合同得到保存后的目标分类、独立关键词、独立扩展名和 priority，用于成功摘要、
  toast、表单恢复和 rule-store 刷新。
- classifier save-rule surface/classifier impact preview surface 可以用 `preview_confirmed = true` 表达用户已完成必需预览后的
  `Save rule only` 回流；Core 只保存规则配置，不计算影响量、不批量应用历史文件。
- classifier save-rule surface 不能从本合同得到历史影响量、批量应用结果或规则列表编辑状态；这些分别属于
  classifier impact preview、独立 apply 行为和 classifier rule editor。本合同不新增 control map 之外的页面能力。

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

classifier impact preview 的分类规则影响预览入口，服务 `classifier impact preview surface classifier-impact-preview` 的
`Preview rule impact` dry-run。输入是已初始化 `repoPath` 和
`ClassifierImpactPreviewRequest`。`request.mode` 支持 `RuleDraft`、`RemoveKeyword`、
`RemoveExtension` 和 `RemoveCategory`，用于规则草稿、删除 keyword、删除 extension
或删除 category 前的同一只读影响预览。`request.rule` 承载目标分类和规则 basis；
`target_category`、`keywords`、`extensions`、`priority` 的校验语义与
`save_classifier_rule` 保持一致；`keywords` 和 `extensions` 是独立 matcher basis，
不是 keyword AND extension 复合规则。`move_files` 表示是否按 classifier impact preview surface 的
`Move files to new category folders` 选择执行路径冲突 dry-run；关闭时只预览分类
metadata 变化，不因目标路径同名文件阻断。`replacement_category` 只在
`RemoveCategory` 模式下有效。

输出 `RuleImpactReport`：

- `request`：回显本次预览请求，供规则摘要、删除摘要和 Back 恢复。
- `move_files`：通过 `request` 回显 Move checkbox 状态，供 classifier impact preview surface 在关闭 Move 后
  重新 dry-run 并恢复 UI 状态。
- `affected_file_count`：现有文件中命中该草稿的总数。
- `will_update_count`：命中且当前分类会改变的文件数量。
- `already_correct_count`：命中但已经属于目标分类的文件数量。
- `needs_review_count`：命中但需要人工确认、不能直接批量应用的文件数量。
- `conflict_count`：路径冲突、缺失文件或规则冲突数量。
- `sample_limit`：本响应最多携带多少样例行。
- `samples`：classifier impact preview surface 表格样例，包含文件 id、路径、当前分类、新分类、命中原因、
  `WillUpdate` / `AlreadyCorrect` / `NeedsReview` / `Conflict` / `Missing` /
  `IndexOnly` 状态和可选原因。
- `conflicts`：结构化冲突列表，供禁用原因和 VoiceOver 文案使用。
- `needs_review`：是否存在 review-only 行。
- `warning_required` / `warning`：影响量超过阈值时显示过宽规则 warning。
- `can_apply` / `apply_blocked_reason`：对应 apply 能力是否可直接执行，以及禁用原因。
  删除 category 且没有 `replacement_category` 时必须返回 `can_apply = false`，并给出
  replacement 缺失的禁用原因。

副作用边界：

- 只读读取 classifier 配置和文件 metadata；RuleDraft 必须按当前
  `classifier.yaml` matcher 语义叠加草稿后重新计算新分类，DB 查询和
  move dry-run 的冲突检测语义只在 `move_files = true` 时参与 Apply 禁用判断。
- 删除 keyword、extension 或 category 的预览只计算现有 metadata 会如何变化；
  不修改 `classifier.yaml`，也不得移动、删除或重命名历史文件。
- 不得保存规则、重分类、移动、重命名、删除、Trash、导入、reindex、写 notes、
  tags、saved searches、generated overview、change_log、undo_actions 或任何用户文件。
- 不实现 classifier rule save、classifier rule editor CRUD、独立 apply 行为、AI 自动生成规则、
  后台持续规则评估或跨端同步。

错误：

- `Config`：`repoPath`、目标分类、关键词、扩展名、priority、replacement category、
  delete preview request 或 classifier schema 无效。
- `Db`：classifier impact 所需文件 metadata、分类 metadata、冲突检测 metadata 或
  preview 查询不可读取。

页面消费状态：

- classifier impact preview surface 可以从合同得到规则摘要、影响总量、will update / already correct /
  needs review / conflict 计数、样例表格、Index-only / Missing / Name conflict 状态、
  Move on/off 的冲突差异、过宽 warning、Apply 是否可用、禁用原因、删除匹配值影响
  和删除 category replacement 缺失状态。
- classifier impact preview surface 不能从本合同保存规则、应用到现有文件、写 Undo stack、编辑规则列表或创建新分类；
  这些分别属于 classifier rule save、独立 apply 行为、undo action log、classifier rule editor 和 classifier editor 流程。
  本合同不新增 control map 之外的页面能力。

### `list_classifier_rules(repoPath, editingLocale) throws -> ClassifierRuleEditorSnapshot`

```swift
let snapshot = try AreaMatrix.listClassifierRules(
    repoPath: repoPath,
    editingLocale: frozenEditingLocale
)
ruleEditor.load(snapshot.rules, defaultRuleId: snapshot.defaultRuleId)
```

classifier rule editor 的分类规则编辑器入口，服务 `classifier rule editor surface classifier-rule-editor` 的初始加载、
YAML reload 后刷新、保存成功后刷新和 Revert。`editingLocale` 是 UI 打开可编辑 draft 时冻结的 concrete
`zh-Hans` / `en`；只读浏览或 unknown repository policy 时传 `nil`。Core 不自行解析 `system`。

输出 `ClassifierRuleEditorSnapshot`：

- `rules`：当前 classifier category 列表。每个 `ClassifierRuleRecord` 包含
  `rule_id`、`slug`、完整 `display_names` / `descriptions` locale map、`extensions`、`keywords`、
  `priority`、`naming_template` 和 `is_default`，对应 classifier rule editor surface 左侧分类列表和右侧详情。
- `default_rule_id`：当前默认分类，用于禁用删除默认分类和读出 default 状态。
- `updated_rule_id`：最近一次 update/delete 后可重新选中的行；纯列表加载时为 `nil`。
- `repository_locale_policy`：DB 中 exact raw policy，包括兼容 alias 或 unknown value；读取不规范化写回。
- `editing_locale`：回显调用方冻结的 concrete locale；unknown policy 或只读模式为 `nil`。
- `health`：`Valid`、`Missing`、`Unreadable` 或 `Invalid`。后三种状态返回 degraded read-only
  snapshot，不把 embedded defaults 伪装成当前配置；`editing_locale` 必须为 `nil`。
- `recovery_actions`：Core 根据当前文件证据返回的安全动作。`Missing` 只返回 `CreateDefault`；
  readable `Invalid` 返回 `RestoreDefault`，并且仅在存在可验证的 last-valid backup 时追加
  `RestoreLastValid`；`Unreadable` 不返回写动作，用户必须先恢复读取权限。
- `warning`：读取成功但需要用户注意的 classifier 状态，例如外部 YAML reload 后仍需
  Validate，或 repository policy unsupported。已知显式/alias policy 显示值按 exact raw locale、调用方 concrete
  locale、`en`、slug 回退；follow-interface 从 concrete locale 开始；unknown policy 按 exact raw、`en`、slug
  回退。

副作用边界：

- 只读取 `.areamatrix/classifier.yaml` 或等价 classifier metadata。
- 不校验 UI 草稿、不保存规则、不删除分类、不预览影响、不移动、删除、重命名或重分类
  历史文件。
- 不写 `files`、`change_log`、`undo_actions`、notes、tags、saved searches、
  generated overview，也不打开 YAML、不调用 AI/network providers。
- unknown repository policy 仍允许本 API 返回完整 map 与 fallback snapshot；这不授权任何 mutation。

错误：

- `Config`：`repoPath` 为空、位于 `.areamatrix/` 内部或资料库未初始化。classifier 内容缺失、
  不可读或无效通过 degraded snapshot 表达，不作为页面级 throw。
- `PermissionDenied` / `Io`：仅用于无法安全检查资料库元数据边界、路径类型或 recovery evidence
  的失败；普通 classifier 文件不可读通过 `Unreadable` health 表达。

页面消费状态：

- classifier rule editor surface 可以从合同得到分类列表、dirty/revert 的 last-valid 基线、字段初值、
  default category 删除禁用状态、空态、加载失败和 reload 后刷新状态。
- classifier rule editor surface 不能从本合同得到历史影响量、批量应用结果、Open YAML 的平台动作或 AI 规则建议；
  这些分别属于 classifier impact preview、独立 apply 行为、平台层和 AI 规则能力。本合同不新增 control map
  之外的页面能力。

### classifier recovery

```swift
let created = try AreaMatrix.createDefaultClassifier(
    repoPath: repoPath,
    confirmed: true,
    editingLocale: frozenEditingLocale
)
let restored = try AreaMatrix.restoreDefaultClassifier(
    repoPath: repoPath,
    confirmed: true,
    editingLocale: frozenEditingLocale
)
let lastValid = try AreaMatrix.restoreLastValidClassifier(
    repoPath: repoPath,
    confirmed: true,
    editingLocale: frozenEditingLocale
)
```

### `create_default_classifier(repoPath, confirmed, editingLocale) throws -> ClassifierRuleEditorSnapshot`

仅在 classifier 文件缺失且用户明确确认时创建默认配置。

### `restore_default_classifier(repoPath, confirmed, editingLocale) throws -> ClassifierRuleEditorSnapshot`

仅在当前 classifier 可读但无效且用户明确确认时，从默认配置执行受保护恢复。

### `restore_last_valid_classifier(repoPath, confirmed, editingLocale) throws -> ClassifierRuleEditorSnapshot`

仅在存在可验证的 last-valid backup 且用户明确确认时恢复该备份。

三个入口只恢复 `.areamatrix/classifier.yaml`，并返回新的 `ClassifierRuleEditorSnapshot`：

- `create_default_classifier` 仅在文件确实 `Missing` 且用户已确认时创建内置默认配置；如果文件在
  preflight 后出现，必须 fail closed，不能覆盖。
- `restore_default_classifier` 仅在当前文件可读但 `Invalid` 且用户已确认时执行。替换前必须把当前原始
  bytes 写入 `.areamatrix/archives/classifier/` 的编号、非覆盖 backup。
- `restore_last_valid_classifier` 仅在当前文件可读但 `Invalid`、用户已确认且存在可完整解析并通过校验的
  last-valid backup 时执行。当前 invalid bytes 同样先备份；候选 backup 在 commit 前必须再次验证。
- `Unreadable` 不允许任何恢复写入；Core 不通过覆盖文件来绕过权限、非 regular file 或 symlink 问题。
- 正常 create/update/delete 在替换有效 classifier 前也保存编号、非覆盖 last-valid backup。backup 创建、
  temp 写入、文件 fsync、atomic rename 与 parent-directory fsync 任一步失败时，旧活动文件保持不变；已安全
  写成的 backup 可以保留，不自动删除。
- 所有入口拒绝 symlink 和 non-regular classifier/backup 路径，不移动、删除、重命名或重新分类用户文件，
  不写 DB、概述、AI 内容或 `README.md`。

`confirmed = false`、health/action 不匹配、backup 不存在或 backup 无效返回 `Config`；权限失败返回
`PermissionDenied`，安全写入或同步失败返回 `Io`。这些入口不接受 force overwrite，也不把 embedded
defaults 当作浏览或分类时的静默 fallback。

### `create_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`

```swift
guard let editingLocale = snapshot.editingLocale else {
    throw ClassifierEditorError.readOnlyLocale
}
let snapshot = try AreaMatrix.createClassifierRule(
    repoPath: repoPath,
    request: ClassifierRuleCreateRequest(
        repositoryLocalePolicy: snapshot.repositoryLocalePolicy,
        editingLocale: editingLocale,
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

classifier rule editor 的新建分类入口，服务 classifier rule editor surface 的 `New category` 后 Validate + Save。输入是
已初始化 `repoPath` 和一个 `ClassifierRuleCreateRequest`。`slug` 是写回 classifier
的分类 slug；扩展名必须是不带点的小写值；`priority` 范围为 `-1000..=1000`；
`naming_template` 只允许当前 `classifier.yaml` 支持的模板字段。新建分类不会自动影响
历史文件，因此不要求 impact preview confirmation。

`repository_locale_policy` 必须逐字回传 snapshot 的 exact raw policy，`editing_locale` 必须逐字回传
冻结的 concrete locale。`display_name` / `description` 只创建该 locale 的 map entry；custom category 允许
sparse map，不自动生成 `en` 或其他翻译。Core 写入前重读 repository policy；发生变化时返回 `Conflict`。
unknown policy 下本 API 必须返回 `Config`，即使字段本身有效。

输出为新建后的 `ClassifierRuleEditorSnapshot`，让 classifier rule editor surface 刷新分类列表、选中新建行、
Save 成功后的 last-valid 基线、dirty 状态和 warning。

副作用边界：

- 只允许原子更新 classifier 配置：`.areamatrix/classifier.yaml` 或等价 classifier metadata。
- 新建分类只影响未来分类；不会自动移动、删除、重命名或重分类历史文件。
- 写入失败时旧 classifier 配置必须保持为活动版本；实现需要能恢复未完成写入或备份。
- 不写 `files`、`change_log`、`undo_actions`、notes、tags、saved searches、
  generated overview，不执行 classifier rule save `save_classifier_rule`、classifier impact preview、
  Trash、reindex、AI/network provider 或 Open YAML 平台动作。
- 不实现复杂脚本规则、插件规则、`path`、`source_folder` 或独立 rule `enabled` 字段。

错误：

- `Config`：`repoPath`、slug、display name、description、extensions、keywords、
  priority、naming template、重复 slug、重复 matcher value、unknown repository policy 或 classifier schema 无效。
- `Conflict`：读取 snapshot 后 repository policy 已改变，旧 draft 不得覆盖新语言上下文。
- `PermissionDenied`：classifier metadata 或 `.areamatrix/classifier.yaml` 写入被权限阻断。
- `Io`：读取、备份、原子写入或恢复 classifier 配置失败。

页面消费状态：

- classifier rule editor surface 可以从合同得到新建后的列表快照、当前选中行、Save 成功后的 last-valid 基线、
  字段错误对应的 `Config` 状态和写入失败恢复路径。
- classifier rule editor surface 不能从本合同得到历史影响量、批量应用结果、Undo token、文件刷新列表或 YAML 高级
  编辑器动作。本合同不新增 control map 之外的页面能力。

### `update_classifier_rule(repoPath, request) throws -> ClassifierRuleEditorSnapshot`

```swift
guard let editingLocale = snapshot.editingLocale else {
    throw ClassifierEditorError.readOnlyLocale
}
let snapshot = try AreaMatrix.updateClassifierRule(
    repoPath: repoPath,
    request: ClassifierRuleUpdate(
        repositoryLocalePolicy: snapshot.repositoryLocalePolicy,
        editingLocale: editingLocale,
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

classifier rule editor 的编辑保存入口，服务 classifier rule editor surface 的 Validate 后 Save。输入是已初始化
`repoPath` 和一个 `ClassifierRuleUpdate`。`rule_id` 是稳定目标行，`slug` 是写回
classifier 的分类 slug；扩展名必须是不带点的小写值；`priority` 范围为
`-1000..=1000`；`naming_template` 只允许当前 `classifier.yaml` 支持的模板字段。
`preview_confirmed` 表示删除/大范围变更前 UI 已经完成影响预览或等价摘要确认。

`observed` 是打开该 draft 时冻结的目标规则基线，包含稳定 `rule_id`、slug、当前 `editing_locale` 对应的
display name/description，以及 matcher、priority 和 naming template。Core 在读取最新 YAML 后只比较这些
受影响字段；任一字段变化都返回 `Conflict(classifier_rule_observed_state)` 且零写入。其他 locale map 不参与
比较，也不被本次保存覆盖。

`repository_locale_policy` 和 `editing_locale` 构成 locale compare-and-swap（比较并交换）观察值。保存只
patch `editing_locale` 对应的 `display_name` / `description` entry，保留其他 locale 原值；空值按字段规则
删除该 entry，不自动翻译或语义合并。policy 变化返回 `Conflict`；unknown policy 返回 `Config`。

输出仍为 `ClassifierRuleEditorSnapshot`，让 classifier rule editor surface 在保存成功后用同一份已持久化快照
刷新分类列表、详情字段、default 状态、dirty 状态、warning 和 last-valid 基线。

副作用边界：

- 只允许原子更新 classifier 配置：`.areamatrix/classifier.yaml` 或等价 classifier metadata。
- 保存只影响未来分类；删除匹配值或修改分类配置不会自动移动、删除、重命名或重分类历史文件。
- 写入失败时旧 classifier 配置必须保持为活动版本；实现需要能恢复未完成写入或备份。
- 不写 `files`、`change_log`、`undo_actions`、notes、tags、saved searches、
  generated overview，不执行 classifier rule save `save_classifier_rule` 的单规则草稿保存、不执行 classifier impact preview
  impact preview、不调用 AI/network providers。
- 不实现 classifier rule save、classifier impact preview、复杂脚本规则、插件规则或 AI 规则生成。
- 不实现复杂脚本规则、插件规则、`path`、`source_folder` 或独立 rule `enabled` 字段。

错误：

- `Config`：`repoPath`、`rule_id`、slug、display name、description、extensions、
  keywords、priority、naming template、default category、重复 slug、重复 matcher、
  preview confirmation、unknown repository policy 或 classifier schema 无效。
- `Conflict(repository_locale_policy)`：读取 snapshot 后 repository policy 已改变。
- `Conflict(classifier_rule_observed_state)`：目标规则的当前编辑语言或受影响规则字段已在其他窗口或外部编辑中
  改变。Swift 必须显式加载最新 snapshot，保留完整本地 draft 和冻结的 `editing_locale`，由用户 Reload 或
  Review；Review 只更新基线，仍需再次明确 Save。
- `PermissionDenied`：classifier metadata 或 `.areamatrix/classifier.yaml` 写入被权限阻断。
- `Io`：读取、备份、原子写入或恢复 classifier 配置失败。

页面消费状态：

- classifier rule editor surface 可以从合同得到保存后的列表快照、当前选中行、Save 成功后的 last-valid 基线、
  仍需展示的 warning、字段错误对应的 `Config` 状态和写入失败恢复路径。
- classifier rule editor surface 不能从本合同得到历史影响量、批量应用结果、Undo token、文件刷新列表或 YAML 高级
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

classifier rule editor 的分类规则删除入口，服务 classifier rule editor surface 的 Delete category 和删除已存在 rule row 的
确认流程。输入是已初始化 `repoPath` 和一个 `ClassifierRuleDeleteRequest`。
`rule_id` 指向要删除的 classifier category；`replacement_category` 是删除分类前影响预览
使用的回退分类；`preview_confirmed` 表示 UI 已展示影响摘要或完成 classifier impact preview surface 影响预览。

删除不需要选择 `editing_locale`，但 Core 仍必须重读当前 repository policy；unknown policy 时返回
`Config`，不得以“删除不生成文本”为由绕过全 mutation gate。调用方必须先在 Repository 设置中明确
保存 supported policy，再重新加载 snapshot 和影响预览。

输出为删除后的 `ClassifierRuleEditorSnapshot`，让 classifier rule editor surface 刷新分类列表、选中回退行、
default 状态、dirty 状态和 warning。

副作用边界：

- 只允许原子更新 classifier 配置，删除对应 classifier category 或 rule row。
- 删除规则不自动移动、删除、重命名或重分类历史文件；是否更新现有文件分类只能通过独立
  impact/apply 能力执行。
- 必须拒绝删除默认分类、最后一个分类、缺失 replacement 的分类删除、未完成影响确认的删除。
- 不写 `files`、`change_log`、`undo_actions`、notes、tags、saved searches、
  generated overview，不执行 Trash、reindex、AI/network provider 或 Open YAML 平台动作。

错误：

- `Config`：`repoPath`、`rule_id`、replacement category、preview confirmation、默认分类保护、
  最后分类保护、unknown repository policy 或 classifier schema 无效。
- `PermissionDenied`：classifier metadata 或 `.areamatrix/classifier.yaml` 写入被权限阻断。
- `Io`：读取、备份、原子写入或恢复 classifier 配置失败。

页面消费状态：

- classifier rule editor surface 可以从合同得到删除后的列表、下一条可选行、默认分类保护、删除禁用原因对应错误、
  Save/Revert 基线和写入失败恢复状态。
- classifier rule editor surface 不能从本合同得到历史文件更新、Undo action、Trash 删除、AI 建议或插件规则状态。
  本合同不新增 control map 之外的页面能力。

文件级撤销与重做只通过 `list_undo_actions`、`undo_action`、`list_redo_actions`
和 `redo_action` 合同提供。系统废纸篓中的独立恢复接口未纳入 Core 公共 API；调用方
不得把系统废纸篓状态或未实现恢复路径展示为 AreaMatrix 的可执行能力。

### `list_undo_actions(repoPath) throws -> [UndoActionRecord]`

```swift
let actions = try AreaMatrix.listUndoActions(repoPath: repoPath)
let latest = actions.first { $0.status == .pending }
undoToast.present(action: latest)
```

undo action log 的 Undo action log 列表入口，服务 `undo toast` 和
`undo history surface undo-history`。输入只包含已初始化 `repoPath`；输出按最近优先返回
Undo stack snapshot，让 toast、历史面板、Cmd+Z 状态和 VoiceOver 可以从合同中
得到同一份可用性状态。

输出 `UndoActionRecord`：

- `action_id`：稳定 undo action 标识，来自 `undo_actions.token`，也是
  `undo_action` 的输入。
- `kind`：稳定操作类型，例如 `batch_add_tags`、`move_files`、`rename_files`
  或 `trash_delete`，供 UI 选择图标和文案。
- `summary`：显示在 toast 和历史行的操作摘要，不要求 UI 解析 JSON。
- `affected_count`：影响文件数或关系数。
- `affected_file_names`：最多若干文件名样例，供 `undo history surface` preview 使用。
- `status`：`Pending`、`Executed`、`Expired`、`Blocked`。
- `can_undo`：当前是否允许通过 `undo_action` 执行。
- `disabled_reason`：过期、被较新的写操作阻塞、外部变化不可撤销、Trash
  不可恢复或权限不足时的用户可读原因。
- `created_at` / `updated_at`：排序、相对时间和状态刷新使用的 Unix 秒级时间戳。

错误与副作用边界：

- `Db`：读取 `undo_actions` metadata、summary 或状态失败。
- `Io`：实现读取与 summary 相关的 AreaMatrix-owned metadata 失败。
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

undo action log 的 Undo 执行入口。输入是已初始化 `repoPath` 和 `action_id`；输出
`UndoActionResult` 告诉 UI 本次撤销的最终状态、影响数量、完成摘要以及需要刷新的
页面状态。该入口只执行 Undo，不执行 Redo；Redo stack 和 `Shift+Cmd+Z` 属于
redo action log。

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
- `Conflict`：外部变化、较新的写操作或当前状态让反向操作不再安全。
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

redo action log 的 Redo action log 列表入口，服务 `redo surface redo`，并被宿主
`undo toast` Redo slot 与 `undo history surface undo-history` Redo row 消费。输入只包含
已初始化 `repoPath`；输出按最近优先返回 redo stack snapshot，让 Redo 按钮、
`Redo latest`、`Shift+Cmd+Z`、VoiceOver 和禁用原因从同一份合同中得到状态。

输出 `RedoActionRecord`：

- `action_id`：稳定 redo action 标识，也是 `redo_action` 的输入。
- `kind`：稳定操作类型，例如 `batch_add_tags`、`move_files`、`rename_files`
  或 `trash_delete`，供 UI 选择图标和文案。
- `summary`：显示在 Redo slot 和历史行的操作摘要，不要求 UI 解析 JSON。
- `affected_count`：影响文件数或关系数。
- `affected_file_names`：最多若干文件名样例，供 `redo surface` preview 使用。
- `status`：`Available`、`Cleared`、`Blocked`、`Expired`、`Executed`。
- `can_redo`：当前是否允许通过 `redo_action` 执行。
- `disabled_reason`：redo stack 被新写操作清空、外部变化阻塞、跨重启过期、
  Trash restore 不可用或权限不足时的用户可读原因。
- `source_undo_action_id`：生成该 redo 行的 undo action log，供 redo surface 说明来源。
- `created_at` / `updated_at`：排序、相对时间和状态刷新使用的 Unix 秒级时间戳。

错误与副作用边界：

- `Db`：读取 redo stack metadata、summary、source undo linkage 或状态失败。
- `Io`：实现读取与 summary 相关的 AreaMatrix-owned metadata 失败。
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

redo action log 的 Redo 执行入口。输入是已初始化 `repoPath` 和 redo `action_id`；输出
`RedoActionResult` 告诉 UI 本次重做的最终状态、影响数量、完成摘要、恢复后的
Undo token 以及需要刷新的页面状态。Redo 只重放 AreaMatrix 成功 Undo 后生成的
可用 redo action；新的写操作会清空 redo stack，多设备协同 redo 不属于当前 redo 合同。

输出 `RedoActionResult`：

- `action_id`：本次请求的 redo action 标识。
- `status`：执行后状态，成功通常为 `Executed`；失败可保持或转为 `Blocked`。
- `summary`：完成或失败文案，例如 `Redone: moved 5 files to Documents.`。
- `affected_count`：实际重做影响范围。
- `refresh_targets`：稳定刷新建议，例如 `files`、`tags`、`undo_actions`、
  `redo_actions`、`change_log`、`tree`、`selection`，供页面消费方刷新对应 store。
- `undo_token`：redo 成功后原操作重新进入 undo action log Undo stack 时创建的 undo token。
- `completed_at`：重做完成时间。

错误与副作用边界：

- `FileNotFound`：`action_id` 为空、找不到 redo action、或原动作引用的文件已不存在。
- `ExpiredAction`：redo action 已被新写操作清空、跨重启过期或不再属于可用 stack。
- `Conflict`：外部变化、路径冲突、stale state 或 Trash preflight 让重做不安全。
- `PermissionDenied`：metadata、目标文件、Trash restore 或目录写入被权限阻断。
- `Db`：读取/标记 redo action、写入 redo `change_log` 或恢复 undo action log stack 失败。
- `Io`：重做文件操作或 rollback 失败。
- Redo 必须按单个 action 的事务边界执行。失败不得破坏当前文件系统和 DB 状态，
  不得把未完成 redo 标记为 `Executed`，不得覆盖外部 FSEvents 造成的变化。
- 该入口不实现 Undo 本身、批量改分类、批量删除、批量重命名、导入冲突批量决策、
  classifier rule、AI 标签建议、远程同步、多设备 redo 或独立 Redo 页面。

页面消费状态：

- redo surface 可以从列表合同得到 redo 可用性、来源 undo action、影响数量、示例文件、
  cleared/blocked/expired 原因、相对时间、`Shift+Cmd+Z` 和 VoiceOver 所需状态。
- redo surface 可以从执行结果得到成功/失败摘要、刷新用 `refresh_targets`、恢复后的
  `undo_token` 和失败后是否继续保留 redo row。
- undo toast surface / undo history surface 只作为宿主区域消费 redo action log 状态；本合同不新增 control map 之外的
  独立 Redo 页面、独立 panel 或其他页面能力。

### `get_file(repoPath, fileId) throws -> FileEntry`

```swift
let entry = try AreaMatrix.getFile(repoPath: repoPath, fileId: 42)
detailView.show(entry)
```

文件不存在抛 `FileNotFound`。
返回的 `FileEntry.availability_status` 与 `list_files` 一致；缺失物理文件的 active
metadata 行仍返回 `FileAvailabilityStatus.Missing`，恢复动作由 missing-file recovery / mobile file detail 入口处理。

### `get_missing_file_state(repoPath, fileId) throws -> MissingFileState`

```swift
let state = try AreaMatrix.getMissingFileState(repoPath: repoPath, fileId: entry.id)
recoverySheet.show(state)
```

`get_missing_file_state` 是 missing-file recovery 的缺失文件恢复状态入口，服务
`missing-file recovery surface missing-file-recovery`。它只读取 AreaMatrix metadata，返回页面需要的
相对路径、最后已知位置、最后见到时间、缺失原因、期望 hash、`Locate File` /
`Try Again` / `Remove Record...` / `Run Rescan...` 可用性，以及 remove-record
确认要求。

错误与副作用边界：

- `FileNotFound`：`fileId` 无效、没有 active row，或目标 row 不是可恢复的缺失文件。
- `PermissionDenied`：metadata 或最后已知路径的只读检查被权限阻断。
- `Db`：恢复状态 metadata 无法读取。
- 该入口不做全库 rescan，不打开平台 picker，不触发 iCloud/Files/OneDrive 下载，
  不删除记录，不写 change log，不移动、重命名、覆盖或删除用户文件。

页面消费状态：

- missing-file recovery surface 可以从 `relative_path`、`last_known_path`、`last_seen_at` 和 `reason`
  渲染摘要区与缺失原因。
- missing-file recovery surface 可以从 `expected_hash_sha256` 判断 relink 是否必须做 hash 校验。
- missing-file recovery surface 可以从 `can_locate`、`can_try_again`、`can_remove_record`、
  `remove_record_requires_confirmation`、`can_run_rescan` 和
  `rescan_disabled_reason` 决定按钮显示、禁用原因和是否路由到 rescan confirmation surface。
- 本合同不新增 control map 之外的页面能力。

### `relink_missing_file(repoPath, request) throws -> MissingFileRecoveryReport`

```swift
let report = try AreaMatrix.relinkMissingFile(
    repoPath: repoPath,
    request: MissingFileRelinkRequest(
        fileId: entry.id,
        newPath: pickedUrl.path,
        confirmed: true
    )
)
```

`relink_missing_file` 是 missing-file recovery 的用户定位后重新关联入口。平台层负责 picker、授权、
权限恢复和用户取消；Core 只接收已授权的新路径。实现必须先用
metadata 中的期望 hash 校验选中文件；hash 匹配才可更新 file path 并写 change log。
hash 不匹配必须保持原记录为 missing，并通过 `status = HashMismatch` 和
`hash_matched = false` 给页面显示，不能覆盖、移动或直接关联。

错误与副作用边界：

- `FileNotFound`：`fileId` 无效、目标 row 不存在，或 `new_path` 为空 / 不存在。
- `PermissionDenied`：缺少 relink 确认，或 Core 无权只读检查选中路径。
- `Db`：metadata 更新或 change-log 写入失败。
- Relink 不删除、不移动、不覆盖用户选择的新文件，也不删除旧路径上的任何文件。
- 用户取消 picker 不应调用本 API；若调用方传入未确认 request，必须返回
  `PermissionDenied` 且不修改 DB 或文件系统。

### `remove_missing_file_record(repoPath, request) throws -> MissingFileRecoveryReport`

```swift
let report = try AreaMatrix.removeMissingFileRecord(
    repoPath: repoPath,
    request: MissingFileRemoveRecordRequest(fileId: entry.id, confirmed: true)
)
assert(report.fileDeleted == false)
```

`remove_missing_file_record` 是 missing-file recovery 的危险动作入口。它只能移除 AreaMatrix metadata
记录并写 change log，不能删除、移动、重命名、覆盖、Trash 或下载任何用户文件。调用前
missing-file recovery surface 必须完成二次确认，确认文案必须说明只删除记录、不删除磁盘文件。

错误与副作用边界：

- `PermissionDenied`：缺少二次确认。
- `FileNotFound`：`fileId` 无效、目标 row 不存在，或目标 row 已不可移除。
- `Db`：metadata 删除或 change-log 写入失败。
- 成功报告必须保持 `record_removed = true`、`file_deleted = false`，并提供
  `change_log_action` 让页面刷新列表和日志。
- 该入口不实现 manual rescan、不创建 sync conflict、不处理 Replace，也不新增
  control map 之外的页面能力。

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
- `locale`：资料库的 exact raw content policy/view locale，例如 canonical `zh-Hans` / `en`、兼容 alias 或
  unknown value；它不控制应用 UI，也不触发配置写回。category 显示依次查询 exact raw key、`en`、slug；
  root 等 built-in label 没有 exact raw translation 时回退 `en`。`system` 必须由平台层先替换为当前 concrete
  interface locale，Core 不读取进程级界面语言。unknown value 允许本只读 API 浏览，但不授权任何 mutation
  或 generation。

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
- `Db` / `DbLocked` / `DbCorrupted`：树构建需要读取 SQLite metadata 时发生通用、锁定或损坏错误。
- `Io`：资料库目录、文件路径、文件 metadata 或分类配置无法读取。

副作用边界：该 API 只读取资料库文件路径和分类配置，不写 DB，不创建 generated
overview，不移动、重命名、删除或修改用户文件。虚拟智能列表、搜索结果树和
搜索结果树投影不属于本接口。详见 [../modules/tree-scan.md](../modules/tree-scan.md)。

### `detect_sync_conflicts(repoPath) throws -> [SyncConflict]`

```swift
let conflicts = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.detectSyncConflicts(repoPath: repoPath)
}.value
let needsReview = conflicts.filter { $0.status == .needsReview }
```

`detect_sync_conflicts` 是 sync conflict detection 的多端同步冲突检测入口，服务
`sync conflict entry surface sync-conflict-entry` 和 `sync conflict review surface sync-conflict`。输入只暴露已授权
且已初始化的 `repoPath`；候选能力文档中的 external events 和 metadata snapshots
由 Core 从已持久化 watcher/import/cloud/conflict state 中读取，不作为 UDL 参数传入。

输出为 `SyncConflict` 列表：

- `conflict_id`：稳定冲突 ID，供 Review 和 sync conflict resolution resolve 绑定。
- `conflict_type`：`SameNameDifferentContent`、`ConcurrentModification`、
  `MetadataMismatch`、`MissingVersion` 或 `Unknown`。
- `severity`：`Low`、`Medium` 或 `High`，供入口排序、徽标和错误摘要使用。
- `status`：当前只声明 `NeedsReview` / `Resolved`；检测入口不得把 Later 当作 resolved。
- `primary_path`：入口行和详情 banner 使用的主路径。
- `affected_files`：一个或多个 `SyncConflictAffectedFile`，包含 path、可选 file id、
  role、size、modified time、hash 和 source platform。
- `version_count`：Core 当前能识别的版本数量。
- `source_provider` / `detected_at` / `summary`：用于来源、最近检测时间和可访问性摘要。

副作用边界：

- 读取 AreaMatrix metadata、已持久化 sync/import/cloud 状态和安全文件 metadata。
- 写入或刷新 conflict state metadata，用于保存检测到的冲突状态、稳定冲突 ID、
  severity、affected files 和 detected_at。
- 不选择任一版本，不标记 resolved，不写 change log，不写 undo，不推进 fs event cursor。
- 不触发 `sync_external_changes`、manual rescan、iCloud/OneDrive 下载、平台 reveal/open 或 AI/网络。
- 不删除、不移动、不重命名、不覆盖、不 Trash、不隐藏任何用户文件或冲突副本。
- 不实现 sync conflict resolution resolve、replace confirmation replace confirm、replace confirmation surface 二次确认或平台差异 UI。

错误：

- `Db`：conflict state metadata 读取/写入、watcher/import/cloud metadata、
  snapshot 绑定或 schema 访问失败。
- `Io`：安全 metadata inspection、路径解析或文件状态读取失败。
- `Conflict`：外部事件和 metadata snapshot 无法稳定绑定到同一个冲突 ID，必须继续用户 review。

页面消费状态：

- sync conflict entry surface 可以从列表长度、`status = NeedsReview`、`detected_at`、`conflict_type`、
  `severity`、`primary_path` 和 `summary` 渲染 banner、Needs Review 列表、错误态和重试入口。
- sync conflict review surface 可以从 `conflict_id`、`affected_files`、`version_count`、
  `source_provider` 和 `severity` 展示冲突摘要与版本卡片的基础 metadata。
- sync conflict review surface 不能从本合同得到解决策略、impact summary、Trash/Recycle Bin 可用性、
  Replace plan、change log 写入结果或 Undo token；这些属于 sync conflict resolution / replace confirmation。
- 本合同不新增 control map 之外的页面能力。

### `preview_sync_conflict_resolution(repoPath, conflictId, resolution) throws -> SyncConflictResolutionPreviewReport`

```swift
let preview = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.previewSyncConflictResolution(
        repoPath: repoPath,
        conflictId: conflict.conflictId,
        resolution: .keepBoth
    )
}.value
let requiresConfirm = preview.requiresReplaceConfirmation
```

`preview_sync_conflict_resolution` 是 sync conflict resolution 的多端同步冲突解决预览入口，服务
`sync conflict review surface sync-conflict` 和 `replace confirmation surface replace-confirm`。输入是已初始化资料库根路径、
sync conflict detection 返回的稳定 `conflict_id`，以及用户当前选择的
`SyncConflictResolutionStrategy`：

- `KeepBoth`：默认安全策略，所有版本继续留在用户可见位置。
- `UseExisting`：canonical path 继续指向 existing，incoming 仍以 conflict copy
  或自动编号路径保留为用户可见文件。
- `UseIncoming`：incoming 将成为 canonical path；必须先进入 replace confirmation surface 二次确认。

输出为 `SyncConflictResolutionPreviewReport`：

- `conflict_id` / `resolution` / `default_resolution`：回显冲突和当前策略，
  `default_resolution` 必须为 `KeepBoth`。
- `status_after`：成功 apply 后的目标状态，成功时为 `Resolved`。
- `version_impacts`：逐版本文件影响，包含 path、可选 file id、role、是否保留、
  是否 canonical、是否仍用户可见、是否计划进入 Trash/Recycle Bin 和恢复目标。
- `kept_paths` / `retained_paths` / `planned_trash_paths`：页面 impact summary
  所需的保留、非 canonical 保留和计划 Trash 路径。
- `affected_file_ids` / `canonical_path`：DB record 影响和解决后的 canonical path。
- `change_log_action`：计划写入的 change-log action。
- `destructive` / `requires_replace_confirmation` / `trash_required` /
  `trash_available` / `can_apply` / `blocked_reason`：按钮可用性和二次确认状态。
- `preview_token`：`resolve_sync_conflict` 绑定同一预览所需的 token。
- `replace_plan`：`UseIncoming` 等可能替换 canonical version 的策略必须返回，
  供 replace confirmation surface 展示 old/new path、hash、affected record、backup target、
  database update、change log 和 recovery note。

副作用边界：

- 只读取 conflict state、sync conflict detection affected file metadata、Trash/Recycle Bin preflight
  和必要的 change-log/DB 可写性预检。
- 不标记 resolved，不写 change log，不写 undo，不推进 fs event cursor。
- 不移动、不删除、不重命名、不覆盖、不 Trash、不隐藏任何用户文件或冲突副本。
- 不触发 iCloud/OneDrive 下载、平台 reveal/open、AI/网络、manual rescan 或
  `sync_external_changes`。
- 不实现内容级 merge，也不新增 control map 之外的页面能力。

错误：

- `Conflict`：`conflict_id` 不存在、过期、版本集合已变化，或 preview token
  无法安全绑定。
- `PermissionDenied`：Trash/Recycle Bin、metadata、版本路径或 DB/change-log
  preflight 被权限阻断；`UseIncoming` 缺少 replace confirmation surface 必要条件时也必须阻断。
- `Io`：安全 metadata、hash、Trash/Recycle Bin preflight 或路径解析失败。
- `Db`：conflict state、file records 或 change-log preflight 读取失败。

页面消费状态：

- sync conflict review surface 可以从 preview 得到策略 impact summary、按钮可用性、change log 类型、
  受影响 record、canonical/retained/Trash 路径和是否需要 replace confirmation surface。
- replace confirmation surface 可以从 `replace_plan` 得到二次确认所需的 old/new file、hash、record id、
  backup target、database update、change log 和 recovery note。
- sync conflict review surface / replace confirmation surface 不能从本合同得到平台 reveal/open 对象、QuickLook 预览、
  内容级 diff、自动合并、云盘 SDK 操作或相邻导入冲突批量能力。

### `resolve_sync_conflict(repoPath, conflictId, resolution) throws -> SyncConflictResolveReport`

```swift
let report = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.resolveSyncConflict(
        repoPath: repoPath,
        conflictId: conflict.conflictId,
        resolution: SyncConflictResolutionRequest(
            strategy: .keepBoth,
            previewToken: preview.previewToken ?? "",
            replaceConfirmed: false,
            replaceConfirmationId: nil
        )
    )
}.value
```

`resolve_sync_conflict` 是 sync conflict resolution 的执行入口，只能在用户完成 preview，且破坏性
策略完成 replace confirmation surface replace-confirm 后调用。`SyncConflictResolutionRequest`
包含 `strategy`、`preview_token`、`replace_confirmed` 和可选
`replace_confirmation_id`。

输出 `SyncConflictResolveReport`：

- `conflict_id`：已解决冲突 ID。
- `resolution`：实际应用的策略。
- `status`：最终冲突状态，成功时为 `Resolved`。
- `kept_paths` / `retained_paths` / `trashed_paths`：解决后仍保留、仍用户可见但非
  canonical、以及进入 Trash/Recycle Bin 的路径。
- `affected_file_ids`：被更新或保留为普通可见文件的 record ids。
- `change_log_action`：实际写入的 change-log action。
- `undo_token`：Trash/Recycle Bin 操作可撤销时返回。
- `resolved_at`：解决时间戳。

副作用边界：

- `KeepBoth` 不删除、不覆盖任何版本；只能保留/新增普通可见 file record，
  关闭 conflict state 并写 change log。
- `UseExisting` 不删除 incoming；existing 保持 canonical，incoming 继续以
  conflict copy 或自动编号路径保留为用户可见文件。
- `UseIncoming` 必须先有 replace confirmation surface 二次确认；existing 只能进入 Trash/Recycle Bin
  或文档明确的 Core safety backup，不允许永久删除或隐藏归档。
- 成功后写 conflict state 和 change log；必要时写 undo action。
- 任一步骤失败必须保持 conflict unresolved；不得清除 `NeedsReview`，不得把失败项
  当作成功，也不得留下无法解释的最终目录半成品。
- 不实现内容级 merge、导入冲突批量策略、通用 batch delete/rename、平台
  QuickLook、云盘 SDK 集成或相邻 replace confirmation 平台能力检测。

错误：

- `Conflict`：preview token 过期、conflict state 或版本集合已变化，或 requested
  resolution 不再安全。
- `PermissionDenied`：replace confirmation 缺失、Trash/Recycle Bin 不可用、
  metadata 或版本路径权限不足。
- `Io`：文件移动、Trash/Recycle Bin、路径解析或失败回滚出错。
- `Db`：conflict state、file records、change log 或 undo action 写入失败。

sync conflict review surface 可以从执行报告移除 `NeedsReview` 行、刷新版本卡片、展示 kept/retained/
Trash 路径、change-log action 和 Undo toast。解决失败时 UI 必须继续展示该冲突
为 unresolved。本合同没有引入 control map 之外的页面能力。

### `list_icloud_conflicts(repoPath) throws -> [ICloudConflictPair]`

```swift
let conflicts = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.listIcloudConflicts(repoPath: repoPath)
}.value
let needsReview = conflicts.filter { $0.status == .needsReview }
```

`list_icloud_conflicts` 是 iCloud conflict listing 的只读 iCloud conflicted copy 列表入口，
用于 iCloud conflict list。输入是已初始化的资料库根路径；输出按冲突副本返回
`ICloudConflictPair`：

- `conflict_id`：稳定冲突 ID，供单项 resolve 入口使用。
- `original_path` / `original_modified_at`：可识别时返回原始版本路径和修改时间。
- `conflicted_copy_path` / `conflicted_modified_at`：冲突副本路径和修改时间。
- `status`：当前状态；识别不确定或需要用户决策时必须为 `NeedsReview`。
- `uncertainty_reason`：原始版本无法确定、多个候选或 metadata 不完整时的结构化原因。

副作用边界：

- 只扫描 iCloud conflicted copy 和可选 conflict state metadata。
- 不删除、不移动、不重命名、不覆盖、不合并任何原始文件或冲突副本。
- 不触发 iCloud placeholder 下载；下载协调属于平台层。
- 不写 `files` 记录；`mark_icloud_conflict_resolved` 这类单项 resolve
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

`preview_conflict_versions` 是 iCloud conflict resolution 的 iCloud 冲突可视化预览入口，
用于 iCloud conflict review surface 在用户明确进入单个冲突后展示版本 metadata、预览摘要和按钮
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
- 不实现 QuickLook UI 渲染、import conflict 批量决策或云盘 SDK 集成。

错误：

- `ICloudPlaceholder`：关键 metadata 或任一必需版本仍是未下载占位符。
- `PermissionDenied`：资料库、版本 metadata、Trash preflight 或 conflict state
  无法检查。
- `Conflict`：`conflict_id` 已过期、无法安全绑定或当前版本集合已变化。
- `Io`：文件系统 metadata、hash 或预览摘要读取失败。
- `Db`：可选 conflict state metadata 读取失败。

iCloud conflict review surface 可以从本合同得到两个或多个版本的 metadata、metadata-only / preview
可用性、默认 Keep both、Trash 不可用时的按钮禁用原因，以及 destructive
二次确认所需的“另一版本会进入 Trash”边界。iCloud conflict review surface 不能从本合同得到
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

`resolve_icloud_conflict` 是 iCloud conflict resolution 的单项解决入口，只能在用户完成 iCloud conflict review surface
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
- 任一步骤失败必须保持 conflict unresolved；不得清除 Needs Review，也不得把
  失败项当作成功。
- 不实现导入冲突批量策略、通用 batch delete、平台 QuickLook、iCloud 下载触发
  或云盘 SDK 集成。

错误：

- `ICloudPlaceholder`：必需版本仍是未下载占位符。
- `PermissionDenied`：Trash、目标文件、metadata 或 conflict state 写入被阻断。
- `Conflict`：preview 后版本集合或 conflict state 已变化，或 requested
  resolution 不再安全。
- `Io`：Trash、文件系统移动或失败回滚出错。
- `Db`：conflict state、change log 或 undo action 写入失败。

iCloud conflict review surface 可以从本合同得到成功后应移除 Needs Review 的状态、保留/Trash 路径、
Undo toast token 和失败时继续保持 unresolved 的判断依据。本合同没有引入
control map 之外的页面能力；iCloud conflict list 仍只消费 `list_icloud_conflicts`，iCloud conflict review surface
消费 preview / resolve。

### `detect_cloud_storage_state(repoPath) throws -> CloudStorageState`

```swift
let state = try AreaMatrix.detectCloudStorageState(repoPath: repoPath)
switch state.providerKind {
case .iCloudDrive:
    iCloudPermissionView.render(state)
case .oneDrive:
    oneDriveNoticeDialog.render(state)
default:
    break
}
```

cloud storage state 的云盘权限状态入口，也是 OneDrive risk notice 的 OneDrive 风险状态合同。服务
`iCloud permission surface`、`OneDrive notice surface`，并为
`iOS repository connection` 和 `Windows choose-repo` 的云盘分支提供结构化提示。
输入只包含已经由平台层授权或尝试恢复的 `repoPath`。

输出 `CloudStorageState`：

- `repo_path`：本次探测的资料库路径。
- `provider_kind`：`Local`、`ICloudDrive`、`OneDrive` 或 `Unknown`。
- `risk`：`NoRisk`、`Low`、`Medium`、`High` 或 `Unknown`，供页面选择提示强度和按钮禁用状态。
- `placeholder_state`：`NotPlaceholder`、`Placeholder` 或 `Unknown`。
- `permission_state`：`Accessible`、`PermissionDenied`、`AccessExpired` 或 `Unknown`。
- `status_summary`：脱敏、可显示的状态摘要，不包含 SDK 原始输出或系统隐私细节。
- `risk_reasons`：结构化风险原因列表，UI 不需要解析 `status_summary`。
- `recommended_action`：`None`、`AcknowledgeNotice`、`RetryStatusCheck`、`ReconnectFolder`
  或 `ChooseLocalFolder`。OneDrive 路径默认返回 `AcknowledgeNotice`，用于提示首次继续前
  必须完成风险确认；平台 UI 仍负责按钮、Explorer reveal 和 watcher route。
- `requires_notice_acknowledgement`：OneDrive 风险提示是否必须在继续打开、初始化或接管前
  被用户确认。
- `notice_acknowledged`：Core-visible metadata 中是否已经记录该 repo 的 OneDrive 风险提示确认。
  OneDrive risk notice 通过 `acknowledge_onedrive_risk_notice` 在已初始化 repo 的 `repo_config` 中持久化该状态。
- `can_retry`：是否可以直接重试同一只读检测。
- `requires_reconnect`：是否需要平台层重新获取目录访问权限。

副作用边界：

- Core 只做平台中立的只读探测：路径形状、基础 metadata、目录可读性和可见占位符 marker。
- 合同检测本身不写 DB、不写 last cloud state、不移动、不删除、不重命名、不覆盖用户文件。
- 不触发 iCloud placeholder 下载，不调用 iCloud / OneDrive SDK，不打开系统设置，不修改云盘同步策略。
- iOS security-scoped bookmark、iCloud 是否登录、OneDrive 客户端同步状态、下载触发和设置跳转都属于平台层。
- 同步冲突、Replace、manual rescan、watcher health、missing-file recovery 仍由各自多端能力覆盖。

错误：

- `InvalidPath`：`repoPath` 为空，或命中 `.areamatrix` metadata 内部路径。
- `ICloudPlaceholder`：资料库路径或关键 metadata 仍是可见云端占位符。
- `PermissionDenied`：metadata 或目录读取被权限阻断。
- `Io`：其他只读文件系统探测失败，例如路径不存在、不是目录或 metadata 不可读。

页面消费状态：

- iCloud permission surface 可以从 `provider_kind`、`placeholder_state`、`permission_state`、`can_retry` 和
  `requires_reconnect` 区分 iCloud 不可用、权限失效、占位符未下载和重试路径。
- OneDrive notice surface 可以从 `provider_kind = OneDrive`、`risk`、`status_summary` 和
  `risk_reasons` 渲染 OneDrive 风险提示、Unknown 状态和继续前确认文案，并从
  `recommended_action = AcknowledgeNotice`、`requires_notice_acknowledgement`、
  `notice_acknowledged` 判断首次选择和已连接说明态。
- Windows choose-repo surface 可以从 OneDrive path validation 路由到 OneDrive notice surface，并在进入 init/adopt/open
  前等待 OneDrive risk notice acknowledgement；它不直接控制 OneDrive 同步。
- iOS repository connection surface 可以把云盘问题路由到 iCloud permission surface，而不是在连接页硬猜平台状态。
- 本合同不新增 control map 之外的页面能力。

### `acknowledge_onedrive_risk_notice(repoPath) throws -> CloudStorageState`

```swift
let state = try AreaMatrix.acknowledgeOnedriveRiskNotice(repoPath: repoPath)
precondition(state.noticeAcknowledged)
```

OneDrive risk notice 的 OneDrive 风险提示确认写入入口。`OneDrive notice surface` 只能在用户已经明确确认
OneDrive 风险文案后调用；调用成功后返回刷新后的 `CloudStorageState`，其中
`notice_acknowledged = true`、`requires_notice_acknowledgement = false`、
`recommended_action = None`。

输入只包含已初始化资料库根路径。Core 会复用 `detect_cloud_storage_state` 的平台中立路径检查，
只在 `provider_kind = OneDrive` 时写入 `repo_config` key
`onedrive_risk_notice_acknowledged = true`；非 OneDrive 路径不写该 key，只返回当前刷新状态。

副作用边界：

- 只写 `.areamatrix/index.db` 中的 `repo_config` 元数据，不写用户文件。
- 不自动创建 `.areamatrix/`、不初始化 repo、不 reindex、不移动、不删除、不重命名、不覆盖用户文件。
- 不触发 iCloud placeholder 下载，不调用 iCloud / OneDrive SDK，不打开系统设置，不修改云盘同步策略。
- UI 仍负责确认复选框、文案展示、Explorer reveal、进入 watcher 状态页和导航。

错误：

- `InvalidPath`：`repoPath` 为空，或命中 `.areamatrix` metadata 内部路径。
- `ICloudPlaceholder`：资料库路径或关键 metadata 仍是可见云端占位符。
- `PermissionDenied`：metadata、目录读取或 acknowledgement 写入被权限阻断。
- `Io`：路径不是目录、metadata 缺失、repo 尚未初始化、SQLite 写入或其他只读 / metadata 探测失败。

页面消费状态：

- OneDrive notice surface 调用成功后可直接用返回的 `CloudStorageState` 切换到已确认说明态。
- Windows choose-repo surface 在 init/adopt/open 前可用 `notice_acknowledged` 判断是否允许继续。
- 本合同不新增 control map 之外的页面能力，也不实现企业 OneDrive 管理集成。

### `preview_import_conflict_batch(repoPath, request) throws -> ImportConflictBatchPreviewReport`

```swift
let preview = try AreaMatrix.previewImportConflictBatch(
    repoPath: repoPath,
    request: request
)
applyButton.isEnabled = preview.canApply && !preview.replaceConfirmationRequired
```

`preview_import_conflict_batch` 是 import conflict batch 的只读批量导入冲突预览入口，
服务 `import conflict batch review`。输入 `ImportConflictBatchPreviewRequest`
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
- Ask-per-item 只作为输出状态和路由依据；本接口不打开 duplicate import review/name-conflict review/replace confirmation，也不执行逐项策略。

错误：

- `FileNotFound`：`import_session_id` 为空、`conflict_ids` 为空，或指定 session/conflict 已不存在。
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

`apply_import_conflict_batch` 是 import conflict batch 的执行入口，只能在 import conflict review surface 完成 preview 和必要
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
- `failure_summary`：部分失败后的恢复摘要，供 import conflict review surface `Retry failed` / `Ask per item` 使用。

副作用边界：

- `Skip` 对 hash duplicate 不导入重复内容，不删除、不移动、不覆盖已有文件；保持可追踪结果。
- `KeepBoth` 为 incoming 文件生成安全新名称并继续导入，不覆盖已有文件。
- `Replace` 必须在 `replace_confirmed = true` 且 Trash / recovery 可用时执行；旧文件必须进入
  Trash 或可恢复路径，写 change log 和 undo action。
- `AskPerItem` 不执行批量策略，只把当前作用域行保留为逐项处理队列状态。
- 未勾选或不在当前作用域的行保持 staging unresolved，不写 change log，不进入 Undo stack。
- 任一失败必须保留 staged 文件和冲突状态；不得清除 pending/unresolved，不得把失败项当成功。
- 不实现 iCloud conflict、sync conflict resolution、通用 batch delete/rename/category、classifier rule、
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

- import conflict review surface 可以从 preview 合同得到冲突分组、默认安全策略、全量/选中作用域、pending 行、
  Replace 数量、blocked 数量、Index-only 禁止 Replace、Trash/Undo 可用性、二次确认文案、
  Apply/Ask-per-item 是否可用和 VoiceOver 所需状态文本。
- import conflict review surface 可以从执行报告得到成功/失败/跳过/替换/保留两份/pending/逐项队列摘要、刷新用
  `affected_file_ids`、`undo_token`、change log action 和失败恢复摘要。
- undo toast surface / undo action log 只消费 `undo_token` 和 `list_undo_actions` / `undo_action` 状态。
- Ask-per-item 进入 duplicate import review / name-conflict review / replace confirmation 的路由由对应页面能力处理；本合同不新增
  control map 之外的页面能力。

---

## note API

### `read_note(repoPath, fileId) throws -> String?`

```swift
if let note = try AreaMatrix.readNote(repoPath: repoPath, fileId: entry.id) {
    detailView.noteEditor.text = note
}
```

DB 中没有 note row 时返回 `nil`，不会自动接管同名 Markdown 文件。DB 存在时，Core 同时读取
`<filename>.md`；只有两者内容一致才返回笔记。sidecar 缺失、无法读取或内容与 DB 不一致时返回错误，
不用任一侧静默覆盖另一侧。

外部编辑受管 sidecar 不会自动回写 DB。watcher 只把该事件作为可确认 cursor 的受管事件跳过，下一次
`read_note` 或 `write_note` 会暴露不一致。

sidecar 或其父目录的读取权限不足时返回 `PermissionDenied`；其他文件系统读取失败返回 `Io`，note
metadata 查询失败返回 `Db`。这些错误都不会修改 DB、sidecar 或用户文件。

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

写入前 Core 校验旧状态：

- DB 与 sidecar 都不存在：允许创建。
- 两者存在且内容一致：允许替换。
- 只有一侧存在或内容不一致：返回错误，不覆盖用户内容。

sidecar 先通过同目录临时文件原子落位；`notes` row 与 `edited_note` change log 在同一 transaction 中提交。
DB 提交失败时恢复旧 sidecar。

---

## sync API

### `sync_external_changes(repoPath, events, contentLocale) throws -> SyncResult`

```swift
let coreEvents = events.map { e in
    ExternalEvent(
        path: e.relativePath,
        kind: e.kind,
        fsEventId: e.eventId
    )
}

let result = try await Task.detached {
    try AreaMatrix.syncExternalChanges(
        repoPath: repoPath,
        events: coreEvents,
        contentLocale: resolvedRepositoryContentLocale
    )
}.value

print(
    "created: \(result.detectedCreates), renamed: \(result.detectedRenames), " +
        "deleted: \(result.detectedDeletes), modified: \(result.detectedModifies)"
)
appState.refreshList()
```

应用调用方在去抖 + InFlight 过滤后传入按路径归一化的事件。rename 只携带新路径；旧/新路径配对由
Core 根据稳定 hash 完成，平台层不提供 inode 或路径配对。详见
[../architecture/source-of-truth.md](../architecture/source-of-truth.md)。
Swift 同步窗口创建时不读取 locale。只有带业务事件的窗口到达有序队首、准备第一次 Core attempt 时才
冻结 `contentLocale`；同一 window 的 retry/replay 复用，filtered-only window 不冻结。窗口因为前序失败
尚未到队首时，设置仍可改变它未来首次捕获的值。

事件行为：

- `Created`：登记新的 external/indexed row；active 同路径幂等跳过，deleted 同路径复用原 file ID 并恢复
  active，staging 同路径返回 Conflict；不复制或移动用户文件。
- `Renamed`：Core 按稳定 hash 选择唯一 active 候选，并确认候选旧路径已消失后，更新同一 file ID 的
  path、name、category 和稳定 metadata 快照；零个或多个候选、旧路径仍存在、或目标路径被 active、
  staging、deleted 任一 row 占用时都返回 Conflict，不猜测、不降级为其他事件组合。唯一例外是幂等
  重放：事件收据命中、或 change_log 已记录同一事件的 renamed 结果时，按已应用跳过，不算冲突。
- `Removed`：只在路径已不存在时 soft-delete 对应 active row。
- `Modified`：稳定读取后更新已有 row 的 size/hash；未登记的现存路径按 external create 处理。读取期间
  文件持续变化时返回可重放 Conflict，不推进 cursor。

schema v3 的 `external_sync_receipts.content_locale` 是 nullable 且带
`CHECK (content_locale IN ('zh-Hans', 'en'))` 的 provenance 列。nullable 只为 v2 legacy row 保留；所有
新 receipt 必须在 files/change_log 同一事务中写入非空、合法的 `contentLocale`。同一 event ID 的多条
receipt 如果出现不同非空 locale，说明 provenance 已损坏，返回 `Internal`，不得猜测。

整批规划成功后，Core 先在一个 SQLite 事务中提交 files/change_log 与 receipts，再根据本次相关事件与
既有 receipts 计算 overview locale：每个 node 使用影响该 node 的最大 relevant event ID 对应 locale；root
使用全批最大 relevant event ID 对应 locale，并且每批只生成一次。已存在与新写入 receipt 可以组成 mixed
replay，不把“部分已存在”本身当成 Conflict。

legacy `NULL content_locale` receipt 不得由 `sync_external_changes` 使用当前设置或本次调用参数隐式 claim。
发现任一 NULL receipt 时，同步返回 `Config` 并保持 receipt、overview 与 cursor 不变；平台进入下面的显式
recovery 流程。该兼容路径不新增 sidecar。

### `prepare_external_sync_locale_recovery(repoPath) throws -> ExternalSyncLocaleRecoveryPlan?`

读取当前 repository、`fs_event_cursor` 与全部 legacy NULL receipt，按 `(event_id, kind, path)` 稳定排序并返回
绑定 repository / cursor / exact receipt set 的 opaque recovery token。不存在 NULL receipt 时返回 `nil`。
本 API 只读，不修改 receipt、cursor、overview 或用户文件。

### `resolve_external_sync_locale_recovery(repoPath, recoveryToken, contentLocale) throws -> ExternalSyncLocaleRecoveryReport`

用户明确选择 concrete `zh-Hans` 或 `en` 后调用。Core 在 `BEGIN IMMEDIATE` transaction 中重新读取 cursor 与
NULL receipt exact set，重新计算 token；token 为空、stale、cursor 或集合变化时返回 `Conflict` 且零写入。
校验成功后仅把 exact set 内仍为 NULL 的 `content_locale` 原子写为所选值；任一 row count 不为 1 时整批回滚。
成功后平台重试原 external sync window，后续 replay 只使用 receipt 中已冻结的 locale。该 API 不推进 cursor、
不生成 overview、不移动/删除/重命名/覆盖用户文件，也不允许从当前界面或资料库设置推断选择。

overview 和 cursor 成功前 receipts 都保留。overview 或 cursor 失败时 cursor 不推进，也不清理 receipts；
重放继续按 receipt provenance 生成。只有 cursor 成功单调推进后，才清理不高于 cursor 的旧 receipts。

受管 note sidecar 事件不登记为普通 external 文件，但合法 event ID 仍计入批次 cursor；它不属于生成
overview 的 relevant event。Swift watcher 还
把每次 flush 记录为有序同步窗口并携带 `cursorWatermark`：Core 成功后可补写高于实际 signal 最大值的
watermark；全部事件在 Swift 层被过滤时形成空窗口，并在前序窗口完成后确认 watermark。Core 或 cursor
失败必须保留队首并阻断后续窗口，不能静默跳过，也不能丢弃已冻结 locale。

资料库尚未初始化时返回 `RepoNotInitialized`；该错误不创建 `.areamatrix/`、DB 或 cursor，也不触碰用户
文件。

### `get_fs_event_cursor(repoPath) throws -> Int64?`

```swift
let cursor = try AreaMatrix.getFsEventCursor(repoPath: repoPath)
guard let cursor else {
    requestConfirmedFullRescan()
    return
}
let stream = startFSEventStream(sinceWhen: cursor)
```

启动时从已初始化资料库的 `.areamatrix/index.db` 读取。返回 `nil` 只表示 `fs_event_cursor` 尚无持久化
row，不表示资料库可以未初始化；平台层不得静默从 `SinceNow` 开始，而应进入用户可见的全量重扫恢复。

无效资料库路径返回 `InvalidPath`，缺少 AreaMatrix metadata 返回 `RepoNotInitialized`，placeholder-shaped
路径返回 `ICloudPlaceholder`，路径检查受权限阻断返回 `PermissionDenied`，其他文件系统检查失败返回
`Io`，SQLite 打开或查询失败返回 `Db`。

### `set_fs_event_cursor(repoPath, lastEventId) throws`

```swift
try AreaMatrix.setFsEventCursor(repoPath: repoPath, lastEventId: confirmedRescanSeed)
```

该 API 用于已初始化资料库的初始 cursor、已确认全量重扫后的恢复 seed，以及 watcher 的 watermark 确认。
`sync_external_changes` 在 DB 和 overview 成功后负责推进实际业务事件的最大 cursor；Swift 可以在 Core
成功后补写更高的回调窗口 watermark，或在 filtered-only 窗口到达有序队首时确认 watermark。写入使用
单调最大值，较旧 seed 不会使 cursor 回退，负 `lastEventId` 返回 `InvalidPath`。

cursor 只写入 `.areamatrix/index.db`。资料库路径校验还可能返回 `InvalidPath`、`RepoNotInitialized`、
`ICloudPlaceholder`、`PermissionDenied` 或 `Io`；SQLite 打开、transaction 或写入失败返回 `Db`。

### `record_watcher_health(repoPath, signal) throws -> PlatformWatcherSnapshot`

```swift
let snapshot = try AreaMatrix.recordWatcherHealth(
    repoPath: repoPath,
    signal: PlatformWatcherHealthSignal(
        backend: .readDirectoryChangesW,
        status: .running,
        watchedPath: repoPath,
        lastEventId: lastEventId,
        lastEventAt: lastEventAt,
        lastSyncEventId: cursor,
        lastSyncAt: lastSyncAt,
        lastRescanAt: lastRescanAt,
        pendingEventCount: pendingEvents.count,
        watchCount: activeWatchCount,
        errorSummary: nil,
        healthReasons: [],
        recentEvents: recentSamples,
        reportedAt: now
    )
)
```

platform watcher status 的平台 watcher 状态入口，服务 `Windows watcher-status surface watcher-status` 和
`Linux watcher-status surface watcher-status`。输入是平台层已经去抖、过滤并脱敏后的 watcher health
signal；Core 不启动 ReadDirectoryChangesW / inotify，不重建 watcher，也不直接读取平台
watcher backend。

输入 `PlatformWatcherHealthSignal`：

- `backend`：`ReadDirectoryChangesW`、`Inotify` 或 `Unknown`。
- `status`：`Starting`、`Running`、`Paused`、`Error` 或 `Unavailable`。
- `watched_path`：当前平台服务监听路径，用于页面显示和诊断。
- `last_event_id` / `last_event_at`：最近 watcher 事件 id 和时间。
- `last_sync_event_id` / `last_sync_at`：最近成功同步到 Core metadata 的事件 id 和时间。
- `last_rescan_at`：最近一次手动重扫完成时间，若未知则为空。
- `pending_event_count`：等待同步的事件数量。
- `watch_count`：平台 backend 暴露的 watch 数量，Linux inotify 页面可用。
- `error_summary`：脱敏、可显示的错误摘要，不包含用户文件内容或 SDK 原始输出。
- `health_reasons`：结构化原因，例如 `PermissionDenied`、`PathMissing`、
  `DatabaseLocked`、`LimitExceeded`、`NetworkMount`、`CloudSyncNoise`。
- `recent_events`：最多 5 条诊断事件样本，只包含路径、kind、event id 和可选时间。
- `reported_at`：平台采集该 signal 的 Unix 时间。

输出 `PlatformWatcherSnapshot`：返回同一组结构化字段，并补上 `repo_path`，供 Windows/Linux
watcher status 页面渲染状态卡、禁用条件、错误摘要和诊断预览。

副作用边界：

- 本合同只记录 AreaMatrix-owned watcher health metadata；不得移动、删除、重命名或覆盖用户文件。
- 不触发 `sync_external_changes`，不推进 fs event cursor；事件失败不应推进 cursor。
- 不启动手动 rescan，不调用 `reindex_from_filesystem`，`Run rescan now` 必须进入
  `rescan confirmation`，由 manual rescan 处理确认和扫描。
- 不打开 Explorer / 文件管理器，不创建 diagnostics snapshot 或脱敏报告；这些动作属于平台层或独立能力。
- 不读取用户文件正文，不触发 iCloud/OneDrive 下载，不修改系统 watcher/inotify 设置。

错误：

- `Db`：health signal 无效、watcher health metadata 不可读写、DB locked 或 schema 不可用。
- `Io`：实现读取或写入 AreaMatrix-owned metadata 时发生文件系统错误。

页面消费状态：

- Windows watcher-status surface 可以从 `status`、`backend = ReadDirectoryChangesW`、`watched_path`、
  `last_event_at`、`pending_event_count`、`last_rescan_at` 和 `error_summary` 渲染
  Running / Starting / Paused / Error / Unavailable、Path missing、OneDrive 事件噪声和恢复动作。
- Linux watcher-status surface 可以从 `backend = Inotify`、`watch_count`、`health_reasons` 和
  `error_summary` 渲染 limit exceeded、network mount、permission denied 等状态。
- 两个平台的 `Run rescan now` 只能根据 snapshot 判断入口可用性；真正执行必须先进入
  rescan confirmation surface，不由 platform watcher status 直接触发。
- 本合同不新增 control map 之外的页面能力。

---

## error API

### `map_core_error(input: ErrorMappingInput) -> ErrorMapping`

```swift
let mapping = AreaMatrix.mapCoreError(
    input: ErrorMappingInput(
        kind: .permissionDenied,
        path: repoPath,
        reason: nil,
        message: nil
    )
)
```

error mapping 的错误映射入口。输入用稳定的 `ErrorKind` 加可选 `path`、`reason`、`message`
描述 Core 错误 payload；输出固定返回 `kind`、`code`、`field`、`arguments`、
`recovery_action_ids`、`severity`、`recoverability` 和可选 `technical_details`。Swift 错误包装层
（`AppSemanticError`）按当前界面语言解析 code/action IDs，不保存 Core 生成的展示句子。

副作用边界：

- 纯映射函数，不读写文件系统、数据库、日志或 repo 状态。
- 不替代 `CoreError`；调用方仍应保留原始结构化错误 case。
- UI 不得用 localized string 或 string contains 作为主分支判断。

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
        // Observability 由应用级装配初始化；repository bootstrap 只执行本资料库恢复。
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
- `detect_sync_conflicts`（可能读写 conflict metadata 并扫描文件 metadata）
- `list_icloud_conflicts`（扫描 iCloud conflicted copy）
- `preview_move_to_category`（目标路径和同名冲突预检）
- `move_to_category`（可能移动 repo-owned 文件）
- `add_tag` / `remove_tag`（写标签 metadata 和 change log）
- `sync_external_changes`（批量事件）

下列函数轻量，可同步调（< 5ms）：

- `get_version`
- `predict_category`
- `load_repo_config`
- `get_latest_scan_session`
- `get_file`
- `list_tags`
- 单条 `list_files`（limit ≤ 50）

### 错误处理统一规约

Core 对 error mapping 暴露 `map_core_error(input: ErrorMappingInput) -> ErrorMapping`。
输入用 `ErrorKind` 加原始 `path` / `reason` / `message` 表示同一个
`CoreError` payload；输出固定包含 `kind`、`code`、`field`、`arguments`、
`recovery_action_ids`、`severity`、`recoverability` 和可选 `technical_details`。该函数无文件系统、
数据库、日志或状态副作用，Swift 错误包装层只能基于这些结构化字段编排
本地化和展示，不得用字符串 contains 做主分支判断，也不得持久化解析后的展示句子。

```swift
let mapping = await errorMapper.mapCoreError(error)
let presentation = localizer.errorPresentation(
    code: mapping.code,
    arguments: mapping.arguments,
    recoveryActionIDs: mapping.recoveryActionIDs
)
show(presentation, severity: mapping.severity)
```

详见 [error-codes.md](error-codes.md)。

### 取消与超时

UniFFI 0.x 不支持 Rust 端 cooperative cancellation。Swift 端 `Task.cancel()` 不会立刻打断 Rust 调用。对策：

- 长时间运行操作（reindex / sync）拆成多次小调用
- 启动时显示 indeterminate 进度，超过 X 秒提示用户耐心
- 不为单次调用加 timeout

详见 [uniffi-recipes.md](uniffi-recipes.md)。

---

## 合同演进规则

- 对外 API 变化先更新本文，再同步 `core/area_matrix.udl`、Rust facade、生成绑定、平台桥接和测试。
- 新增字段优先保持向后兼容；删除、重命名或改变副作用属于破坏性变化，必须经过版本与迁移评审。
- 候选能力在完成产品合同、风险分析和跨层验证前不得写入正式 UDL。
- 具体版本的 API 变更记录在 [CHANGELOG](../../CHANGELOG.md) 和对应版本归档中，不在长期合同内维护交付路线。

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
