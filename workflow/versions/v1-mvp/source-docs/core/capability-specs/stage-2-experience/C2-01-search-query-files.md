# C2-01 search-query-files

## 服务的 UX 页面

- S2-01 search-results
- S2-04 search-empty
- S2-05 query-error

## Core API

- 计划新增：`search_files(repo_path, query, filter, sort, pagination) -> SearchResultPage`

## 输入

- 查询字符串、filter、sort、limit、offset。

## 输出

- 搜索结果、总数、query parse diagnostics。

## DB 变化

- 无写入。可新增 FTS 或索引表。

## 文件系统变化

- 无。

## 错误码

- `Db`
- `Config`
- `InvalidPath`

## 验收标准

- 文件名、相对路径、笔记、分类、change log 可搜索。
- 0 结果和 query parse error 可区分。
- 搜索不修改标签、分类或文件。

## 延后范围

- OCR、语义搜索和远程 AI 属于 Stage 3。
