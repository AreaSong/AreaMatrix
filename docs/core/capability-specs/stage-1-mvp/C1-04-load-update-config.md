# C1-04 load-update-config

## 服务的 UX 页面

- S1-26 settings-general
- S1-27 settings-repository
- S1-28 settings-classifier
- S1-29 settings-integrations
- S1-30 settings-advanced

## Core API

- `load_config(repo_path) -> RepoConfig`
- `update_config(repo_path, new_config)`

## 输入

- `repo_path`
- `RepoConfig`

## 输出

- 当前资料库配置。
- 原子更新后的配置。

## DB 变化

- `repo_config` 中配置键值更新。
- 配置变更需要写 `updated_at`。

## 文件系统变化

- 可同步写入 `.areamatrix/classifier.yaml` 或配置文件，具体以 `docs/architecture/data-model.md` 为准。
- 更新必须采用 tmp + rename。

## 错误码

- `Config`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 配置不存在时返回默认值，不抛错。
- 更新失败不损坏旧配置。
- 默认存储模式、overview 输出、locale、AI 开关与 UI 设置项可读写。

## 延后范围

- Stage 2+ 的搜索、标签、AI provider 配置只保留字段或占位，不实现远程能力。
