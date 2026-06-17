# C1-13 list-change-log

## 服务的 UX 页面

- S1-13 detail-log
- S1-21 import-result
- S1-32 error-recovery

## Core API

- `list_changes(repo_path, filter) -> sequence<ChangeLogEntry>`

## 输入

- `ChangeFilter`

## 输出

- 按 `occurred_at DESC` 排序的 change log。

## DB 变化

- 无写入。

## 文件系统变化

- 无。

## 错误码

- `RepoNotInitialized`
- `Db`

## 验收标准

- 支持按 file_id、category、action、时间范围和分页过滤。
- 导入、重命名、移动、笔记编辑、外部变化均能被查询。
- `detail_json` 保持可解析 JSON。

## 延后范围

- Undo 历史和批量撤销属于 Stage 2。
