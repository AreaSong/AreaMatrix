# C4-13 desktop-import-flow

## 服务的 UX 页面

- S4-WIN-05 import-flow
- S4-LNX-05 import-flow

## Core API

- `predict_category`
- `import_file`
- `import_file_with_result`

## 输入

- 平台 file picker 返回路径和 ImportOptions。

## 输出

- 导入结果、冲突状态、Move 源文件移除状态。

## DB 变化

- 同 Stage 1 import 能力。

## 文件系统变化

- Copy/Move/Index 按配置执行。
- Move 必须先安全写入 repository 文件、DB 和导入日志，再移除 source。
- Move 源文件移除失败时保留已导入 repository 文件，并返回
  `source_removal_status = Retained` 与 `source_removal_failure`，供页面显示
  `Imported, original retained`。

## 错误码

- `DuplicateFile`
- `Conflict`
- `PermissionDenied`
- `InvalidPath`

## 验收标准

- Replace 必须走 S4-X-09。
- 平台 Trash 不可用时禁止 destructive 路径。
- 导入失败不显示成功状态。
- Move 源文件移除失败不得回滚已安全导入的 repository 文件，但不得标记为
  完整 Move。

## 延后范围

- Explorer/Nautilus shell integration 后续再拆。
