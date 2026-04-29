# C2-14 classifier-impact-preview

## 服务的 UX 页面

- S2-18 classifier-impact-preview

## Core API

- 计划新增：`preview_classifier_rule_impact(repo_path, rule) -> RuleImpactReport`

## 输入

- 分类规则草稿。

## 输出

- 受影响文件数量、样例、冲突、needs review。

## DB 变化

- 无写入。

## 文件系统变化

- 无。

## 错误码

- `Config`
- `Db`

## 验收标准

- 仅预览不改变文件分类。
- 影响量超过阈值必须提示。
- 冲突或 needs review 时不能直接批量应用。

## 延后范围

- 后台持续规则评估属于后续优化。
