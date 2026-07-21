# 导入冲突批量处理（import_conflict_batch）

> 记录 import conflict review surface 的批量预览与 Apply 实现边界。
>
> 阅读时长：约 4 分钟。

---

## 模块布局

`core/src/import_conflict_batch/` 当前包含：

```text
import_conflict_batch/
├── apply/
│   ├── detail.rs
│   ├── execution.rs
│   ├── item.rs
│   ├── replace.rs
│   ├── result.rs
│   └── rollback.rs
├── apply.rs
├── path.rs
├── plan.rs
└── token.rs
```

入口与合同类型位于 `core/src/import_conflict_batch.rs`。公开 FFI 门面位于 `core/src/api/conflicts.rs`。

测试：

- `core/tests/import_conflict_batch_contract_api.rs`
- `core/tests/import_conflict_batch_implementation.rs`
- `core/tests/import_conflict_batch_validation.rs`
- `core/tests/import_conflict_batch_failure_recovery.rs`
- `core/tests/import_conflict_batch_file_safety.rs`

## 冲突类型与策略

| 冲突类型 | 含义 | 可选策略 |
|---|---|---|
| `DuplicateHash` | 与已有文件 hash 相同 | Skip / KeepBoth / Replace / AskPerItem |
| `SameNameDifferentContent` | 同名不同内容 | Skip / KeepBoth / Replace / AskPerItem |

Preview 为只读：不写 `files`、不写 `change_log`、不移动 Trash、不创建 undo token。

Apply 必须绑定 `preview_import_conflict_batch` 返回的 `preview_token`；选择集、策略或 inspected state 变化时返回 `Conflict`。

## 执行语义

- **Skip**：跳过 incoming staged 项，不修改既有 active 文件。
- **KeepBoth**：为 incoming 解析无冲突编号的目标名后导入。
- **Replace**：先把可替换对象置于 Trash / recovery 边界，再提交新 metadata；需二次确认；失败时 rollback。
- **AskPerItem**：路由到单项 import conflict 队列，不在本批完成。

Indexed（仅索引）目标不可 Replace；Trash 不可用时 Replace 行阻塞 Apply。

## 安全边界

- **不覆盖已有文件**：Skip / KeepBoth 不修改既有 active 文件；Replace 走可恢复 Trash 路径。
- **失败不留半成品**：Apply 使用 staging row 与 rollback guard；DB / FS / Trash 任一步失败尝试恢复。
- **成功导入 FS+DB 一致**：最终 active 行与资料库内文件状态对齐。
- **不碰外部源文件**：Indexed 冲突行只更新 metadata，不移动或删除外部源路径。
- **Staging recovery**：存在未修复 staging 残留时返回 `StagingRecoveryRequired`，须先 `recover_on_startup`。
- **自动生成**：不写 `README.md` 或 `.areamatrix/generated/` 以外的用户可见路径。

## 公开 API

- `preview_import_conflict_batch(repo, request)`
- `apply_import_conflict_batch(repo, request, preview_token)`

详见 [Core API](../api/core-api.md) conflict 章节。

## 验证重点

- Preview 零副作用；stale preview_token 拒绝 Apply。
- Replace 二次确认缺失时阻塞；Trash 不可用时的 blocked 行。
- KeepBoth 编号不与已有 repo-owned 路径冲突。
- Apply 部分失败时的 per-item 状态与 rollback。
- duplicate / same-name 策略独立计数与 `apply_to_all_similar_conflicts` 扩展。
- undo token 与 change_log 在成功写入时创建。

## Related

- [../api/core-api.md](../api/core-api.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [storage.md](storage.md)
- [../development/recovery.md](../development/recovery.md)
