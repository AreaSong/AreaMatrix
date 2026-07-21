# 改动日志

> 记录 AreaMatrix `change_log` 的真实 action、transaction 语义和查询边界。
>
> 阅读时长：约 5 分钟。

---

## 定位

改动日志保存在 `.areamatrix/index.db` 的 `change_log` 表中。当前没有独立
`core/src/change_log/` 模块；查询实现在 `core/src/db/change_log.rs`，各 mutation 在自己的 DB 模块中
写入日志。

## Action

DB CHECK 允许以下字符串：

| Action | 语义 |
|---|---|
| `imported` | Copy/Move/Indexed 导入成功 |
| `adopted` | 接管已有文件并登记 |
| `renamed` | AreaMatrix 或外部 rename 已确认 |
| `moved` | 分类移动或 category metadata 更新 |
| `edited_note` | note sidecar 与 DB 同步成功 |
| `deleted` | repo-owned 文件进入删除/Trash 状态，或外部文件消失 |
| `removed_from_index` | Indexed entry 从索引移除 |
| `restored` | token 化 Undo 恢复 |
| `external_modified` | 外部 create/modify、tag 等 metadata 变化 |

`action` 在 Rust DTO 中是 `String`，不是独立 `ChangeAction` enum。新增 action 必须同时修改 schema CHECK、
写入方、Core API、UDL 消费假设和测试。

## Transaction 语义

关键 mutation 把 metadata 和 change log 放在同一 SQLite transaction：

- import promotion：active row + `imported`
- rename：files + `renamed` + undo metadata
- category move：files + `moved` + undo metadata
- delete：files + `deleted`/`removed_from_index` + undo metadata
- note：notes row + `edited_note`
- adopt/reindex：files + 对应 log
- external sync：整批 files + change log

因此日志写失败会使对应 DB transaction 失败。它不是“仅 warning、不阻断主操作”的旁路日志。文件系统
已经发生变化的操作必须由外层 guard/rollback 恢复，不能通过忽略日志错误留下 FS/DB 分叉。

## detail_json

`detail_json` 必须是 JSON object。内容由 action owner 定义，例如 rename 的 from/to path、external create 的
`kind=create`、note 的 length before/after。

敏感原则：

- 不记录文件正文、note 正文或 AI secret。
- Indexed 路径等用户数据只在完成产品行为所需范围内持久化。
- 对外 diagnostics 不应直接导出未经脱敏的完整 change log。

## 查询

`list_changes(repoPath, filter)` 支持：

- `file_id`
- `category`
- 精确 `action`
- `since` / `until`
- `limit` / `offset`

排序为 `occurred_at DESC, id DESC`。limit 小于等于 0 时使用 100，上限 1000。读取时如果
`detail_json` 不是 JSON object，返回 DB error。

`occurred_at` 使用秒级时间，不提供跨设备或跨数据库的严格单调保证。

## 保留与归档

当前没有 change-log GC、retention timer、JSONL archive writer 或
`.areamatrix/archives/changes-*.jsonl` 合同。`archives/` 被其他可恢复文件操作使用，不表示 change log 会
自动迁出 SQLite。

在新增保留策略前，必须明确用户可见历史、Undo/Redo、审计、隐私、备份和 schema migration 影响。

## 验证

- mutation 成功时 metadata 与 log 同时存在。
- 注入 log 写失败时 transaction 回滚。
- external create/modify 使用 `external_modified`，rename 使用 `renamed`。
- filter、pagination、非法 JSON 和时间范围错误均有覆盖。
- 日志失败后的文件系统补偿满足用户文件不变量。

## Related

- [../architecture/data-model.md](../architecture/data-model.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../api/core-api.md](../api/core-api.md)
- [storage.md](storage.md)
