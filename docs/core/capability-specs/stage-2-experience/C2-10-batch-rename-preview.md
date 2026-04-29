# C2-10 batch-rename-preview

## 服务的 UX 页面

- S2-14 batch-rename
- S2-10 undo-toast

## Core API

- 计划新增：`preview_batch_rename`、`batch_rename`

## 输入

- file_ids、命名模板或替换规则。

## 输出

- old/new name 预览、冲突列表、执行报告。

## DB 变化

- 批量更新 `files.current_name/path`。
- 写 change log 和 undo action。

## 文件系统变化

- Copy / Move 文件 rename。
- Indexed 文件只更新显示名。

## 错误码

- `InvalidPath`
- `Conflict`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 预览必须覆盖每个文件。
- 冲突或非法名称不能静默跳过。
- 成功后可 undo。

## 延后范围

- AI 自动命名属于 Stage 3+。
