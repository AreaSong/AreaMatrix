# C4-04 camera-import

## 服务的 UX 页面

- S4-IOS-03 camera-import

## Core API

- `import_file`
- `predict_category`

## 输入

- 平台层保存后的照片临时文件路径和 ImportOptions。

## 输出

- FileEntry、导入结果。

## DB 变化

- 同 C1-06/C1-07。

## 文件系统变化

- Core 从平台临时路径导入到 repo。
- 平台层负责相机权限和临时文件生命周期。

## 错误码

- `PermissionDenied`
- `InvalidPath`
- `Io`
- `Db`

## 验收标准

- 拍照取消不写 DB。
- 导入失败不删除用户已有文件。
- 临时文件清理不由 Core 删除最终 repo 文件。

## 延后范围

- OCR 和拍照自动摘要属于 Stage 3+/后续。
