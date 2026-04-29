# C1-23 delete-remove-index

## 服务的 UX 页面

- S1-34 file-delete-confirm
- S1-12 detail-meta
- S1-09 main-list

## Core API

- `delete_file(repo_path, file_id, hard=false)`
- 计划新增：`remove_index_entry(repo_path, file_id)` 或 `delete_file(..., mode=RemoveIndex)`

## 输入

- `repo_path`
- `file_id`
- 删除模式：Move to Trash 或 Remove from Index。

## 输出

- 成功无返回值，调用方刷新 list/detail。

## DB 变化

- `files.status = deleted` 或移除 indexed/missing 记录。
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
