# C1-07 import-move-file

## 服务的 UX 页面

- S1-17 import-single-sheet
- S1-20 import-progress
- S1-21 import-result
- S1-26 settings-general

## Core API

- `import_file(repo_path, source_path, ImportOptions { mode: Moved, ... }) -> FileEntry`

## 输入

- `repo_path`
- `source_path`
- `ImportOptions`

## 输出

- 新增 `FileEntry`。
- 原路径被安全移入资料库最终位置。

## DB 变化

- `files.storage_mode = Moved`。
- `files.source_path` 记录原始来源。
- `change_log.action = imported`。

## 文件系统变化

- 源文件移动到 staging，再原子 rename 到最终目录。
- 不跨越用户未确认的目录边界。

## 错误码

- `InvalidPath`
- `DuplicateFile`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 成功后原路径不存在，最终路径存在。
- 移动失败必须保留源文件或可恢复 staging，不丢数据。
- 与 Copy 模式共享重复检测和同名冲突处理。

## 延后范围

- 从外部云盘占位符自动下载由 macOS 层处理。
- 多文件 move 队列由 Phase 2 UI 任务处理。
