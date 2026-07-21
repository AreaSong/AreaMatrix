# 元数据修复与诊断（repair）

> 记录 diagnostics snapshot、metadata repair 与全量 rescan 路由边界。
>
> 阅读时长：约 3 分钟。

---

## 模块布局

实现位于单文件 `core/src/repair.rs`。全量 filesystem rescan 路由到 `core/src/repo_scan/`。

公开 FFI 门面位于 `core/src/api/repository.rs`：

- `create_diagnostics_snapshot`
- `repair_metadata`
- `reindex_from_filesystem`（repair 与 advanced settings 共用入口，内部委托 `repo_scan`）

测试：

- `core/tests/repair_reindex_metadata_contract_api.rs`
- `core/tests/repair_reindex_metadata_implementation.rs`
- `core/tests/repair_reindex_metadata_validation.rs`
- `core/tests/repair_reindex_metadata_failure_recovery.rs`
- `core/tests/repair_reindex_metadata_integration_verify.rs`

## Diagnostics snapshot

`create_diagnostics_snapshot` 将 `.areamatrix/index.db`（及可选 `-wal` / `-shm`）复制到 `.areamatrix/diagnostics/index-<timestamp>-<uuid>.db`。

- 只读文件级复制，不打开 SQLite 做 mutation。
- 返回路径必须在 `.areamatrix/` 内；不修改 `files`、`scan_sessions` 或用户文件。
- 不写 `AREAMATRIX.md`、`README.md` 或 `.areamatrix/generated/`。

## repair_metadata 流程

`RepairOptions` 控制行为：

| 选项 | 行为 |
|---|---|
| `preserve_diagnostics_snapshot = true` | 修复前先保留诊断快照 |
| `full_rescan = true` | 必要时重建损坏 DB，再调用 `reindex_from_filesystem` |
| `full_rescan = false` | 仅做 metadata 健康校验，不启动 scan |

`full_rescan = true` 且 DB 损坏时：先（按需）snapshot，再在 `.areamatrix/` 内构建 replacement `index.db`，然后全扫 upsert metadata。

## 安全边界

- **只改 metadata**：不移动、不重命名、不删除、不覆盖用户源文件。
- **诊断保留**：修复失败不得删除已生成的 diagnostics 快照。
- **并发保护**：已有 Running reindex session 时返回 `Conflict`。
- **不能恢复的数据**：reindex 无法从文件系统推导 tags、history、notes 等 DB-only 字段。
- **Soft-delete retention**：过期 deleted metadata 清理由 `recover_on_startup` 负责（30 天），repair 本身不硬删用户文件。

## 公开 API

- `create_diagnostics_snapshot(repo_path)`
- `repair_metadata(repo_path, options)`
- `reindex_from_filesystem(repo_path)` — 详见 [repo-scan.md](repo-scan.md)

## 验证重点

- snapshot 路径始终位于 `.areamatrix/diagnostics/`。
- 损坏 DB + full_rescan 后 Tree/List 可重新加载。
- full_rescan=false 时不创建 scan session、不改 files。
- 并发 Running reindex 的 Conflict。
- repair 失败不删除用户文件或 diagnostics 材料。
- replacement DB 构建失败时的 rollback。

## Related

- [../api/core-api.md](../api/core-api.md)
- [repo-scan.md](repo-scan.md)
- [../architecture/data-model.md](../architecture/data-model.md)
- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [../development/recovery.md](../development/recovery.md)
- [storage.md](storage.md)
