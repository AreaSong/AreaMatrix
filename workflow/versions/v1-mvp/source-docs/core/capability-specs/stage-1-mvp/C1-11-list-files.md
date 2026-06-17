# C1-11 list-files

## 服务的 UX 页面

- S1-08 main-empty
- S1-09 main-list
- S1-10 main-loading
- S1-15 detail-multi

## Core API

- `list_files(repo_path, filter) -> sequence<FileEntry>`

## 输入

- `FileFilter`

## 输出

- 按 `imported_at DESC` 排序的文件列表。
- `limit` 超过上限时自动 clamp。

## DB 变化

- 无写入。

## 文件系统变化

- 无。

## 错误码

- `RepoNotInitialized`
- `Db`

## 验收标准

- 空资料库返回空数组。
- 默认不返回 `status=deleted` 的文件。
- 分类过滤、时间过滤、分页和 limit clamp 有测试。

## 延后范围

- 搜索、标签过滤、智能列表属于 Stage 2。
