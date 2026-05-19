# C2-13 classifier-rule-save

## 服务的 UX 页面

- S2-17 classifier-save-rule

## Core API

- 计划新增：`save_classifier_rule(repo_path, rule) -> ClassifierRule`

## 输入

- 关键词、扩展名、目标分类、优先级、是否已完成必要影响预览确认。

## 输出

- 保存后的规则。

## DB 变化

- 可写入 classifier metadata 或 `.areamatrix/classifier.yaml` 对应结构。

## 文件系统变化

- 原子更新 classifier 配置。

## 错误码

- `Config`
- `PermissionDenied`
- `Io`

## 验收标准

- 过宽规则必须 warning 或阻止。
- 只选扩展名或其他过宽规则在未预览确认时必须阻止；预览确认后可只保存规则配置。
- 重复规则有结构化反馈。
- 保存前不应用到历史文件。

## 延后范围

- AI 自动生成规则属于 Stage 3+。
