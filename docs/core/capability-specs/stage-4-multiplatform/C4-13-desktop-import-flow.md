# C4-13 desktop-import-flow

## 服务的 UX 页面

- S4-WIN-05 import-flow
- S4-LNX-05 import-flow

## Core API

- `predict_category`
- `import_file`

## 输入

- 平台 file picker 返回路径和 ImportOptions。

## 输出

- 导入结果和冲突状态。

## DB 变化

- 同 Stage 1 import 能力。

## 文件系统变化

- Copy/Move/Index 按配置执行。

## 错误码

- `DuplicateFile`
- `Conflict`
- `PermissionDenied`
- `InvalidPath`

## 验收标准

- Replace 必须走 S4-X-09。
- 平台 Trash 不可用时禁止 destructive 路径。
- 导入失败不显示成功状态。

## 延后范围

- Explorer/Nautilus shell integration 后续再拆。
