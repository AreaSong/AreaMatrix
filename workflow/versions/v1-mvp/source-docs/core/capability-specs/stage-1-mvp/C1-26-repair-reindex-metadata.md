# C1-26 repair-reindex-metadata

## 服务的 UX 页面

- S1-37 db-repair-confirm
- S1-11 main-repo-error
- S1-32 error-recovery

## Core API

- `reindex_from_filesystem(repo_path) -> ReindexReport`
- `create_diagnostics_snapshot(repo_path) -> DiagnosticsSnapshot`
- `repair_metadata(repo_path, options) -> RepairReport`

## 输入

- `repo_path`
- `RepairOptions.full_rescan`
- `RepairOptions.preserve_diagnostics_snapshot`

## 输出

- `ReindexReport.scan_session_id` / `inserted` / `updated` / `skipped` / `errors`
- `DiagnosticsSnapshot.snapshot_path` / `created_at` / `warnings`
- `RepairReport.scan_session_id` / `diagnostics_snapshot_path` / `inserted` / `updated` / `skipped` / `errors`

## DB 变化

- 创建新的可用索引或修复 metadata。
- 保留原损坏状态的诊断快照引用。

## 文件系统变化

- 只处理 `.areamatrix/` 元数据。
- 不移动、不重命名、不删除用户文件。
- 不覆盖 `README.md`。

## 错误码

- `Db`
- `PermissionDenied`
- `Io`
- `Internal`

## 验收标准

- 未确认前不运行修复。
- 修复失败不得删除用户文件，也不得清空诊断信息。
- 成功后可重新加载 Tree/List。

## 延后范围

- 云端备份恢复和自动上传诊断不在 Stage 1。
