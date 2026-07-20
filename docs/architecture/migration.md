# 数据库迁移

> 记录 AreaMatrix 当前 SQLite schema 版本、自动升级、备份和失败恢复边界。
>
> 阅读时长：约 5 分钟。

---

## 当前版本

当前 `LATEST_SCHEMA_VERSION` 为 `2`，定义在 `core/src/db/schema.rs`。新资料库直接执行内嵌的
`INITIAL_SCHEMA` 并写入 schema version 2，不经过独立 SQL migration 文件。

每次打开可写连接时，`open_repo_connection` 会先配置 WAL、foreign keys、busy timeout 等 SQLite
参数，再调用 `run_schema_migrations`。只读连接不执行迁移。

## 当前升级路径

当前自动升级只处理旧资料库的 `scan_sessions` 表缺少以下列的情况：

- `missing`
- `conflicts`
- `unreadable`
- `unknown`

升级顺序：

1. 读取 `schema_version` 和 `scan_sessions` 的实际列。
2. 已达到 version 2 且列完整时直接返回。
3. 执行 `PRAGMA wal_checkpoint(FULL)`。
4. 创建一次性 `.areamatrix/index.db.pre-v2.bak`；文件已存在时不覆盖。
5. 在一个 SQLite transaction 中补齐缺失列。
6. 写入 schema version 2 并提交。

仓库当前没有 `core/src/db/migrations/` 目录、SQL migration 文件序列或 `MIGRATIONS` 数组。新增
schema 版本时，应先在本文件定义兼容性、备份和恢复边界，再扩展 `schema.rs` 及测试。

## 备份与失败语义

- WAL checkpoint 失败：不进入 schema transaction。
- 备份失败：不进入 schema transaction。
- `ALTER TABLE` 或 version 写入失败：transaction 回滚，原 DB 和 `.pre-v2.bak` 保留。
- `.pre-v2.bak` 是迁移前保护副本，不是自动轮转备份，也不会在每次启动创建。
- 当前没有公开 `rollback_to`、schema downgrade 或 migration progress API。

不能通过重命名备份文件或直接编辑 `schema_version` 冒充应用内回滚。人工恢复必须先退出应用，保留
原 DB、WAL、SHM 和备份副本，并在恢复后执行完整性检查和受控 reindex。

## Repair 与 migration 的区别

`repair_metadata` 负责损坏诊断和元数据重建，不是 schema rollback：

- 可先把 `index.db` 及存在的 WAL/SHM 复制到 `.areamatrix/diagnostics/`。
- 使用 `PRAGMA integrity_check` 和 foreign-key check 判断元数据健康。
- full rescan 需要重建 DB 时，先创建临时 replacement DB；安装失败会恢复旧 DB。
- reindex 只重建可由文件系统推导的索引，不能恢复标签、历史或其他仅存在于 DB 的元数据。

## Schema 变更要求

新增版本必须同时具备：

- 明确的旧版本输入和目标版本。
- migration 前 WAL 处理和不会覆盖的备份路径。
- transaction 内的 schema 变更。
- 失败后 DB、WAL、SHM 和用户文件状态说明。
- 新库、旧库升级、重复执行、失败回滚和损坏输入测试。
- `docs/architecture/data-model.md`、Core API、UDL 和平台桥接同步评估。

迁移不得移动、删除、重命名或覆盖资料库中的用户文件。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace
```

涉及 repair/reindex 时，还应覆盖 diagnostics snapshot、DB install failure、用户文件不变和重复运行。

## Related

- [data-model.md](data-model.md)
- [transactional-import.md](transactional-import.md)
- [source-of-truth.md](source-of-truth.md)
- [../development/recovery.md](../development/recovery.md)
- [../api/core-api.md](../api/core-api.md)
