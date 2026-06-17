# C1-23 delete-remove-index

## 服务的 UX 页面

- S1-34 file-delete-confirm
- S1-12 detail-meta
- S1-09 main-list

## Core API

- `delete_file(repo_path, file_id)`
- `remove_index_entry(repo_path, file_id)`

## 输入

- `repo_path`
- `file_id`
- `delete_file`：Move to Trash，仅用于 Copy / Move 等 repo-owned active 条目。
- `remove_index_entry`：Remove from Index，仅移除 Indexed / Missing 等索引条目。

## 输出

- 成功无返回值，调用方刷新 list/detail。

## DB 变化

- `delete_file` 将对应 repo-owned active row 标记为 `files.status = deleted`。
- `remove_index_entry` 移除 indexed/missing 记录或使其不再出现在 list/detail 索引中。
- 写入 `change_log.deleted` 或 `change_log.removed_from_index`。

## 文件系统变化

- Copy / Move 文件删除默认进入系统 Trash。
- Indexed / Missing 条目只移除索引，不删除外部源文件。
- 不提供永久删除。

## 错误码

- `FileNotFound`
- `PermissionDenied`
- `Io`
- `Db`
- `Internal`

## 验收标准

- Delete 必须能证明走 Trash，不直接物理删除。
- Remove from Index 不删除任何用户原文件。
- 失败时不清空笔记、不误删其他文件。

## 延后范围

- 批量删除和 Undo 属于 Stage 2。
