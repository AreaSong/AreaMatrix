# C3-10 ai-fallback

## 服务的 UX 页面

- S3-10 ai-fallback

## Core API

- 计划新增：`get_ai_fallback_status`。
- 关联所有 AI API 的 fallback metadata。

## 输入

- AI operation、provider error、privacy decision。

## 输出

- fallback kind、user message、retry ability。

## DB 变化

- 记录 AI call failure。

## 文件系统变化

- 无。

## 错误码

- `Config`
- `Internal`
- `PermissionDenied`

## 验收标准

- AI 失败不阻断导入、普通搜索、本地规则分类。
- 不自动切换远程 provider。
- UI 能展示是失败、禁用、隐私跳过还是模型不可用。

## 延后范围

- 自动 provider failover 不在 Stage 3。
