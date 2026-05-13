# C1-04 load-update-config

## 服务的 UX 页面

- S1-01 welcome
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

## 页面消费边界

- S1-01 只消费 `load_config`：外层 onboarding shell 读取已配置 repo 后决定继续显示欢迎页、进入 repo ready 状态或展示配置错误；不得在欢迎页中触发 `update_config`。
- S1-26 到 S1-30 可消费 `load_config` 与 `update_config`，但具体设置项由各自 page-feature task 验收。

## DB 变化

- `repo_config` 中配置键值更新。
- 配置变更需要写 `updated_at`。

## 文件系统变化

- 当前 C1-04 contract-api 只持久化 SQLite `repo_config`，不创建或覆盖 `README.md`、
  `AREAMATRIX.md` 或 `.areamatrix/classifier.yaml`。
- 若后续任务引入文件型配置同步，文件写入必须采用 tmp + rename，并在对应能力中单独验证。

## 错误码

- `Config`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 配置不存在时返回默认值，不抛错。
- 更新失败不损坏旧配置。
- 默认存储模式、overview 输出、locale、AI 开关、iCloud 提醒、分类规则
  开关、fallback inbox 与危险 Replace 开关可读写。

## 延后范围

- Stage 2+ 的搜索、标签、AI provider 配置只保留字段或占位，不实现远程能力。
