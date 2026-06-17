# C2-18 redo-action-log

## 服务的 UX 页面

- S2-22 redo

## Core API

- 计划新增：`list_redo_actions`、`redo_action(repo_path, action_id)`

## 输入

- action_id。

## 输出

- Redo 可用性、执行结果、刷新建议和失败原因。

## DB 变化

- 更新 undo/redo action 状态。
- 写入 redo 对应 change log。

## 文件系统变化

- 取决于被恢复动作；必须使用原 action 的安全执行路径。

## 错误码

- `Conflict`
- `FileNotFound`
- `PermissionDenied`
- `ExpiredAction`
- `Db`
- `Io`

## 验收标准

- 只有 AreaMatrix 成功 Undo 的动作可以 Redo。
- 新写操作会清空 redo stack。
- Redo 失败不破坏当前文件系统和 DB 状态。

## 延后范围

- 多设备协同 redo 属于 Stage 4+。

