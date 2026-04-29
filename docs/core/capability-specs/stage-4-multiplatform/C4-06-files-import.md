# C4-06 files-import

## 服务的 UX 页面

- S4-IOS-07 files-import

## Core API

- `import_file`
- `predict_category`

## 输入

- iOS Files provider 授权后的 file URL。

## 输出

- 导入预览和导入结果。

## DB 变化

- 同 import 能力。

## 文件系统变化

- Core 只处理授权后的可读文件。

## 错误码

- `ICloudPlaceholder`
- `PermissionDenied`
- `DuplicateFile`
- `Conflict`

## 验收标准

- 文件未下载/无权限时给出结构化状态。
- Replace 必须进入 S4-X-09。
- Cancel 不写 DB。

## 延后范围

- Provider 后台下载管理不在 Core。
