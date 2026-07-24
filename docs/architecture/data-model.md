# 数据模型

> 记录 AreaMatrix 当前 SQLite 元数据、文件系统数据和按功能创建的扩展表。
>
> 阅读时长：约 8 分钟。

---

## 存储边界

| 数据 | 位置 | 权威边界 |
|---|---|---|
| 用户文件 | 用户选择的资料库目录或 Indexed 外部路径 | 文件系统 |
| 核心元数据 | `<repo>/.areamatrix/index.db` | SQLite |
| SQLite WAL/SHM | `<repo>/.areamatrix/index.db-{wal,shm}` | SQLite 运行状态 |
| 配置 | `repo_config` 及 `.areamatrix/*.yaml` | 按配置类型分域 |
| 导入暂存 | `<repo>/.areamatrix/staging/` | AreaMatrix-owned、可恢复的 Copy/Move 中间态 |
| 笔记 sidecar | `<filename>.md` | 与 `notes` 表保持一致合同 |
| 自动概览 | `.areamatrix/generated/` | DB/文件状态派生 |
| diagnostics snapshot | `.areamatrix/diagnostics/` | AreaMatrix-owned 恢复材料 |

`archives/` 可被可恢复文件操作使用，但当前 change log 不归档为 JSONL。仓库没有“每次启动保留 5 份
数据库备份”的行为。

## Schema version 3 初始表

新资料库由 `core/src/db/schema.rs::INITIAL_SCHEMA` 创建核心表，并以 schema version 3 标记；v2 资料库通过
编号 migration 补齐同一合同。核心表包括：

| 表 | 用途 |
|---|---|
| `schema_version` | schema 版本与应用时间 |
| `files` | 文件索引、hash、路径、来源、storage mode 和生命周期状态 |
| `change_log` | 可查询的文件和元数据变更历史 |
| `notes` | 笔记 Markdown 内容 |
| `tags` | 文件标签多值关系 |
| `undo_actions` | token 化 Undo 状态和 inverse payload |
| `fs_event_cursor` | FSEvents 已确认的单调 cursor |
| `external_sync_receipts` | 外部同步事件的幂等回执，`(event_id, kind, path)` 主键 |
| `scan_sessions` | adopt/reindex 进度、计数和错误 |
| `repo_config` | 资料库级 key/value 配置 |
| `repo_config_revision` | Repository 设置 CAS 的单调 revision |
| `saved_searches` | 保存的搜索条件和侧边栏状态 |
| `recoverable_operations` | 可恢复 operation identity、冻结上下文、状态与内部 run sequence |
| `overview_regeneration_items` | 全库概览事务的目标、旧/新 hash、staging 与应用状态 |
| `overview_provenance` | 当前生效 overview 的 locale、operation、format、revision 与 hash |

`external_sync_receipts`、operation context 和 AI provenance 不能只在普通业务调用中按需创建；v3 migration
必须把其结构和约束纳入可审计的 schema transaction。

### files

`files` 的关键字段：

- `path`：唯一路径；repo-owned 为相对路径，Indexed 可为外部绝对路径。
- `original_name` / `current_name`：导入原名和当前显示/物理名称。
- `category`：分类 slug。
- `size_bytes` / `hash_sha256`：最近一次已确认快照。
- `storage_mode`：`moved`、`copied`、`indexed`。
- `origin`：`imported`、`adopted`、`external`。
- `status`：`staging`、`active`、`deleted`。
- `source_path`：导入来源或 Indexed 外部路径。
- `deleted_at`：soft-delete 时间。

active category、active hash、status 和 imported time 都有索引。外部 deleted path 再次出现时可复用原 row
并恢复为 active。

`staging` row 不进入普通文件列表、overview 或 command index 等用户消费面。即使 `list_files` 使用
`include_deleted = true`，查询仍排除 `status = staging`，不会暴露尚未提交的导入。

### 关系与删除语义

| 关系 | 删除语义 |
|---|---|
| `change_log.file_id -> files.id` | `ON DELETE SET NULL`，保留历史记录 |
| `notes.file_id -> files.id` | `ON DELETE CASCADE` |
| `tags.file_id -> files.id` | `ON DELETE CASCADE` |

`tags` 使用 `(file_id, tag)` 复合主键，保证同一文件不会保存重复标签。

### change_log

`action` 由 DB CHECK 限制为：

```text
imported, adopted, renamed, moved, edited_note,
deleted, removed_from_index, restored, external_modified
```

`detail_json` 必须是 JSON object。关键 mutation 把 metadata 与 change log 放在同一 transaction 中；日志
写失败会使对应 metadata transaction 失败。

### fs_event_cursor

表只允许 `id = 1`，保存 `last_event_id` 和 `updated_at`。写入使用单调最大值，不能让 cursor 回退。

### scan_sessions

记录 adopt/reindex 的 `running/completed/paused/failed/interrupted` 状态，以及 inserted、updated、missing、
conflicts、unreadable、unknown、skipped 和 errors。需要恢复生成上下文的 session 通过可空 `operation_id`
引用 `recoverable_operations`；旧 session 缺少上下文时不得从当前语言设置补猜。

### recoverable_operations

每个用户触发的 attempt 对应一行，关键字段为：

- `operation_id`：UUID 文本主键；resume/replay/rollback 保持不变。
- `retry_of_operation_id`：显式 Retry 创建新 operation 时关联前一次；不用于 continuation。
- `operation_code`：稳定英文能力代码。
- `operation_payload_json`：按 operation schema 编码的规范 JSON，只保存恢复必需的 options 和稳定标识。
- `content_locale`：可空 concrete `zh-Hans` / `en`；不生成自然语言的 operation 可以为空。
- `repository_revision`、`format_contract_version`、`target_set_hash`：冻结的 CAS 与确定性输入。
- `status`：`running`、`staging`、`ready_to_commit`、`committing`、`completed`、
  `rollback_required`、`rolled_back` 或 `failed`。
- `run_sequence`：同一 operation 内部重新进入执行时递增；不是新的公开 identity。
- `created_at`、`updated_at`、`finished_at`：UTC Unix seconds。

表中不得保存 API key、完整 prompt，或仅为恢复而复制可从资料库安全重建的用户正文。远程调用使用单独
`call_id`/call log 追踪，但仍引用同一 `operation_id`。

### overview regeneration journal

`overview_regeneration_items` 以 `(operation_id, relative_path)` 为主键。`relative_path` 必须是允许的 generated
目标或根 `AREAMATRIX.md`，不得出现 `README.md`、绝对路径和 `..`。每项记录 target kind、旧文件是否存在、
旧/新 SHA-256、AreaMatrix-owned staging/backup 相对路径，以及 `planned/staged/applied/restored` 状态。

`overview_provenance` 只描述当前生效输出，保存 relative path、operation ID、content locale、format contract
version、repository revision、content hash 和 UTC generation time。事务完成后 provenance 与生效字节一致；
回滚恢复旧 provenance。journal 未收敛前 Repository 不接受新的普通写入。

## 按功能创建的扩展表

以下表在相应能力首次写入或检查 schema 时创建，不属于 `INITIAL_SCHEMA`：

| 表 | Owner |
|---|---|
| `ai_call_log` | AI 调用审计 |
| `ai_summaries` | AI 摘要正文、ownership、content revision 与生成 provenance |
| `ai_summary_revisions` | 每文件单调 content revision tombstone，清除后仍阻止旧草稿覆盖 |
| `import_sessions` | 导入冲突 review session |
| `import_conflicts` | 逐项导入冲突状态 |
| `semantic_index_entries` | 本地语义索引 metadata |

部分扩展表仍可按能力首次使用创建，但 v3 需要在第一次写入前完成其必要 provenance 列和约束。因此
`schema_version = 3` 表示核心 schema 和本版本数据安全边界已经满足，不代表所有功能都已运行过。

### `ai_summaries`

每个 file 只保存一行当前摘要。除正文和原有 route/model/context 审计字段外，稳定合同包括：

- `ownership`：`generated` 或 `user_owned`；接受但未编辑的摘要保持 `generated`，用户编辑后变为
  `user_owned`。
- `content_revision`：从 1 开始单调递增；保存和清除必须比较调用方的 expected revision。
- `operation_id`、`content_locale`、`format_contract_version`：生成来源；用户编辑后仍保留原生成来源。
- `generated_at`、`saved_at`：UTC Unix seconds。

保存 generated 结果也必须是显式动作。替换 `user_owned` 行需要专门确认位，任何 stale revision 或缺少确认
都零写入失败。`ai_summary_revisions` 在 clear 后保留最后 revision，使旧 expected=0 或旧窗口草稿不能在
删除后重新覆盖；摘要正文行可以删除，但 revision tombstone 继续存在。旧 `edited_by_user` 只用于 migration
推导 ownership，不再作为公开所有权合同。

### `ai_call_log`

`ai_call_log` 由 AI producer 首次成功写入审计记录时，在同一 SQLite transaction 中按需创建，不属于
`INITIAL_SCHEMA`。表不存在时，`list_ai_calls` 返回空页，`clear_ai_call_log` 返回 zero-count report；读取和
空清理不会仅为查询创建该表。

稳定 schema 语义：

- 基础列为 `id`、`feature`、`file_id`、`route`、`provider`、`model`、`status`、
  `sent_fields_json`、`privacy_rule_id`、`result_summary`、`error_code` 和 `occurred_at`；基础列缺失时读取和
  清理返回 DB error。
- `status` 只允许 `success`、`failed`、`skipped`、`unavailable`。
- `file_id` 可为空，并以 `ON DELETE SET NULL` 引用 `files.id`；删除文件 row 后保留审计记录，但解除文件关联。
- `privacy_rules_checked` 只允许 `0` 或 `1`，由 producer 显式写入：进入 privacy gate 并完成评估时为 `1`，
  即使没有命中任何规则；在 gate 之前因 AI/feature disabled 退出时为 `0`。它不能从
  `privacy_rule_id` 是否为空推断。
- `privacy_rule_id` 只记录命中的规则。旧表补列时，非空 rule id 可确定回填 checked=`1`；rule id 为空的
  历史行无法证明是否评估过，只能保守回填 `0`。这表示“未记录/未证明”，不表示当时一定绕过规则。
- `sent_fields_json` 保存字段类别标识，不保存字段正文；公开读取仍对显示文本执行脱敏。
- `batch_id`、`scope`、`duration_ms`、`privacy_rules_checked`、`privacy_rule_name` 和
  `matched_field_type` 是兼容补列。旧表缺列时读取使用 `NULL` 或可推导 fallback，下一次成功写入在 transaction
  内补齐。
- 查询索引分别按 `occurred_at DESC` 和 `(feature, occurred_at DESC)` 排序；索引名称属于实现细节。
- API 返回的 90 天 retention 是应用策略，schema 没有自动过期 trigger。删除只通过
  `clear_ai_call_log` 的 `All`、`SelectedEntries` 或 `OlderThan` scope 执行。

## 连接与一致性

可写连接配置：

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 268435456;
PRAGMA cache_size = -65536;
PRAGMA busy_timeout = 5000;
```

只读连接使用 `SQLITE_OPEN_READ_ONLY` 和 `query_only = ON`。平台 metadata reader 不得用可写 fallback
创建或修改 DB。

关键一致性边界：

- 文件操作与 DB 无法组成单一 transaction，使用 staging、短 DB transaction 和补偿 guard。
- note sidecar 与 `notes` row 不一致时，read/write 返回错误而不是静默覆盖。
- external sync 的 files/change_log 在一个 transaction 中提交，overview 和 cursor 随后执行。
- overview regeneration 使用 DB journal + AreaMatrix-owned staging/backup 做补偿式事务；文件系统崩溃窗口
  可能短暂存在中间字节，但打开 Repository 时必须先恢复到全旧或全新稳定状态。
- diagnostics/repair 使用独立 snapshot 和 replacement DB，不把用户文件纳入备份。

## 迁移与恢复

当前核心版本为 3。v2→v3 迁移前执行 WAL checkpoint 并创建新的、不覆盖已有文件的编号备份；完整规则见
[migration.md](migration.md)。迁移失败必须保持 v2 数据库原样可恢复。

删除 `.areamatrix/` 不删除用户文件，但会丢失不能从文件系统重建的 tags、notes、history、saved searches
和配置。

## Related

- [migration.md](migration.md)
- [source-of-truth.md](source-of-truth.md)
- [transactional-import.md](transactional-import.md)
- [../modules/change-log.md](../modules/change-log.md)
- [../api/core-api.md](../api/core-api.md)
