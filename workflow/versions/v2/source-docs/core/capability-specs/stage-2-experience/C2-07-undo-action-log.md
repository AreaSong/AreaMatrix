# C2-07 undo-action-log

## 服务的 UX 页面

- S2-10 undo-toast
- S2-11 undo-history

## Core API

- 计划新增：`list_undo_actions`、`undo_action(repo_path, action_id)`

## 输入

- action_id。

## 输出

- Undo 执行结果和刷新建议。

## DB 变化

- 写入 undo action、执行状态和反向 change log。

## 文件系统变化

- 取决于被撤销动作；不得撤销外部 FSEvents 造成的变化。

## 错误码

- `Conflict`
- `FileNotFound`
- `PermissionDenied`
- `Db`
- `Io`

## 验收标准

- 移动、重命名、删除、改分类可生成 undo action。
- 外部变化不可撤销时必须明确显示。
- Undo 失败不破坏当前状态。

## 延后范围

- 多端协同 undo 属于 Stage 4。
