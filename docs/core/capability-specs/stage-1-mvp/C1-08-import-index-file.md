# C1-08 import-index-file

## 服务的 UX 页面

- S1-17 import-single-sheet
- S1-19 import-folder-sheet
- S1-20 import-progress
- S1-21 import-result
- S1-27 settings-repository

## Core API

- `import_file(repo_path, source_path, ImportOptions { mode: Indexed, ... }) -> FileEntry`

## 输入

- `repo_path`
- `source_path`
- `ImportOptions`

## 输出

- 指向外部或资料库内现有文件的 `FileEntry`。

## DB 变化

- `files.storage_mode = Indexed`。
- `files.source_path` 必须保留。
- 写入 `change_log.imported`。

## 文件系统变化

- 不复制、不移动源文件。
- 可读取源文件 metadata 和 hash。

## 错误码

- `InvalidPath`
- `FileNotFound`
- `PermissionDenied`
- `ICloudPlaceholder`
- `Db`

## 验收标准

- 成功后源文件路径不变。
- 删除源文件后详情或列表能通过 `FileNotFound` 显示可恢复错误。
- Indexed 模式不得写入最终资料库文件副本。

## 延后范围

- 外部路径 bookmark 和跨重启授权归 macOS app 层。
- Stage 1 不做跨设备 indexed 路径修复。
