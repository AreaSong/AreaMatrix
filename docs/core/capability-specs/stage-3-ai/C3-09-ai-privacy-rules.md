# C3-09 ai-privacy-rules

## 服务的 UX 页面

- S3-09 ai-privacy-rules
- S3-10 ai-fallback

## Core API

- 计划新增：`list_ai_privacy_rules`、`update_ai_privacy_rules`、`evaluate_ai_privacy`

## 输入

- 目录规则、关键词规则、字段过滤规则、`privacy_gate_enabled`、provider scope snapshot。

## 输出

- allow/deny/skipped reason。
- provider gate reason，例如 `privacy_gate_disabled`、`scope_not_allowed`、`provider_not_verified`。

## DB 变化

- 保存 privacy rules。
- 记录 skipped AI calls。

## 文件系统变化

- 无写入。

## 错误码

- `Config`
- `Db`

## 验收标准

- 命中规则时不发送文件内容到 AI。
- 跳过原因在 AI 页面和调用日志可见。
- 默认策略偏保守。
- 关闭 `privacy_gate_enabled` 只阻止远程调用，不删除 provider 配置、Keychain key 或既有 AI 结果。

## 延后范围

- 组织级 DLP 策略不在 Stage 3。
