# C1-19 sync-external-removed

## 服务的 UX 页面

- S1-09 main-list
- S1-11 main-repo-error
- S1-13 detail-log

## Core API

- `sync_external_changes(repo_path, events)`

## 输入

- `ExternalEvent { kind: Removed, path, fs_event_id }`

## 输出

- `SyncResult.detected_deletes`

## DB 变化

- 对对应 `files` 标记 `status=deleted` 或等价状态。
- 写入 `change_log.deleted`。

## 文件系统变化

- 只读确认路径缺失。
- 不删除其他文件。

## 错误码

- `FileNotFound`
- `Db`
- `Io`

## 验收标准

- 外部删除后默认列表不再显示该文件。
- Detail 打开已删除 file_id 时给出可理解错误。
- change log 可追溯删除事件。

## 延后范围

- 从 Trash 自动恢复属于 Stage 2+。
