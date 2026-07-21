# 文件系统扫描（repo_scan）

> 记录 adopt 接管扫描、manual rescan preview、全量 reindex 与 scan session 生命周期。
>
> 阅读时长：约 5 分钟。

---

## 模块布局

`core/src/repo_scan/` 当前包含：

```text
repo_scan/
├── files.rs
├── ignore.rs
├── preview.rs
├── report.rs
├── runner.rs
├── session.rs
└── types.rs
```

入口 re-export 位于 `core/src/repo_scan.rs`。公开 FFI 门面位于 `core/src/api/repository.rs`：

- `preview_manual_rescan`
- `reindex_from_filesystem`
- `get_latest_scan_session`
- `resume_scan_session`

`init_repo(AdoptExisting)` 通过 `repo_scan::start_adopt_scan` 触发内部 adopt 扫描。

测试：`core/tests/support/repo_scan_contract_source.rs` 及 reindex / adopt 相关集成测试。

## Scan session 种类

| Kind | 触发 | origin 标记 | track missing |
|---|---|---|---|
| `Adopt` | `init_repo(AdoptExisting)` | `.adopted` | 否 |
| `Reindex` | `reindex_from_filesystem` / repair full rescan | `.external` | 是 |

Session 状态：`Running` / `Paused` / `Interrupted` / `Failed` / `Completed`。`resume_scan_session` 从 `last_path` 续扫；已完成 session 返回空 report。

## 扫描行为

1. 读取 `.areamatrix/ignore.yaml` 并合并默认 ignore。
2. 遍历资料库文件系统（跳过 `.areamatrix/`、`README.md` 作为普通用户文件索引；跳过 `AREAMATRIX.md` 与 generated overview）。
3. 计算 hash 与 metadata，upsert `files` index。
4. Reindex 模式对比 active snapshot，标记 `missing` / `conflicts` / `unreadable` / `unknown` 供 UI Needs Review。

`preview_manual_rescan` 只读：不创建 scan session、不写 DB、不修改用户文件；已有 Running reindex 时返回 `Conflict`。

## 安全边界

- **只读用户文件内容用于索引**：不移动、不重命名、不删除、不覆盖、不 Trash 用户文件。
- **不触发 iCloud 下载**：占位符等不可读项记入 `unreadable` / warning，不主动拉取云端内容。
- **不覆盖 README**：不把 overview 写入用户 `README.md`。
- **只允许写 metadata**：`.areamatrix/index.db` 与 scan session 行；自动生成仍限 `.areamatrix/generated/`。
- **并发互斥**：同一资料库不允许并发 Running reindex session。
- **Core 平台无关**：遍历与 hash 不依赖 macOS 专属 API。

## 公开 API

- `preview_manual_rescan(repo_path)` — 只读预览
- `reindex_from_filesystem(repo_path)` — 全量重建
- `get_latest_scan_session(repo_path)`
- `resume_scan_session(repo_path, scan_session_id)`

详见 [Core API](../api/core-api.md) repository 章节。

## 验证重点

- Adopt 与 Reindex 的 origin 标记差异。
- preview 零副作用；Running session 的 Conflict。
- ignore patterns、symlink、跨文件系统边界。
- Reindex 的 missing / conflict 计数不隐式删除或合并文件。
- resume 幂等 upsert 与 `last_path` 续扫。
- 大库进度更新与 session 终态报告字段。

## Related

- [../api/core-api.md](../api/core-api.md)
- [../architecture/adopt-existing-folders.md](../architecture/adopt-existing-folders.md)
- [../adr/0010-adopt-existing-folders-and-overviews.md](../adr/0010-adopt-existing-folders-and-overviews.md)
- [../adr/0003-source-of-truth-strategy.md](../adr/0003-source-of-truth-strategy.md)
- [repair.md](repair.md)
- [missing-file-recovery.md](missing-file-recovery.md)
- [storage.md](storage.md)
