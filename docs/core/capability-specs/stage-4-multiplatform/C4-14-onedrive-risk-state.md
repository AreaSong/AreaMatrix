# C4-14 onedrive-risk-state

## 服务的 UX 页面

- S4-WIN-03 onedrive-notice

## Core API

- `detect_cloud_storage_state`

## 输入

- Windows repo path。

## 输出

- OneDrive risk state、placeholder state、recommended action。

## DB 变化

- 可记录用户已确认提示。

## 文件系统变化

- 只读探测。

## 错误码

- `PermissionDenied`
- `Io`

## 验收标准

- 只提示风险，不承诺控制 OneDrive 同步。
- 用户确认状态可持久化。
- 不使用 OneDrive SDK 管理用户文件。

## 延后范围

- 企业 OneDrive 管理集成不在当前 Stage 4。
