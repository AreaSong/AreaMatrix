# C1-10 resolve-name-conflict

## 服务的 UX 页面

- S1-23 conflict-name
- S1-24 replace-confirm

## Core API

- `import_file(repo_path, source_path, options)`
- `rename_file(repo_path, file_id, new_name)`

## 输入

- 目标目录。
- 原始文件名或 `override_filename`。

## 输出

- 无冲突的最终文件名。
- 或 `Conflict` / `InvalidPath`。

## DB 变化

- `files.path` 和 `files.current_name` 写入最终无冲突结果。
- `change_log` 记录自动改名或手动改名。

## 文件系统变化

- 同名不同内容默认追加后缀，例如 `name_1.ext`。
- 不覆盖已有用户文件，除非 Replace 二次确认且策略允许。

## 错误码

- `Conflict`
- `InvalidPath`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 同名不同 hash 不覆盖旧文件。
- 自动改名结果在 DB、文件系统、导入结果 UI 中一致。
- Replace 路径必须经过 S1-24，不能从 Core 默认分支直接覆盖。

## 延后范围

- 自定义命名模板和批量重命名属于 Stage 2。
