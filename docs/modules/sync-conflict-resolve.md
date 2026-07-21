# 同步冲突解决（sync_conflict_resolve）

> 记录 external sync 冲突检测后的 preview、Replace 确认与 Apply 边界。
>
> 阅读时长：约 4 分钟。

---

## 模块布局

```text
core/src/sync_conflict_resolve.rs
core/src/sync_conflict_resolve/
├── apply.rs
└── plan.rs
```

冲突检测位于 `core/src/sync_conflict_detect/`（`detect_sync_conflicts`）。公开 FFI 门面位于 `core/src/api/conflicts.rs`。

测试：

- `core/tests/sync_conflict_resolve_contract_api.rs`
- `core/tests/sync_conflict_resolve_implementation.rs`
- `core/tests/sync_conflict_resolve_validation.rs`
- `core/tests/sync_conflict_resolve_failure_recovery.rs`

## 解决策略

| 策略 | 典型效果 |
|---|---|
| `KeepBoth` | 所有版本保持用户可见 |
| `UseExisting` | 保留现有 canonical，incoming 以保留路径可见 |
| `UseIncoming` | incoming 成为 canonical；destructive 时需 Replace 确认 |

Preview 返回 `version_impacts`、`planned_trash_paths`、`replace_plan` 与 `preview_token`。默认安全策略为 `KeepBoth`。

## Preview / Apply 协议

1. `preview_sync_conflict_resolution(repo, conflict_id, resolution)`
2. `resolve_sync_conflict(repo, conflict_id, request)` — `request.preview_token` 必须匹配；destructive 策略需 `replace_confirmed = true`

Apply 写 change_log（`sync_conflict_resolved` / `external_modified` 等），Trash 可用时创建 undo token。

## 安全边界

- **用户文件可见性**：非 canonical 版本优先保留在用户可见位置或 Trash/recovery 边界，而非 silent delete。
- **Replace 二次确认**：`UseIncoming` 等 destructive 路径必须完成 replace confirmation sheet。
- **Trash 门禁**：需要 Trash 而平台不可用时 `can_apply = false`。
- **Stale 状态**：冲突已解决或 preview token 过期返回 `Conflict`。
- **不整库 reindex**：resolution 不调用 `reindex_from_filesystem`；只处理已检测冲突条目。
- **Indexed 外部源**：plan 区分 repo-owned 与 index-only；不移动或删除外部源文件除非策略明确且经确认。
- **Core 平台无关**：Trash 能力探测在 plan 层抽象，不绑定 AppKit。

## 公开 API

- `detect_sync_conflicts(repo)` — 检测入口（只读 DB + FS 对比）
- `preview_sync_conflict_resolution(repo, conflict_id, resolution)`
- `resolve_sync_conflict(repo, conflict_id, request)`

详见 [Core API](../api/core-api.md) sync/conflict 章节。

## 验证重点

- Preview 零 mutation；stale conflict / token 拒绝 Apply。
- KeepBoth 不 Trash 任何用户可见文件。
- UseIncoming Replace 缺确认时被拒。
- Trash 失败 rollback 与 undo token 可用性。
- version_impacts 与最终 `kept_paths` / `trashed_paths` 一致。
- change_log action 与 affected_file_ids 准确。

## Related

- [../api/core-api.md](../api/core-api.md)
- [../adr/0006-icloud-support.md](../adr/0006-icloud-support.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [storage.md](storage.md)
- [change-log.md](change-log.md)
