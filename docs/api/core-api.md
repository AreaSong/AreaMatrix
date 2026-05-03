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
enum ICloudConflictStatus { "NeedsReview", "Resolved" };
enum ExternalEventKind { "Created", "Removed", "Modified", "Renamed" };
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
| 错误映射元数据 | S1-03, S1-06, S1-11, S1-25, S1-32 | C1-21 | 每个错误返回 severity、suggested_action、recoverability，避免 UI 解析字符串 | `map_core_error` 返回 Core 侧稳定映射元数据，Swift `AppError` 包装层只负责本地化与展示编排 |

这些缺口不得被 UI 静态 mock 掩盖。若某个 UI 任务进入真实闭环验收，而所需缺口尚未实现或没有明确替代路径，验收应判定不通过。

### Stage 2-4 API 规划入口

Stage 2-4 的后续接口先以 capability specs 作为合同来源，不直接落 UDL：

- Stage 2：搜索、标签、Smart List、Undo/Redo、批量操作、导入冲突批量决策、非 AI 标签建议、分类规则编辑，见 [../core/capability-specs/stage-2-experience.md](../core/capability-specs/stage-2-experience.md)。
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
- `resume_scan_session`（可能继续全扫）
- `recover_on_startup`（启动时）
- `list_tree_json`（大库）
- `list_icloud_conflicts`（扫描 iCloud conflicted copy）
- `preview_move_to_category`（目标路径和同名冲突预检）
- `move_to_category`（可能移动 repo-owned 文件）
- `sync_external_changes`（批量事件）

下列函数轻量，可同步调（< 5ms）：

- `get_version`
- `predict_category`
- `load_config`
- `get_latest_scan_session`
- `get_file`
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
