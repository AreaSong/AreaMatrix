# C3-04 ai-classification-suggestion

## 服务的 UX 页面

- S3-04 ai-classification-suggestion
- S3-10 ai-fallback

## Core API

- 计划新增：`suggest_category_with_ai(repo_path, file_id) -> AiCategorySuggestion`

## 输入

- file_id、上下文提取策略、privacy policy。

## 输出

- 建议分类、confidence、reason、是否本地/远程。

## DB 变化

- 写 AI call log。
- 用户采纳前不改 `files.category`。

## 文件系统变化

- 可只读提取文件名、路径、有限文本摘要；受隐私规则限制。

## 错误码

- `Config`
- `PermissionDenied`
- `Internal`

## 验收标准

- 只在规则分类失败或低置信时介入。
- 建议必须等待用户确认。
- 隐私规则命中时返回 skipped reason。

## 延后范围

- 全自动重分类不在 Stage 3。
