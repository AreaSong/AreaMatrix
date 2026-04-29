# C4-12 platform-watcher-status

## 服务的 UX 页面

- S4-WIN-04 watcher-status
- S4-LNX-04 watcher-status

## Core API

- `sync_external_changes`
- `get_fs_event_cursor`
- `set_fs_event_cursor`
- 计划新增：`record_watcher_health`

## 输入

- platform watcher events 和 health signal。

## 输出

- watcher 状态、last sync、error summary。

## DB 变化

- 更新 cursor 和 watcher health metadata。

## 文件系统变化

- Core 不监听文件系统，只消费平台层事件。

## 错误码

- `Db`
- `Io`

## 验收标准

- Windows/Linux watcher 状态可被 UI 查询。
- 事件失败不推进 cursor。
- 手动 rescan 需进入确认页。

## 延后范围

- Watcher 后台服务安装不在 Core。
