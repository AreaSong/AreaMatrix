# 批量删除（batch_delete）

> 记录 batch delete confirmation 的 preview / Apply 与 Trash、索引移除边界。
>
> 阅读时长：约 4 分钟。

---

## 模块布局

`core/src/batch_delete/` 当前包含：

```text
batch_delete/
├── apply.rs
├── inspect.rs
├── plan/
│   └── classify.rs
├── plan.rs
└── token.rs
```

入口与合同类型位于 `core/src/batch_delete.rs`。公开 FFI 门面位于 `core/src/api/batch.rs`。

测试：

- `core/tests/batch_delete_trash_contract_api.rs`
- `core/tests/batch_delete_trash_implementation.rs`
- `core/tests/batch_delete_trash_validation.rs`
- `core/tests/batch_delete_trash_failure_recovery.rs`

## 删除模式

| 模式 | 适用行 | 文件系统 |
|---|---|---|
| `MoveToTrash` | repo-owned active 文件 | Core 移入系统 Trash + soft-delete metadata |
| `RemoveFromIndex` | Indexed 或 Missing 行 | 只移除 metadata，**不** touch 外部源文件 |

Preview 分类：`WillMoveToTrash` / `IndexOnly` / `Missing` / `Skipped` / `Blocked`。

## Preview / Apply 协议

1. `preview_batch_delete(repo, file_ids, delete_mode)` — 只读 impact 表与 `preview_token`。
2. `batch_delete_to_trash(..., preview_token)` — 绑定 preview 状态后执行。

Preview 禁止：Trash 移动、metadata 写入、change_log、undo token、overview 更新、AI/网络调用。

Apply 成功时：per-item 状态、change_log、可用则创建 undo token；Trash 已发生而 DB 失败须尝试恢复 repo 路径（与单文件 delete 相同 guard 语义）。

## 安全边界

- **Indexed 外部源**：`RemoveFromIndex` 不得删除、移动、重命名、覆盖或 Trash 外部源路径。
- **Missing 行**：只能 metadata 移除，不假定文件已不存在而删盘。
- **不覆盖用户 README**：batch 操作不涉及 overview 或 README 写入。
- **路径校验**：拒绝空选择、无效 id、指向 `.areamatrix/` 内的 repo path。
- **Trash 不可用**：repo-owned Trash 行标记 Blocked，Apply 整体 fail closed。
- **Soft-delete retention**：soft-deleted 行由 `recover_on_startup` 在 30 天后 purge metadata；不硬删用户源文件。

Swift 层负责 Trash availability probe 与危险确认；Core 执行实际 Trash mutation 与 DB 协作。

## 公开 API

- `preview_batch_delete(repo, file_ids, delete_mode)`
- `batch_delete_to_trash(repo, file_ids, delete_mode, preview_token)`

详见 [Core API](../api/core-api.md) storage / batch 章节。

## 验证重点

- Preview 零副作用；stale preview_token 返回 Conflict。
- MoveToTrash 与 RemoveFromIndex 按 storage mode 正确分类。
- Trash 成功 + DB 失败的可恢复 rollback。
- undo token 与 affected_file_ids 在部分成功时的报告。
- blocked / skipped 计数与 `can_apply` 一致性。
- 重复 file_id 去重与空选择错误。

## Related

- [../api/core-api.md](../api/core-api.md)
- [storage.md](storage.md)
- [missing-file-recovery.md](missing-file-recovery.md)
- [../development/recovery.md](../development/recovery.md)
- [change-log.md](change-log.md)
