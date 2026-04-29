# C4-16 sync-conflict-resolve

## 服务的 UX 页面

- S4-X-01 sync-conflict
- S4-X-09 replace-confirm

## Core API

- 计划新增：`preview_sync_conflict_resolution`、`resolve_sync_conflict`

## 输入

- conflict_id、resolution。

## 输出

- 预览和解决报告。

## DB 变化

- 更新 conflict state。
- 写 change log。

## 文件系统变化

- 默认保留版本；丢弃版本进入 Trash。
- Replace 必须二次确认。

## 错误码

- `Conflict`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- Resolve 失败保持 unresolved。
- 不自动删除任何版本。
- Replace 必须经过 S4-X-09。

## 延后范围

- 自动合并内容不在当前 Stage 4。
