# C1-24 move-to-category

## 服务的 UX 页面

- S1-35 change-category-sheet
- S1-09 main-list
- S1-12 detail-meta

## Core API

- `move_to_category(repo_path, file_id, new_category) -> FileEntry`

## 输入

- `repo_path`
- `file_id`
- `new_category`

## 输出

- 更新后的 `FileEntry`。

## DB 变化

- 更新 `files.category`、`files.path`、`updated_at`。
- 写入 `change_log.moved`。

## 文件系统变化

- Copy / Move 文件移动到目标分类目录。
- 目标同名时按 C1-10 生成安全名称，不覆盖。
- Indexed 文件只更新分类元数据，不移动源文件。

## 错误码

- `Classify`
- `Conflict`
- `FileNotFound`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 移动前能预览最终路径。
- 目标同名不会覆盖目标文件。
- 成功后 Tree/List/Detail 可通过 Core 查询看到新位置。

## 延后范围

- 批量改分类属于 Stage 2 的 C2-09。
