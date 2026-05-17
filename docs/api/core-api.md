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
    sequence<UndoActionRecord> list_undo_actions(string repo_path);

    [Throws=CoreError]
    UndoActionResult undo_action(string repo_path, string action_id);

    [Throws=CoreError]
    FileEntry get_file(string repo_path, i64 file_id);

    [Throws=CoreError]
    sequence<ChangeLogEntry> list_changes(string repo_path, ChangeFilter filter);

    [Throws=CoreError]
    string list_tree_json(string repo_path, string locale);

    [Throws=CoreError]
    sequence<ICloudConflictPair> list_icloud_conflicts(string repo_path);

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
enum ICloudConflictStatus { "NeedsReview", "Resolved" };
enum ExternalEventKind { "Created", "Removed", "Modified", "Renamed" };
enum BatchMutationStatus { "Added", "AlreadyHadTag", "Failed" };
enum UndoActionStatus { "Pending", "Executed", "Expired", "Blocked" };
enum ErrorKind {
    "Io", "Db", "Config", "Classify", "Conflict", "DuplicateFile",
    "FileNotFound", "RepoNotInitialized", "InvalidPath",
    "ICloudPlaceholder", "PermissionDenied", "Internal"
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
    Classify(string reason);
    Conflict(string path);
    DuplicateFile(string existing_path);
    FileNotFound(string path);
    RepoNotInitialized(string path);
    InvalidPath(string path);
    ICloudPlaceholder(string path);
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
| `add_tag(repo, file_id, tag)` | tags | √ | FileNotFound / Db / InvalidPath |
| `remove_tag(repo, file_id, tag)` | tags | √ | FileNotFound / Db / InvalidPath |
| `list_tags(repo, file_id)` | tags | √ | FileNotFound / Db / InvalidPath |
| `batch_add_tags(repo, file_ids, tags)` | tags | √ | FileNotFound / Db |
| `list_undo_actions(repo)` | undo | √ | Db / Io |
| `undo_action(repo, action_id)` | undo | √ | Conflict / FileNotFound / PermissionDenied / Db / Io |
| `get_file(repo, file_id)` | query | √ | FileNotFound |
| `list_changes(repo, filter)` | query | √ | Db |
| `list_tree_json(repo, locale)` | query | √ | RepoNotInitialized / Db / Io |
| `list_icloud_conflicts(repo)` | query | √ | ICloudPlaceholder / PermissionDenied / Io / Db |
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
  以及 C2-07 undo action log（`list_undo_actions`、`undo_action`）已提升为
  本文与 `core/area_matrix.udl` 的稳定合同；
  Redo、批量分类/删除/重命名、导入冲突批量决策、非 AI 标签建议、
  分类规则编辑仍见
  [../core/capability-specs/stage-2-experience.md](../core/capability-specs/stage-2-experience.md)。
- Stage 3：AI 配置、本地模型、远程 provider、AI 建议、AI 日志、语义搜索、隐私规则，见 [../core/capability-specs/stage-3-ai.md](../core/capability-specs/stage-3-ai.md)。
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
| 0.2.x | 加 `search`、`batch_import`、`undo` |
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
