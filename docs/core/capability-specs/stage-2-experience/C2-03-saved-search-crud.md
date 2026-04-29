# C2-03 saved-search-crud

## 服务的 UX 页面

- S2-03 saved-search-sheet
- S2-06 smart-lists

## Core API

- 计划新增：`create_saved_search`、`update_saved_search`、`delete_saved_search`、`list_saved_searches`

## 输入

- 名称、query、filters、sort、scope。

## 输出

- SavedSearch 记录。

## DB 变化

- 新增/更新/删除 saved search 元数据表。

## 文件系统变化

- 无。

## 错误码

- `Db`
- `Config`

## 验收标准

- 删除 Smart List 只删除保存查询，不删除任何文件。
- 名称重复、非法 query、保存失败都有结构化错误。
- 保存后可在 sidebar 恢复同一搜索条件。

## 延后范围

- 共享 Smart List 和跨端同步属于 Stage 4。
