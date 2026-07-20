# 存储模块

> 记录 AreaMatrix 当前文件导入、重命名、移动、删除和恢复实现边界。
>
> 阅读时长：约 7 分钟。

---

## 模块布局

`core/src/storage/` 当前包含：

```text
storage/
├── dedup.rs
├── delete.rs
├── destination.rs
├── hash.rs
├── history.rs
├── import.rs
├── import/import_detail.rs
├── import_source_removal.rs
├── import_target.rs
├── move_to_category/
├── rename.rs
├── replacement_trash.rs
├── safe_move.rs
├── staging_row.rs
└── validate.rs
```

内部 facade 是 `core/src/storage/mod.rs`。公开 FFI 门面位于
`core/src/api/file_actions.rs`；startup recovery 位于 `core/src/recovery.rs`；reindex/repair 位于
`core/src/repair.rs` 和 `core/src/repo_scan/**`。

仓库没有 `storage/ops.rs`、`storage/recovery.rs` 或 `storage/reindex.rs`。

## Storage mode

| Mode | 资料库内文件 | 源文件 | DB path |
|---|---|---|---|
| `Copied` | 创建 repo-owned 副本 | 保留 | repository-relative |
| `Moved` | 创建 repo-owned 副本 | 最后尝试删除 | repository-relative |
| `Indexed` | 不创建副本 | 保留且不修改 | 外部源路径 |

Move 使用 copy-to-staging、资料库提交、最后删除源文件的顺序。源删除失败返回 `Retained`，不会删除已经
安全提交的资料库文件。

## 公开文件动作

Core API 包括：

- `import_file` / `import_file_with_result`
- `delete_file` / `remove_index_entry`
- `rename_file`
- `preview_move_to_category` / `move_to_category`
- batch category/delete/rename preview 与 apply
- token 化 Undo/Redo
- `recover_on_startup`
- `reindex_from_filesystem` / `repair_metadata`

所有公开行为的输入、输出和副作用以 [Core API](../api/core-api.md) 为准。

## 路径与覆盖保护

- 拒绝空路径、`.`、`..`、路径分隔符和 `.areamatrix` 内部目标。
- repo-owned 文件目标使用 no-replace 语义；同名冲突通过安全编号或显式策略处理。
- Indexed rename 只更新显示名，不重命名外部源文件。
- Indexed category move 只更新 metadata，不移动外部源文件。
- note sidecar 随 repo-owned 文件移动，并在冲突时 fail closed。
- 自动概览默认只写 `.areamatrix/generated/`，不覆盖用户 `README.md`。

## Import 与 duplicate

Copy/Move 使用 staging row 和补偿 guard；Indexed 使用单 transaction active insert。duplicate strategy：

- `Skip` / `Ask`：不修改既有文件。
- `KeepBoth`：解析安全的新目标名。
- `Overwrite`：先把可替换对象置于可恢复边界，再提交新 metadata；失败恢复旧状态。

详细顺序见 [事务式导入](../architecture/transactional-import.md)。

## Delete、Trash 与恢复

- Swift 平台/UI 层负责 Trash availability probe、危险确认和结果呈现，不执行文件 mutation，也不写
  delete metadata、change log 或 Undo。
- repo-owned delete 的实际 Trash mutation 由 Core 执行，并与 DB soft-delete、
  `change_log.action = deleted` 和 token 化 Undo 协作。
- Trash 已发生而 DB/change log/Undo 任一步失败时，Core 的可恢复 guard 必须尝试恢复原 repo 路径并
  回滚本次状态；不得留下无 Undo token 的已删除成功态。
- Indexed remove 只移除索引，不删除外部源文件。
- 支持的恢复入口是 token 化 Undo/Redo，不提供公开 `restore_file`。
- startup recovery 只处理可证明属于 staging 的状态；未知文件、目录和不安全路径保持不动并返回 warning。

删除 `.areamatrix/` 不得导致用户文件丢失，但会删除仅存在于 metadata 的信息。

## Reindex

`reindex_from_filesystem` 由 `repair.rs` 路由到 `repo_scan`：

- 使用 scan session 记录进度和失败状态。
- 读取文件系统、计算 metadata/hash 并 upsert index。
- 不移动、删除、重命名或覆盖用户文件。
- 不能恢复 tags、history、notes DB row 等无法从文件系统推导的数据。

## 验证重点

- Copy/Move/Indexed 的源文件与最终文件状态。
- duplicate 和 name conflict 不覆盖已有文件。
- DB/log/overview/Trash 失败的补偿状态。
- Swift availability probe 与 Core mutation/revalidation 的职责边界。
- note sidecar 与基础文件一起移动或明确失败。
- startup recovery 路径规范化、symlink 和 unknown residue。
- reindex 只改 metadata，不改用户文件。

## Related

- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [../architecture/data-model.md](../architecture/data-model.md)
- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [../development/recovery.md](../development/recovery.md)
- [change-log.md](change-log.md)
