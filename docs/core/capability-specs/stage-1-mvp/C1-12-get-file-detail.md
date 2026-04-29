# C1-12 get-file-detail

## 服务的 UX 页面

- S1-12 detail-meta
- S1-15 detail-multi

## Core API

- `get_file(repo_path, file_id) -> FileEntry`

## 输入

- `repo_path`
- `file_id`

## 输出

- 单个 `FileEntry`。

## DB 变化

- 无写入。

## 文件系统变化

- 可选 metadata 检查，但不得修改文件。

## 错误码

- `FileNotFound`
- `RepoNotInitialized`
- `Db`

## 验收标准

- 存在文件返回完整字段。
- 不存在或已删除 file_id 返回结构化错误或按 filter 规则不可见。
- Detail UI 不需要从文件路径反推 DB 字段。

## 延后范围

- 文件预览、Quick Look 和 OCR 元数据属于 macOS/Stage 2+。
