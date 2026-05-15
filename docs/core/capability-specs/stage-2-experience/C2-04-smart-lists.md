# C2-04 smart-lists

## 服务的 UX 页面

- S2-06 smart-lists
- S2-15 command-palette

## Core API

- `list_saved_searches`
- `search_files`
- 计划新增：`run_smart_list(repo_path, saved_search_id, pagination) -> SearchResultPage`

## 输入

- Smart List ID 和分页。

## 输出

- Smart List 结果页。

## DB 变化

- 读取 saved searches；无文件写入。

## 文件系统变化

- 无。

## 错误码

- `Db`
- `Config`
- `FileNotFound`

## 验收标准

- 打开 Smart List 只运行查询，不改变文件。
- Rename/Delete/Duplicate 只影响 saved search 记录。
- Command palette 能发现 smart list。

## 延后范围

- 智能推荐列表属于 Stage 3。
