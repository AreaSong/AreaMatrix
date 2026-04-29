# C2-09 batch-delete-trash

## 服务的 UX 页面

- S2-13 batch-delete-confirm
- S2-10 undo-toast

## Core API

- 计划新增：`preview_batch_delete`、`batch_delete_to_trash`

## 输入

- file_ids、delete mode。

## 输出

- 预览报告、执行报告、undo token。

## DB 变化

- 软删除 files。
- 写 change log 和 undo action。

## 文件系统变化

- Copy / Move 文件进入 Trash。
- Indexed / Missing 条目只移除索引。
- 不提供永久删除。

## 错误码

- `PermissionDenied`
- `FileNotFound`
- `Io`
- `Db`

## 验收标准

- Trash 不可用时禁用删除。
- 删除前必须确认影响。
- 失败项不被当作成功删除。

## 延后范围

- 永久删除不进入 Stage 2。
