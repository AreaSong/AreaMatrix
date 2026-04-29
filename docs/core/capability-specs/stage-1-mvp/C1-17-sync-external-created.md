# C1-17 sync-external-created

## 服务的 UX 页面

- S1-09 main-list
- S1-10 main-loading
- S1-13 detail-log

## Core API

- `sync_external_changes(repo_path, events)`
- `get_fs_event_cursor(repo_path)`
- `set_fs_event_cursor(repo_path, last_event_id)`

## 输入

- `ExternalEvent { kind: Created, path, fs_event_id }`

## 输出

- `SyncResult.detected_creates`

## DB 变化

- 新建 `files.origin = External`。
- 写入 `change_log.external_modified` 或更具体动作。
- 更新 `fs_event_cursor`。

## 文件系统变化

- 读取新增文件 metadata/hash。
- 不移动、不覆盖新增文件。

## 错误码

- `InvalidPath`
- `ICloudPlaceholder`
- `Db`
- `Io`

## 验收标准

- 外部新增文件出现在 list/tree/detail。
- `.areamatrix/` 和 generated overview 被跳过。
- cursor 只在事件批次成功处理后推进。

## 延后范围

- FSEvents 启停与去抖属于 macOS app 层。
