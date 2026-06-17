# C3-05 ai-call-log

## 服务的 UX 页面

- S3-05 ai-call-log

## Core API

- 计划新增：`list_ai_calls`、`clear_ai_call_log`

## 输入

- filter、pagination、clear scope。

## 输出

- AI 调用记录，不包含密钥和完整文件内容。

## DB 变化

- 读写 `ai_call_log` 或等价审计表。

## 文件系统变化

- 无。

## 错误码

- `Db`
- `PermissionDenied`

## 验收标准

- 本地/远程调用可区分。
- 可清除日志，但不影响用户文件。
- 日志不包含 API key 或未脱敏隐私内容。

## 延后范围

- 云端审计同步不在 Stage 3。
