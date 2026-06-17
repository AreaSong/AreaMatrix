# C4-05 share-extension-import

## 服务的 UX 页面

- S4-IOS-04 share-extension-import

## Core API

- `import_file`
- `predict_category`

## 输入

- Share Extension 提供的 staged file URL。

## 输出

- 导入结果或 deferred import ticket。

## DB 变化

- 导入成功后写 files/change_log。

## 文件系统变化

- 平台层把 share payload materialize 成 Core 可读文件。

## 错误码

- `PermissionDenied`
- `InvalidPath`
- `Io`

## 验收标准

- Share Extension 超时不留下成功假状态。
- deferred import 可被主 app 继续。
- 不把外部 app payload 内容写入日志。

## 延后范围

- 后台批量分享导入优化后续处理。
