# C4-11 desktop-main-query

## 服务的 UX 页面

- S4-WIN-02 main-window
- S4-LNX-02 main-window

## Core API

- `list_files`
- `get_file`
- `list_tree_json`
- `search_files`

## 输入

- repo path、filter、pagination。

## 输出

- 跨桌面平台主窗口数据。

## DB 变化

- 只读。

## 文件系统变化

- 无写入。

## 错误码

- `Db`
- `RepoNotInitialized`

## 验收标准

- Windows/Linux 主窗口使用同一 Core 查询能力。
- 平台 UI 不直接扫描 repo 拼列表。
- 大库分页可用。

## 延后范围

- 平台原生虚拟列表优化由 app 层处理。
