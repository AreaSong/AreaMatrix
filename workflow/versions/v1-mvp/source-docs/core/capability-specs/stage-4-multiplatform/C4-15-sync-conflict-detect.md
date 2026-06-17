# C4-15 sync-conflict-detect

## 服务的 UX 页面

- S4-X-03 sync-conflict-entry
- S4-X-01 sync-conflict

## Core API

- 计划新增：`detect_sync_conflicts(repo_path) -> sequence<SyncConflict>`

## 输入

- repo path、external events、metadata snapshots。

## 输出

- conflict list、severity、affected files。

## DB 变化

- 写 conflict state metadata。

## 文件系统变化

- 只读探测；不自动解决。

## 错误码

- `Db`
- `Io`
- `Conflict`

## 验收标准

- 冲突入口数量来自 Core 状态。
- 不静默选择任一版本。
- 检测失败不删除文件。

## 延后范围

- 实时协同编辑冲突不在当前 Stage 4。
