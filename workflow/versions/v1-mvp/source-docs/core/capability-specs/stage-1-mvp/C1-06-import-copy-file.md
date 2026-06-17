# C1-06 import-copy-file

## 服务的 UX 页面

- S1-17 import-single-sheet
- S1-18 import-batch-sheet
- S1-20 import-progress
- S1-21 import-result
- S1-09 main-list

## Core API

- `import_file(repo_path, source_path, ImportOptions { mode: Copied, ... }) -> FileEntry`

## 输入

- `repo_path`
- `source_path`
- `ImportOptions.destination`
- `ImportOptions.duplicate_strategy`

## 输出

- 新增 `FileEntry`。
- 可在列表、详情、Tree 和 change log 中查到。

## DB 变化

- `files` 插入 staging 后提升为 active。
- `change_log` 写入 `imported`。

## 文件系统变化

- 复制源文件到 `.areamatrix/staging/`。
- 计算 hash 后 rename 到最终目录。
- 保留原文件不变。

## 错误码

- `InvalidPath`
- `DuplicateFile`
- `ICloudPlaceholder`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 成功后源文件存在且内容不变。
- 目标文件、DB `files`、`change_log` 三者一致。
- 失败不会留下 active 半成品；staging 可由 C1-16 清理。

## 延后范围

- 批量队列进度由 UI 层编排。
- 大文件细粒度进度回调不在 Stage 1 Core API 内，先由 UI 包装单文件任务状态。
