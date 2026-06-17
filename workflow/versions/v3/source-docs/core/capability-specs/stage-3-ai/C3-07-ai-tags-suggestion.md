# C3-07 ai-tags-suggestion

## 服务的 UX 页面

- S3-07 ai-tags-suggestion

## Core API

- 计划新增：`suggest_tags_with_ai`、`apply_ai_tag_suggestions`

## 输入

- file_id、候选标签、privacy policy。

## 输出

- 标签建议、confidence、reason。

## DB 变化

- 用户采纳后写 `tags`、change log 和 AI call log。

## 文件系统变化

- 无。

## 错误码

- `Config`
- `FileNotFound`
- `Db`

## 验收标准

- 建议不自动写入标签。
- 用户可以编辑、删除、采纳部分建议。
- 隐私规则命中时不调用 provider。

## 延后范围

- 团队标签词库不在 Stage 3。
