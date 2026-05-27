# C3-03 remote-provider-config

## 服务的 UX 页面

- S3-03 remote-model-enable
- S3-09 ai-privacy-rules

## Core API

- 计划新增：`test_remote_ai_provider`、`load_remote_ai_provider_config`、
  `enable_remote_ai_provider`、`disable_remote_ai_provider`

## 输入

- provider、model、key reference、allowed scopes。

## 输出

- 测试连接结果和启用状态。
- `provider_configured`、`provider_verified`、`remote_provider_enabled`、`feature_scope`，供 S3-03/S3-09 共同判断远程调用 gate。
- 禁用远程 provider 后的只读快照；如用户选择删除凭据，快照必须隐藏 credential reference 并重置 verified。

## DB 变化

- 保存 provider metadata 和 scope，不保存 key 明文。

## 文件系统变化

- 无直接文件写入，key 进入 Keychain 或平台安全存储。

## 错误码

- `Config`
- `PermissionDenied`
- `Internal`

## 验收标准

- 远程 provider 必须显式测试和确认数据流向后启用。
- S3-03/S3-09 必须能读取当前 provider 配置、测试状态、启用状态和 scope。
- S3-03 必须能禁用 remote provider；删除 Keychain key 只能在用户勾选后执行。
- API key 不进入日志、诊断、错误文案。
- 本地模型失败不得自动启用远程 provider。
- 远程调用必须同时满足 provider configured、provider verified、remote provider enabled、feature scope allowed 和 S3-09 privacy gate allowed。

## 延后范围

- 多 provider 自动路由不在 Stage 3。
