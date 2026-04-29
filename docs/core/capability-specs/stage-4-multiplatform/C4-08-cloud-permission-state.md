# C4-08 cloud-permission-state

## 服务的 UX 页面

- S4-IOS-06 icloud-permission
- S4-WIN-03 onedrive-notice

## Core API

- 计划新增：`detect_cloud_storage_state(repo_path) -> CloudStorageState`

## 输入

- repo path。

## 输出

- provider kind、risk、placeholder/permission state。

## DB 变化

- 可记录 last cloud state。

## 文件系统变化

- 只读探测。

## 错误码

- `PermissionDenied`
- `ICloudPlaceholder`
- `Io`

## 验收标准

- iCloud/OneDrive 风险提示来自结构化状态。
- Core 不调用云盘 SDK 管理同步。
- 不建议危险 chmod/sudo 操作。

## 延后范围

- 云盘 SDK 深度集成不在当前 Stage 4。
