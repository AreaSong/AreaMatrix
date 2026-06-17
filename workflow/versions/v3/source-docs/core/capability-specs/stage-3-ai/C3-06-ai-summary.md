# C3-06 ai-summary

## 服务的 UX 页面

- S3-06 ai-summary-editor

## Core API

- 计划新增：`generate_ai_summary`、`save_ai_summary`、`clear_ai_summary`

## 输入

- file_id、summary draft、provider scope。

## 输出

- 摘要草稿或保存结果。

## DB 变化

- 保存摘要 metadata。
- 写 AI call log 和 change log。

## 文件系统变化

- 可写伴生 summary metadata；不得覆盖用户原文件。

## 错误码

- `Config`
- `FileNotFound`
- `PermissionDenied`
- `Db`

## 验收标准

- 生成结果默认是草稿，用户保存后才持久化。
- Clear 只清摘要，不删文件和笔记。
- 远程摘要必须受隐私规则控制。

## 延后范围

- 多文档摘要和知识库摘要属于后续阶段。
