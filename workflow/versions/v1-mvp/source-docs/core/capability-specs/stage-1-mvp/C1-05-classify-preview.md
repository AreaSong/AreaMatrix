# C1-05 classify-preview

## 服务的 UX 页面

- S1-16 drag-hover
- S1-17 import-single-sheet
- S1-18 import-batch-sheet
- S1-19 import-folder-sheet
- S1-28 settings-classifier

## Core API

- `predict_category(repo_path, filename) -> ClassifyResult`

## 输入

- `repo_path`
- `filename`

## 输出

- `category`
- `suggested_name`
- `reason`
- `confidence`

## DB 变化

- 无。

## 文件系统变化

- 读取 `.areamatrix/classifier.yaml`。
- 不创建、不移动、不删除文件。

## 错误码

- `Config`
- `Classify`

## 验收标准

- 关键词命中优先于扩展名命中。
- 无命中时返回 `inbox` / default，不抛错。
- UI 可以用结果预填导入 sheet，但不能把 preview 当作最终导入。

## 延后范围

- AI 分类建议属于 Stage 3。
- 用户自定义规则编辑器属于 Stage 2。
