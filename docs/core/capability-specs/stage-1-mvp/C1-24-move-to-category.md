# C1-24 move-to-category

## 服务的 UX 页面

- S1-35 change-category-sheet
- S1-09 main-list
- S1-12 detail-meta

## Core API

- `preview_move_to_category(repo_path, file_id, new_category) -> MoveToCategoryPreview`
- `move_to_category(repo_path, file_id, new_category) -> FileEntry`

## 输入

- `repo_path`
- `file_id`
- `new_category`

## 输出

- `MoveToCategoryPreview`：确认前的最终路径、最终名称、是否自动编号、是否
  Index-only、确认后是否会移动 repo-owned 文件。
- `FileEntry`：确认改分类后更新的文件条目。

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

- 移动前能通过 `preview_move_to_category` 预览最终路径，且 preview 不移动文件、
  不重命名、不删除、不创建分类目录、不写 DB。
- 目标同名不会覆盖目标文件。
- 成功后 Tree/List/Detail 可通过 Core 查询看到新位置。

## 延后范围

- 批量改分类属于 Stage 2 的 C2-09。
