# C2-15 classifier-rule-editor

## 服务的 UX 页面

- S2-19 classifier-rule-editor

## Core API

- 计划新增：`list_classifier_rules`、`create_classifier_rule`、`update_classifier_rule`、`delete_classifier_rule`

## 输入

- 新建规则内容、规则 ID 和更新/删除请求。

## 输出

- 规则列表或创建/更新/删除结果。

## DB 变化

- 更新分类规则配置。

## 文件系统变化

- 原子更新 `.areamatrix/classifier.yaml` 或等价配置。

## 错误码

- `Config`
- `PermissionDenied`
- `Io`

## 验收标准

- 编辑规则前后可预览影响。
- 删除规则不自动移动历史文件。
- 配置损坏时可恢复到旧版本。

## 延后范围

- 复杂脚本规则和插件规则不在 Stage 2。
