# C3-01 ai-settings-config

## 服务的 UX 页面

- S3-01 ai-settings
- S3-09 ai-privacy-rules

## Core API

- 计划新增：`load_ai_config`、`update_ai_config`

## 输入

- AI enabled、provider preference、本地/远程开关、隐私策略引用。

## 输出

- 当前 AI 配置和可用能力。

## DB 变化

- 写入 repo 或 app 级 AI 配置元数据。

## 文件系统变化

- 可写配置文件；不得写入 API key 明文。

## 错误码

- `Config`
- `PermissionDenied`
- `Io`

## 验收标准

- AI 默认关闭。
- 配置变更可持久化且不会自动触发远程调用。
- key 只允许平台安全存储，不进入日志或诊断。

## 延后范围

- 企业策略下发和团队级配置属于后续阶段。
