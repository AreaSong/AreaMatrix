# C1-02 init-empty-repo

## 服务的 UX 页面

- S1-04 confirm-init
- S1-05 initializing
- S1-07 init-done
- S1-08 main-empty

## Core API

- `init_repo(repo_path, RepoInitOptions { mode: CreateEmpty, ... })`
- `load_config(repo_path)`
- `list_tree_json(repo_path, locale)`

## 输入

- `repo_path`
- `RepoInitOptions.create_default_categories`
- `RepoInitOptions.overview_output`

## 输出

- 初始化成功或结构化 `CoreError`。
- 可被后续 `load_config`、`list_files`、`list_tree_json` 读取的空资料库。

## DB 变化

- 创建 `.areamatrix/index.db`。
- 初始化 `schema_version`、`repo_config`。

## 文件系统变化

- 创建 `.areamatrix/staging/`、`.areamatrix/archives/`、`.areamatrix/generated/`。
- 创建默认 `classifier.yaml` 和 `ignore.yaml`。
- 默认只写 `.areamatrix/generated/root.md`。
- 不覆盖用户已有 `README.md`。

## 错误码

- `InvalidPath`
- `PermissionDenied`
- `Config`
- `Io`
- `Db`

## 验收标准

- 空目录初始化后 DB、配置、分类规则和 generated overview 均存在。
- 重复初始化同一目录有明确错误，不破坏已有数据。
- 初始化失败不会留下不可恢复的半成品；再次启动可由 C1-16 处理。

## 延后范围

- 非空目录接管由 C1-03 处理。
- UI 进度展示由 Phase 2 prompt 处理。
