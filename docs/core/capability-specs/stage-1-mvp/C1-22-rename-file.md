# C1-22 rename-file

## 服务的 UX 页面

- S1-33 file-rename-sheet
- S1-09 main-list
- S1-12 detail-meta

## Core API

- `rename_file(repo_path, file_id, new_name) -> FileEntry`

## 输入

- `repo_path`
- `file_id`
- `new_name`

## 输出

- 更新后的 `FileEntry`。

## DB 变化

- 更新 `files.current_name`、`files.path`、`updated_at`。
- 写入 `change_log.renamed`，记录旧名和新名。

## 文件系统变化

- Copy / Move 文件在资料库内执行安全 rename。
- Indexed 文件只更新索引显示名，不移动外部源文件。
- 不覆盖同目录已有文件。

## 错误码

- `InvalidPath`
- `Conflict`
- `FileNotFound`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 重命名不改变 `file_id`、分类、标签、笔记。
- 空名、非法字符、同名冲突都有测试。
- Cancel 属于 UI 行为，Core 不应在未调用时产生副作用。

## 延后范围

- 批量重命名属于 Stage 2 的 C2-11。
