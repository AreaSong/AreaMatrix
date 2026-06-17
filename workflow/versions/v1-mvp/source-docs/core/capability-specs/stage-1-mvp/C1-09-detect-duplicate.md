# C1-09 detect-duplicate

## 服务的 UX 页面

- S1-22 conflict-duplicate
- S1-24 replace-confirm

## Core API

- `import_file(repo_path, source_path, options)` 内部 hash 检测。
- 可选缺口：`preview_import` 返回重复候选。

## 输入

- `source_path`
- `DuplicateStrategy`

## 输出

- `DuplicateFile { existing_path }`。
- 或按 `KeepBoth` / `Overwrite` 策略继续导入。

## DB 变化

- 读取 `files.hash_sha256`。
- `Overwrite` 需要软删除旧文件并写 change log。

## 文件系统变化

- 读取源文件 hash。
- `Skip` 不写最终文件。
- `Overwrite` 必须走安全替换或 Trash 语义。

## 错误码

- `DuplicateFile`
- `Io`
- `Db`
- `PermissionDenied`

## 验收标准

- 同 hash 文件默认 `Skip`，UI 能得到 existing path。
- `KeepBoth` 产生两个 active entry，路径不同、hash 相同。
- `Overwrite` 必须有二次确认 UI 才能接入。

## 延后范围

- 高级相似文件检测和模糊重复属于 Stage 2+。
