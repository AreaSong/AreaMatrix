# C1-18 sync-external-renamed

## 服务的 UX 页面

- S1-09 main-list
- S1-13 detail-log

## Core API

- `sync_external_changes(repo_path, events)`

## 输入

- `ExternalEvent { kind: Renamed, path, fs_event_id }`
- 可能需要 app 层合并 old/new path。

## 输出

- `SyncResult.detected_renames`

## DB 变化

- 更新 `files.path`、`files.current_name`、`updated_at`。
- 写入 `change_log.renamed`。

## 文件系统变化

- 只读确认新路径存在。
- 不主动重命名用户文件。

## 错误码

- `FileNotFound`
- `Conflict`
- `Db`
- `Io`

## 验收标准

- 外部 rename 后列表和详情显示新名称。
- change log 保留 old/new path。
- 无法配对 rename 时可降级为 removed + created。

## 延后范围

- 跨目录复杂 rename 配对优化属于 Stage 2。
