# C2-16 icloud-conflict-visual

## 服务的 UX 页面

- S2-20 icloud-conflict-visual
- S1-36 icloud-conflict-list

## Core API

- `list_icloud_conflicts`
- 计划新增：`preview_conflict_versions`、`resolve_icloud_conflict`

## 输入

- conflict_id、resolution。

## 输出

- 版本 metadata、预览摘要、解决报告。

## DB 变化

- 更新 conflict 状态。
- 写 change log。

## 文件系统变化

- 默认 Keep both。
- 丢弃版本必须走 Trash，不直接删除。

## 错误码

- `ICloudPlaceholder`
- `PermissionDenied`
- `Conflict`
- `Io`
- `Db`

## 验收标准

- 冲突解决失败时保持 unresolved。
- 不自动删除任一版本。
- 预览失败不能继续 destructive resolution。

## 延后范围

- 云盘 SDK 深度集成属于 Stage 4+。
