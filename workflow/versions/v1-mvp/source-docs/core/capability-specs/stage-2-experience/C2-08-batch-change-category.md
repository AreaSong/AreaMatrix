# C2-08 batch-change-category

## 服务的 UX 页面

- S2-12 batch-change-category
- S2-10 undo-toast

## Core API

- `preview_batch_move_to_category(repo_path, file_ids, target_category, move_repo_owned_files) -> BatchCategoryPreviewReport`
- `batch_move_to_category(repo_path, file_ids, target_category, move_repo_owned_files, preview_token) -> BatchCategoryChangeReport`

## 输入

- file_ids、target_category。

## 输出

- 预览报告、执行报告、undo token。

## DB 变化

- 批量更新 `files.category/path`。
- 写 change log 和 undo action。

## 文件系统变化

- Copy / Move 文件移动到目标目录。
- Indexed 文件只改元数据。

## 错误码

- `Conflict`
- `Classify`
- `FileNotFound`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 执行前必须有目标路径和冲突预览。
- Index-only 不移动源文件。
- 部分失败有摘要，不静默跳过。

## 延后范围

- AI 规则批量重分类属于 C2-14/C2-15 或 Stage 3。
