# C2-14 classifier-impact-preview

## 服务的 UX 页面

- S2-18 classifier-impact-preview

## Core API

- 计划新增：`preview_classifier_rule_impact(repo_path, request) -> RuleImpactReport`

## 输入

- 规则草稿、删除 keyword、删除 extension 或删除 category 的显式预览请求。
- Move preference，用于决定是否在只读 dry-run 中检查目标路径冲突。
- 删除 category 并准备 apply 到现有文件时，可带 replacement category；缺失时必须保留预览但禁用 apply。

## 输出

- 受影响文件数量、样例、冲突、needs review、replacement 缺失状态。
- 回显 Move preference；关闭 Move 时仅预览分类 metadata 变化，不因目标路径冲突阻断。
- 每行包含当前分类、新分类、命中来源和 `WillUpdate` / `AlreadyCorrect` / `NeedsReview` / `Conflict` / `Missing` / `IndexOnly` 状态。

## DB 变化

- 无写入。

## 文件系统变化

- 无。

## 错误码

- `Config`
- `Db`

## 验收标准

- 仅预览不改变文件分类。
- RuleDraft 预览必须复用 `classifier.yaml` matcher priority / keyword length /
  category order 语义计算新分类。
- 删除 keyword、extension 或 category 的预览不得移动、删除或重命名历史文件。
- Move 开启时必须检查 repo-owned 文件目标路径冲突；Move 关闭时不得把路径冲突作为
  metadata-only apply 阻断。
- 影响量超过阈值必须提示。
- 冲突或 needs review 时不能直接批量应用。
- 删除 category 缺少 replacement category 时不能直接批量应用。

## 延后范围

- 后台持续规则评估属于后续优化。
