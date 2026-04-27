# Core API（UDL 接口规范）

> AreaMatrix Core 暴露给 Swift/Kotlin/Python 的所有函数与类型，权威定义。任何对外接口变化必须先改本文档与 `area_matrix.udl`。
>
> 阅读时长：约 8 分钟。

---

## 接口稳定性约定

- **MVP 阶段（Stage 1）**：接口处于 unstable，每个版本可能调整
- **Stage 2 起**：接口稳定，破坏性变化只在 MAJOR 版本发生
- **废弃流程**：标记 `@deprecated` 至少保留一个 MINOR 版本

---

## 函数总览

| 函数 | 类别 | Throws |
|---|---|---|
| `get_version()` | meta | × |
| `init_logging(level)` | meta | √ |
| `init_repo(path)` | repo | √ |
| `load_config(repo)` | repo | √ |
| `update_config(repo, cfg)` | repo | √ |
| `recover_on_startup(repo)` | repo | √ |
| `reindex_from_filesystem(repo)` | repo | √ |
| `predict_category(repo, name)` | classify | √ |
| `import_file(repo, src, options)` | storage | √ |
| `delete_file(repo, file_id, hard)` | storage | √ |
| `rename_file(repo, file_id, new_name)` | storage | √ |
| `move_to_category(repo, file_id, cat)` | storage | √ |
| `restore_file(repo, file_id)` | storage | √ |
| `list_files(repo, filter)` | query | √ |
| `get_file(repo, file_id)` | query | √ |
| `list_changes(repo, filter)` | query | √ |
| `list_tree_json(repo, locale)` | query | √ |
| `read_note(repo, file_id)` | note | √ |
| `write_note(repo, file_id, content)` | note | √ |
| `sync_external_changes(repo, events)` | sync | √ |
| `get_fs_event_cursor(repo)` | sync | √ |
| `set_fs_event_cursor(repo, id)` | sync | √ |

---

## meta

### `get_version() -> String`

返回 Core 版本（来自 `Cargo.toml`），形如 `"0.1.0"`。

### `init_logging(level: String) -> Result<(), CoreError>`

初始化 Rust tracing。`level` ∈ `"trace"|"debug"|"info"|"warn"|"error"`。

应用应在最早调用，避免 Core 中间状态丢日志。

---

## repo

### `init_repo(repo_path: String) -> Result<(), CoreError>`

在指定路径初始化资料库：

- 创建 `<repo>/{docs,code,design,media,finance,inbox}/`
- 创建 `<repo>/.areamatrix/{staging/}`
- 复制默认 `classifier.yaml`
- 创建 SQLite 并应用 schema
- 写入根 README.md

如目录已存在但非空 → `CoreError::Config { reason: "non-empty directory" }`。

### `load_config(repo_path: String) -> Result<RepoConfig, CoreError>`

加载 `.areamatrix/config.json`。文件不存在时返回默认值。

```rust
pub struct RepoConfig {
    pub repo_path: String,
    pub default_mode: StorageMode,  // 默认 Copied
    pub ai_enabled: bool,           // 默认 false
    pub locale: String,             // 默认 "zh-CN"
    pub icloud_warn: bool,          // 默认 true
}
```

### `update_config(repo, new_config) -> Result<(), CoreError>`

原子写入新配置（先写 tmp 再 rename）。

### `recover_on_startup(repo) -> Result<RecoveryReport, CoreError>`

应用启动必调。清 staging、回滚未完成事务。

```rust
pub struct RecoveryReport {
    pub cleaned_staging_files: i64,
    pub reverted_staging_db_rows: i64,
    pub warnings: Vec<String>,
}
```

### `reindex_from_filesystem(repo) -> Result<ReindexReport, CoreError>`

扫描整个资料库，比对 DB，inserted/updated/skipped。耗时与文件数成正比。

```rust
pub struct ReindexReport {
    pub inserted: i64,
    pub updated: i64,
    pub skipped: i64,
    pub errors: Vec<String>,
}
```

---

## classify

### `predict_category(repo, filename) -> Result<ClassifyResult, CoreError>`

无 IO 副作用，只返回预测。UI 拖入后调用以填充 ImportSheet。

```rust
pub struct ClassifyResult {
    pub category: String,
    pub suggested_name: String,
    pub reason: ClassifyReason,  // Keyword | Extension | AiPredicted | Default
    pub confidence: f32,
}
```

详见 [../modules/classify.md](../modules/classify.md)。

---

## storage

### `import_file(repo, source_path, options) -> Result<FileEntry, CoreError>`

参数：

```rust
pub struct ImportOptions {
    pub mode: StorageMode,                       // Moved | Copied | Indexed
    pub override_category: Option<String>,
    pub override_filename: Option<String>,
    pub duplicate_strategy: DuplicateStrategy,   // Skip | Overwrite | KeepBoth | Ask
}
```

返回 active 状态的 `FileEntry`。

可能抛：`Io` / `Db` / `DuplicateFile` / `Conflict` / `InvalidPath` / `ICloudPlaceholder` / `Internal`。

### `delete_file(repo, file_id, hard: bool) -> Result<(), CoreError>`

`hard=false` → 软删除 + 移到废纸篓。
`hard=true` → 硬删除（物理删除）。

### `rename_file(repo, file_id, new_name) -> Result<FileEntry, CoreError>`

仅改文件名，不改分类。

### `move_to_category(repo, file_id, new_category) -> Result<FileEntry, CoreError>`

跨分类移动。`new_category` 必须在 classifier.yaml 中存在。

### `restore_file(repo, file_id) -> Result<FileEntry, CoreError>`

恢复软删除的文件。如果 FS 中文件被废纸篓清空，返回 `FileNotFound`。

---

## query

### `list_files(repo, filter) -> Result<Vec<FileEntry>, CoreError>`

```rust
pub struct FileFilter {
    pub category: Option<String>,
    pub include_deleted: Option<bool>,
    pub imported_after: Option<i64>,
    pub imported_before: Option<i64>,
    pub limit: i64,    // 默认 200
    pub offset: i64,
}
```

返回按 `imported_at DESC` 排序的列表。

### `get_file(repo, file_id) -> Result<FileEntry, CoreError>`

```rust
pub struct FileEntry {
    pub id: i64,
    pub path: String,
    pub original_name: String,
    pub current_name: String,
    pub category: String,
    pub size_bytes: i64,
    pub hash_sha256: String,
    pub storage_mode: StorageMode,
    pub source_path: Option<String>,
    pub imported_at: i64,
    pub updated_at: i64,
}
```

### `list_changes(repo, filter) -> Result<Vec<ChangeLogEntry>, CoreError>`

详见 [../modules/change-log.md](../modules/change-log.md)。

### `list_tree_json(repo, locale) -> Result<String, CoreError>`

返回 JSON 字符串（避免大 sequence 跨 FFI 多次拷贝）。Swift 用 `JSONDecoder` 解析。

详见 [../modules/tree-scan.md](../modules/tree-scan.md)。

---

## note

### `read_note(repo, file_id) -> Result<Option<String>, CoreError>`

返回 markdown 内容，无笔记时返回 None。

### `write_note(repo, file_id, content_md: String) -> Result<(), CoreError>`

同时写：
- DB `notes` 表
- 物理文件 `<filename>.md`（与文件同目录）

通过 InFlightTracker 标记防 watcher 循环（Swift 侧负责）。

---

## sync

### `sync_external_changes(repo, events: Vec<ExternalEvent>) -> Result<SyncResult, CoreError>`

```rust
pub struct ExternalEvent {
    pub path: String,           // 资料库相对路径
    pub kind: ExternalEventKind, // Created | Removed | Modified | Renamed
    pub fs_event_id: i64,
}

pub struct SyncResult {
    pub detected_creates: i64,
    pub detected_renames: i64,
    pub detected_deletes: i64,
    pub detected_modifies: i64,
    pub errors: Vec<String>,
}
```

详见 [../architecture/source-of-truth.md](../architecture/source-of-truth.md)。

### `get_fs_event_cursor(repo) -> Result<Option<i64>, CoreError>`

返回上次保存的 event id，None 表示首次启动。

### `set_fs_event_cursor(repo, last_event_id: i64) -> Result<(), CoreError>`

调用方在每批 sync 完成后保存 cursor，断电后下次启动差量重放。

---

## 类型一览表

```
StorageMode         { Moved, Copied, Indexed }
DuplicateStrategy   { Skip, Overwrite, KeepBoth, Ask }
ClassifyReason      { Keyword, Extension, AiPredicted, Default }
ChangeAction        { Imported, Renamed, Moved, EditedNote, Deleted, Restored, ExternalModified }
ExternalEventKind   { Created, Removed, Modified, Renamed }
NodeKind            { Category, Subdir }
```

---

## 错误体系

详见 [error-codes.md](error-codes.md)。

---

## 调用规范

### Swift 侧封装（CoreBridge）

UI 不直接调 `area_matrix.*`，而是通过 `CoreBridge` 包装：

```swift
@MainActor
public final class CoreBridge {
    public func importFile(from src: URL, options: ImportOptions) async throws -> FileEntry
    public func listFiles(filter: FileFilter) async throws -> [FileEntry]
    // ...
}
```

理由见 [../architecture/ffi-design.md#corebridge-包装](../architecture/ffi-design.md)。

### 不要在主线程调耗时函数

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
- 单条 `list_files`

---

## 版本演进

| 版本 | 变化 |
|---|---|
| 0.1.x | MVP 接口，可能多次微调 |
| 0.2.x | 加 search、batch_import、undo |
| 0.3.x | 加 ai_predict、auto_naming |
| 1.0.0 | 接口稳定承诺生效 |

---

## Related

- [error-codes.md](error-codes.md)
- [classifier-yaml.md](classifier-yaml.md)
- [../architecture/ffi-design.md](../architecture/ffi-design.md)
- [../modules/storage.md](../modules/storage.md)
- [../modules/classify.md](../modules/classify.md)
- [../modules/change-log.md](../modules/change-log.md)
