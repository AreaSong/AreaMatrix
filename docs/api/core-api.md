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
    ClassifyResult predict_category(string repo_path, string filename);

    [Throws=CoreError]
    FileEntry import_file(
        string repo_path, string source_path, ImportOptions options
    );

    [Throws=CoreError]
    void delete_file(string repo_path, i64 file_id, boolean hard);

    [Throws=CoreError]
    FileEntry rename_file(string repo_path, i64 file_id, string new_name);

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
    string? read_note(string repo_path, i64 file_id);

    [Throws=CoreError]
    void write_note(string repo_path, i64 file_id, string content_md);

    [Throws=CoreError]
    SyncResult sync_external_changes(string repo_path, sequence<ExternalEvent> events);

    [Throws=CoreError]
    i64? get_fs_event_cursor(string repo_path);

    [Throws=CoreError]
    void set_fs_event_cursor(string repo_path, i64 last_event_id);
};

dictionary RepoConfig {
    string repo_path;
    StorageMode default_mode;
    OverviewOutput overview_output;
    boolean ai_enabled;
    string locale;
    boolean icloud_warn;
};

dictionary RepoInitOptions {
    RepoInitMode mode;
    boolean create_default_categories;
    OverviewOutput overview_output;
};

dictionary ImportOptions {
    StorageMode mode;
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
    string? source_path;
    i64 imported_at;
    i64 updated_at;
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
    i64 inserted;
    i64 updated;
    i64 skipped;
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

enum StorageMode { "Moved", "Copied", "Indexed" };
enum RepoInitMode { "CreateEmpty", "AdoptExisting" };
enum OverviewOutput { "GeneratedOnly", "RootAreaMatrixFile" };
enum DuplicateStrategy { "Skip", "Overwrite", "KeepBoth", "Ask" };
enum ClassifyReason { "Keyword", "Extension", "AiPredicted", "Default" };
enum ExternalEventKind { "Created", "Removed", "Modified", "Renamed" };

[Error]
enum CoreError {
    "Io", "Db", "Config", "Classify", "Conflict",
    "DuplicateFile", "FileNotFound", "RepoNotInitialized",
    "InvalidPath", "ICloudPlaceholder", "PermissionDenied", "Internal"
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
| `init_repo(path, options)` | repo | √ | Io / Config / PermissionDenied |
| `load_config(repo)` | repo | √ | Io / Config |
| `update_config(repo, cfg)` | repo | √ | Io |
| `recover_on_startup(repo)` | repo | √ | Db |
| `reindex_from_filesystem(repo)` | repo | √ | Io / Db |
| `predict_category(repo, name)` | classify | √ | Config |
| `import_file(repo, src, options)` | storage | √ | Io / Db / DuplicateFile / InvalidPath |
| `delete_file(repo, file_id, hard)` | storage | √ | Io / Db / FileNotFound |
| `rename_file(repo, file_id, new_name)` | storage | √ | Io / InvalidPath |
| `move_to_category(repo, file_id, cat)` | storage | √ | Classify / Io |
| `restore_file(repo, file_id)` | storage | √ | FileNotFound |
| `list_files(repo, filter)` | query | √ | Db |
| `get_file(repo, file_id)` | query | √ | FileNotFound |
| `list_changes(repo, filter)` | query | √ | Db |
| `list_tree_json(repo, locale)` | query | √ | Io |
| `read_note(repo, file_id)` | note | √ | Io |
| `write_note(repo, file_id, content)` | note | √ | Io |
| `sync_external_changes(repo, events)` | sync | √ | Db |
| `get_fs_event_cursor(repo)` | sync | √ | Db |
| `set_fs_event_cursor(repo, id)` | sync | √ | Db |

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
- 创建 SQLite + 应用 schema v1
- `AdoptExisting` 模式下调用首次 `reindex_from_filesystem`
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

文件不存在时返回默认值（不抛错）。

### `update_config(repoPath: String, newConfig: RepoConfig) throws`

```swift
var cfg = try AreaMatrix.loadConfig(repoPath: repoPath)
cfg.defaultMode = .copied
cfg.overviewOutput = .generatedOnly
cfg.locale = "zh-Hans"
try AreaMatrix.updateConfig(repoPath: repoPath, newConfig: cfg)
```

原子写入（先写 tmp 再 rename）。

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

无 IO 副作用，仅返回预测。UI 在拖入时调用以填充 ImportSheet。

---

## storage API

### `import_file(repoPath, sourcePath, options) throws -> FileEntry`

```swift
func importDroppedFile(_ url: URL) async {
    let options = ImportOptions(
        mode: appState.config.defaultMode,
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

### `delete_file(repoPath, fileId, hard) throws`

```swift
func deleteFile(_ entry: FileEntry, hard: Bool = false) async {
    do {
        try await Task.detached {
            try AreaMatrix.deleteFile(
                repoPath: repoPath,
                fileId: entry.id,
                hard: hard
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

`hard=false`：移到废纸篓 + DB 软删除。
`hard=true`：物理删除 + DB 软删除。

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

仅改文件名，不改分类。文件名包含禁用字符（`/ \\ : * ? " < > |`）会抛 `InvalidPath`。

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

`new_category` 必须在 `classifier.yaml` 中存在，否则抛 `Classify`。

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

返回 JSON 字符串而非 `TreeNode`，避免大 sequence 跨 FFI 多次拷贝。详见 [../modules/tree-scan.md](../modules/tree-scan.md)。

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
- `recover_on_startup`（启动时）
- `list_tree_json`（大库）
- `sync_external_changes`（批量事件）

下列函数轻量，可同步调（< 5ms）：

- `get_version`
- `predict_category`
- `load_config`
- `get_file`
- 单条 `list_files`（limit ≤ 50）

### 错误处理统一规约

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
- [../architecture/ffi-design.md](../architecture/ffi-design.md)
- [../modules/storage.md](../modules/storage.md)
- [../modules/classify.md](../modules/classify.md)
- [../modules/change-log.md](../modules/change-log.md)
- [../modules/tree-scan.md](../modules/tree-scan.md)
