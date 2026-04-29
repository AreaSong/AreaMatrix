# C1-15 build-tree

## 服务的 UX 页面

- S1-08 main-empty
- S1-09 main-list
- S1-10 main-loading

## Core API

- `list_tree_json(repo_path, locale) -> string`

## 输入

- `repo_path`
- `locale`

## 输出

- 可被 Swift 解码的 Tree JSON。

## DB 变化

- 无写入。

## 文件系统变化

- 可读文件路径和分类配置。
- 不写 generated overview。

## 错误码

- `RepoNotInitialized`
- `Db`
- `Io`

## 验收标准

- 空资料库返回合法空树。
- 大目录返回稳定排序、稳定 ID 或 path key。
- JSON schema 与 Swift 模型兼容。

## 延后范围

- 虚拟智能列表、搜索结果树属于 Stage 2。
