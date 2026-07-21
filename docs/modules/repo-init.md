# 资料库初始化（repo_init）

> 记录空目录创建与已有目录接管（AdoptExisting）的 Core 实现边界。
>
> 阅读时长：约 4 分钟。

---

## 模块布局

实现位于单文件 `core/src/repo_init.rs`。公开 FFI 门面位于 `core/src/api/repository.rs` 的 `init_repo`。

相关依赖：

- `core/src/config/` — 默认 `RepoConfig`
- `core/src/db/` — 初始化 `index.db` 与 schema
- `core/src/overview/` — 生成 `.areamatrix/generated/root.md`
- `core/src/repo_path/` — 路径校验
- `core/src/repo_scan/` — `AdoptExisting` 完成后启动 adopt scan

测试：`core/tests/` 中与 repository init、adopt、path validation 相关的合同与集成测试。

## 初始化模式

| 模式 | 目录要求 | 对用户文件 | 后续动作 |
|---|---|---|---|
| `CreateEmpty` | 空目录或仅系统隐藏项 | 不创建用户内容 | 可选默认分类目录 |
| `AdoptExisting` | 非空、未初始化 | 不移动、不重命名、不删除、不覆盖 | 启动 `scan_sessions(kind=Adopt)` |

两种模式均通过 `.areamatrix.init-<uuid>/` 暂存 metadata，成功后再原子 `rename` 为 `.areamatrix/`；失败且 metadata 未提交时回滚暂存目录。

## Metadata 创建内容

`.areamatrix/` 内创建：

- `staging/`、`archives/`、`generated/`
- 默认 `classifier.yaml`、`ignore.yaml`
- SQLite `index.db`（当前 schema_version = 2）
- `generated/root.md`（默认 overview）

`AdoptExisting` 禁止 `create_default_categories` 与 `overview_output = RootAreaMatrixFile`；接管时不写入根目录 `AREAMATRIX.md`。

## 安全边界

- **不碰用户文件**：接管已有目录时只读枚举，确认存在用户内容条目；不修改任何已有文件或目录名。
- **不覆盖 README**：永不写入或覆盖用户已有 `README.md`；仅当显式选择 `RootAreaMatrixFile` 时在空库创建 `AREAMATRIX.md`。
- **自动生成位置**：overview 默认只写 `.areamatrix/generated/`。
- **路径拒绝**：资料库路径不能为空、不能指向 `.areamatrix/` 内部；不可写目录返回 `PermissionDenied`。
- **Preflight 失败归一**：已初始化、非空（CreateEmpty）、空目录（AdoptExisting）、未完成 scan session 等一律 `Config("configuration error")`。
- **可恢复 init 残留**：仅当目录完全匹配可恢复 init 结构时才清理 `.areamatrix.init-*`；否则 fail closed。
- **平台无关**：Core 不依赖 macOS 专属 API；Trash、书签等平台能力留在 Swift 层。

## 公开 API

- `init_repo(repo_path, options)` — 见 [Core API](../api/core-api.md#init_repopath-string-options-repoinitoptions-throws)

## 验证重点

- CreateEmpty 对非空目录、已初始化目录、不可写路径的拒绝。
- AdoptExisting 不创建分类目录、不写根 `AREAMATRIX.md`、不改动既有文件。
- init 失败时 `.areamatrix.init-*` 回滚，不留半成品 metadata。
- 成功 Adopt 后 adopt scan session 创建且 `FileEntry.origin = .adopted`。
- overview 只出现在 `.areamatrix/generated/`，除非显式 RootAreaMatrixFile。
- symlink、非预期 init 残留目录的 fail closed 行为。

## Related

- [../api/core-api.md](../api/core-api.md)
- [../architecture/adopt-existing-folders.md](../architecture/adopt-existing-folders.md)
- [../adr/0010-adopt-existing-folders-and-overviews.md](../adr/0010-adopt-existing-folders-and-overviews.md)
- [repo-scan.md](repo-scan.md)
- [storage.md](storage.md)
