# 缺失文件恢复（missing_file_recovery）

> 记录 Missing 状态查询、relink 与 remove-record 的 Core 合同与文件安全边界。
>
> 阅读时长：约 4 分钟。

---

## 模块布局

```text
core/src/missing_file_recovery.rs      # 合同类型与入口
core/src/missing_file_recovery/
└── filesystem.rs                        # 路径检查、relink candidate 校验
core/src/db/missing_file_recovery.rs   # metadata 读写
```

公开 FFI 门面位于 `core/src/api/queries.rs`：

- `get_missing_file_state`
- `relink_missing_file`
- `remove_missing_file_record`

测试：

- `core/tests/missing_file_recovery_contract_api.rs`
- `core/tests/missing_file_recovery_implementation.rs`
- `core/tests/missing_file_recovery_validation.rs`
- `core/tests/missing_file_recovery_failure_recovery.rs`

## 缺失原因与页面能力

`MissingFileReason` 包括：`PathMissing`、`PermissionDenied`、`CloudPlaceholder`、`ExternalVolumeDisconnected`、`Unknown`。

`get_missing_file_state` 为只读：返回 last known path、hash 期望、确认要求与 rescan 路由状态；不整库扫描、不下载占位符、不删记录。

`can_run_rescan` 默认 false；manual rescan 须经独立确认流程（见 [repo-scan.md](repo-scan.md)）。

## 恢复动作

| 动作 | 前提 | 对用户文件 |
|---|---|---|
| `relink_missing_file` | 用户确认 + 平台 picker 授权路径 | 不删除旧路径；hash 不匹配则保持 Missing |
| `remove_missing_file_record` | 用户显式确认 | **仅**移除 metadata；`file_deleted` 必须为 false |

Relink 成功更新 relative path、hash 匹配字段并写 change_log；失败不 link 不安全候选。

Remove record 写 `removed_from_index` change_log；永不 touch 外部源文件或 Trash。

## 安全边界

- **不删用户文件**：所有 recovery 路径保证 `file_deleted = false`。
- **Indexed 外部源**：remove record 只清索引，不删除外部路径上的文件。
- **Hash 校验**：relink 必须匹配 stored SHA-256，否则返回 `HashMismatch` 状态而非强行关联。
- **确认门禁**：relink 与 remove record 均要求 `confirmed = true`，否则 `PermissionDenied`。
- **不自动 reindex**：本模块不调用 `reindex_from_filesystem`；rescan 由 UI 经 preview + 确认触发。
- **Soft-delete retention**：removed record 与 startup purge（30 天 deleted metadata）是不同路径；purge 不硬删用户源文件。

## 公开 API

- `get_missing_file_state(repo, file_id)`
- `relink_missing_file(repo, request)`
- `remove_missing_file_record(repo, request)`

详见 [Core API](../api/core-api.md) recovery 章节。

## 验证重点

- get 只读；无效 file_id 返回 `FileNotFound`。
- relink hash mismatch 不持久化错误关联。
- remove record 无确认时被拒；DB 失败 rollback soft-delete。
- Cloud placeholder / permission denied 的原因分类。
- repo-owned 与 Indexed storage mode 的路径解析差异。
- change_log action 与 `file_deleted` 不变量。

## Related

- [../api/core-api.md](../api/core-api.md)
- [repo-scan.md](repo-scan.md)
- [storage.md](storage.md)
- [../development/recovery.md](../development/recovery.md)
- [../adr/0006-icloud-support.md](../adr/0006-icloud-support.md)
