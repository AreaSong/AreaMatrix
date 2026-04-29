# C2-17 import-conflict-batch

## 服务的 UX 页面

- S2-21 import-conflict-batch

## Core API

- 计划新增：`preview_import_conflict_batch`、`apply_import_conflict_batch`

## 输入

- import_session_id、conflict_ids、批量策略。

## 输出

- 每个冲突项的策略预览、风险说明、执行结果和失败摘要。

## DB 变化

- 写入 import session 决策、file 记录变化、change log 和 undo action。

## 文件系统变化

- 按策略 Skip、Keep both、Replace 或 Ask per item 处理 staged 文件。
- Replace 必须走二次确认和可恢复路径。

## 错误码

- `Conflict`
- `FileNotFound`
- `PermissionDenied`
- `StagingRecoveryRequired`
- `Io`
- `Db`

## 验收标准

- Hash duplicate 默认 Skip，同名不同内容默认 Keep both。
- 批量策略执行前必须预览每一项影响。
- 失败时保留 staged 文件和冲突状态，不覆盖用户文件。

## 延后范围

- 跨设备同步冲突属于 Stage 4。

