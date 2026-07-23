# 元数据修复与诊断（repair）

> 记录 diagnostics snapshot、metadata repair 与全量 rescan 路由边界。
>
> 阅读时长：约 3 分钟。

---

## 模块布局

实现位于单文件 `core/src/repair.rs`。全量 filesystem rescan 路由到 `core/src/repo_scan/`。

公开 FFI 门面位于 `core/src/api/repository.rs`：

- `create_diagnostics_snapshot`
- `preflight_repair_metadata`
- `repair_metadata`
- `reindex_from_filesystem`（独立入口，内部委托 `repo_scan`）

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

## 只读 preflight

`preflight_repair_metadata` 在任何 repair mutation（修复写入）之前只读检查 `.areamatrix/`、`index.db`、
`repo_config` 与 locale。它不创建 sidecar、不执行 migration、不初始化 metadata，也不写用户文件。

| 状态 | locale 结果 | 选择规则 |
|---|---|---|
| `Healthy` | 返回 DB 中 exact raw policy，包括兼容别名 | 原样保留，不隐式 canonicalize |
| `MetadataAbsent` | 无 policy | 不预选，用户必须明确选择 |
| `DatabaseMissing` | 无 policy | 不预选，用户必须明确选择 |
| `DatabaseCorrupt` | 无 policy | 不预选，用户必须明确选择 |
| `LocaleMissing` | 无 policy | 不预选，用户必须明确选择 |
| `LocaleUnsupported` | 单独返回 exact raw unsupported value | 不预选，用户必须明确选择 |

非 healthy 状态只能选择 canonical `system`、`zh-Hans` 或 `en`。preflight 返回 token，绑定观察到的状态、
raw policy 和必要 metadata identity，供确认后的 mutation 防止以旧观察覆盖新状态。

## repair_metadata 流程

`RepairOptions` 控制行为：

| 选项 | 行为 |
|---|---|
| `preserve_diagnostics_snapshot = true` | 现有 DB 存在时，修复前先保留诊断快照 |
| `preflight_token` | 绑定用户确认前的只读观察 |
| `repository_locale_policy` | healthy 时原样回传 raw policy；其他状态传用户明确选择的 canonical policy |

mutation 前 Core 必须重做 preflight。状态、raw policy 或 token 已变化时返回 `Conflict`，不继续修复；缺少
明确选择或传入非法 policy 时返回 `Config`。repair 不创建额外 locale sidecar。

repair 按 metadata 状态分流：

- `.areamatrix/` 缺失：先在同级临时目录创建 metadata skeleton，再原子安装；不写 generated overview。
- `.areamatrix/` 存在但 `index.db` 缺失：保留孤立 WAL/SHM 诊断材料，原子安装新 DB。
- `index.db` 损坏、locale 缺失或 unsupported：先（按需）snapshot，再构建 replacement DB 并原子替换。
- `index.db` 健康：只验证 metadata；可按用户选择保留诊断快照，不启动其他 operation。

缺失 DB 时没有可复制的旧数据库，因此 `diagnostics_snapshot_path` 可以为空。初始化或重建后的索引为空；
用户确认独立的 rescan 后，`reindex_from_filesystem` 才恢复能从文件系统推导的索引。tags、history、notes
等 DB-only metadata 无法凭空恢复。

## 安全边界

- **只改 metadata**：不移动、不重命名、不删除、不覆盖用户源文件。
- **诊断保留**：修复失败不得删除已生成的 diagnostics 快照。
- **operation 分离**：repair 不读取、创建、恢复或完成 reindex / overview regeneration session。
- **确认时效**：preflight 状态、raw policy 或 token 变化时返回 `Conflict`，旧确认不升级为新授权。
- **locale 权威**：healthy DB 的 exact raw policy 保持不变；缺失或损坏状态只接受用户明确选择的 canonical policy。
- **不能恢复的数据**：reindex 无法从文件系统推导 tags、history、notes 等 DB-only 字段。
- **Soft-delete retention**：过期 deleted metadata 清理由 `recover_on_startup` 负责（30 天），repair 本身不硬删用户文件。

## 公开 API

- `create_diagnostics_snapshot(repo_path)`
- `preflight_repair_metadata(repo_path)`
- `repair_metadata(repo_path, options)`
- `reindex_from_filesystem(repo_path)` — 详见 [repo-scan.md](repo-scan.md)

## 验证重点

- snapshot 路径始终位于 `.areamatrix/diagnostics/`。
- 损坏 DB repair 后 metadata 可打开，但文件索引保持为空，直到独立 reindex 完成。
- repair 始终不创建 scan session、不遍历用户文件、不写 generated overview。
- repair 与并发 Running reindex 各自保持独立 session；平台写协调器负责禁止同库并发 mutation。
- repair 失败不删除用户文件或 diagnostics 材料。
- replacement DB 构建失败时的 rollback。
- 未初始化资料库可在用户确认后创建 metadata DB，并保持用户文件字节不变。
- preflight 无写入副作用，所有非 healthy 状态没有默认 locale 选择。
- healthy raw alias 原样往返；竞态、unsupported 或缺失选择 fail closed。

## Related

- [../api/core-api.md](../api/core-api.md)
- [repo-scan.md](repo-scan.md)
- [../architecture/data-model.md](../architecture/data-model.md)
- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [../development/recovery.md](../development/recovery.md)
- [storage.md](storage.md)
