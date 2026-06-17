# C2-02 search-filters

## 服务的 UX 页面

- S2-02 search-filters
- S2-08 tags-filter

## Core API

- `search_files(...)`
- 计划新增：`list_filter_facets(repo_path, query) -> SearchFacets`

## 输入

- category、tags、date range、storage mode、include deleted。

## 输出

- 过滤后的搜索结果和 facet counts。

## DB 变化

- 无写入。

## 文件系统变化

- 无。

## 错误码

- `Db`
- `Config`

## 验收标准

- 标签筛选只改变搜索条件，不创建或删除标签。
- 日期非法返回结构化 query error。
- Smart List 编辑场景可保存 draft filter。

## 延后范围

- 语义 filter 和 AI filter 属于 Stage 3。
