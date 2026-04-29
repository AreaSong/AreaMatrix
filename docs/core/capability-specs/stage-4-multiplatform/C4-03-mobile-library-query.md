# C4-03 mobile-library-query

## 服务的 UX 页面

- S4-IOS-02 mobile-library
- S4-IOS-05 mobile-file-detail

## Core API

- `list_files`
- `get_file`
- `list_tree_json`
- `list_changes`

## 输入

- repo path、filter、pagination。

## 输出

- 移动端可分页数据。

## DB 变化

- 无写入。

## 文件系统变化

- 无写入。

## 错误码

- `Db`
- `RepoNotInitialized`

## 验收标准

- 移动端不需要一次加载全库。
- 详情数据来自 Core，而非平台侧扫描。
- 缺失文件状态可被 UI 表达。

## 延后范围

- 离线缓存同步策略后续细化。
