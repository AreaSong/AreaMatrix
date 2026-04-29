# C4-19 manual-rescan

## 服务的 UX 页面

- S4-X-07 rescan-confirm
- S4-WIN-04 watcher-status
- S4-LNX-04 watcher-status

## Core API

- `reindex_from_filesystem`
- `get_latest_scan_session`
- `resume_scan_session`

## 输入

- repo path、rescan scope。

## 输出

- ReindexReport 和 scan session。

## DB 变化

- 写 scan_sessions。
- upsert files metadata。

## 文件系统变化

- 只读扫描 repo。
- 不移动、不删除、不覆盖用户文件。

## 错误码

- `PermissionDenied`
- `Db`
- `Io`

## 验收标准

- 手动 rescan 前必须确认影响。
- 扫描失败可恢复或继续。
- 不覆盖 README 和 generated 边界。

## 延后范围

- 后台定时重扫策略后续拆分。
