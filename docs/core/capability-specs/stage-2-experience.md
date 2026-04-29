# Stage 2 Experience Core 能力索引

> Stage 2 目标是在 Stage 1 稳定闭环之上补齐搜索、标签、Undo、批量操作、命令面板、自定义分类和更完整的冲突处理。

## 能力列表

| ID | 能力 | 类型 | 主要消费页面 | Prompt |
|---|---|---|---|---|
| C2-01 | [search-query-files](stage-2-experience/C2-01-search-query-files.md) | Search | S2-01, S2-04, S2-05 | `4-1/task-01` |
| C2-02 | [search-filters](stage-2-experience/C2-02-search-filters.md) | Search | S2-02, S2-08 | `4-1/task-02` |
| C2-03 | [saved-search-crud](stage-2-experience/C2-03-saved-search-crud.md) | Search | S2-03, S2-06 | `4-1/task-03` |
| C2-04 | [smart-lists](stage-2-experience/C2-04-smart-lists.md) | Search | S2-06, S2-15 | `4-1/task-04` |
| C2-05 | [tag-crud](stage-2-experience/C2-05-tag-crud.md) | Tags | S2-07, S2-08 | `4-1/task-05` |
| C2-06 | [batch-add-tags](stage-2-experience/C2-06-batch-add-tags.md) | Batch | S2-09, S2-10 | `4-1/task-06` |
| C2-07 | [undo-action-log](stage-2-experience/C2-07-undo-action-log.md) | Undo | S2-10, S2-11 | `4-1/task-07` |
| C2-08 | [batch-change-category](stage-2-experience/C2-08-batch-change-category.md) | Batch | S2-12, S2-10 | `4-1/task-08` |
| C2-09 | [batch-delete-trash](stage-2-experience/C2-09-batch-delete-trash.md) | Batch | S2-13, S2-10 | `4-1/task-09` |
| C2-10 | [batch-rename-preview](stage-2-experience/C2-10-batch-rename-preview.md) | Batch | S2-14, S2-10 | `4-1/task-10` |
| C2-11 | [command-index](stage-2-experience/C2-11-command-index.md) | Command | S2-15 | `4-1/task-11` |
| C2-12 | [classifier-correction](stage-2-experience/C2-12-classifier-correction.md) | Classifier | S2-16 | `4-1/task-12` |
| C2-13 | [classifier-rule-save](stage-2-experience/C2-13-classifier-rule-save.md) | Classifier | S2-17 | `4-1/task-13` |
| C2-14 | [classifier-impact-preview](stage-2-experience/C2-14-classifier-impact-preview.md) | Classifier | S2-18 | `4-1/task-14` |
| C2-15 | [classifier-rule-editor](stage-2-experience/C2-15-classifier-rule-editor.md) | Classifier | S2-19 | `4-1/task-15` |
| C2-16 | [icloud-conflict-visual](stage-2-experience/C2-16-icloud-conflict-visual.md) | Conflict | S2-20 | `4-1/task-16` |
| C2-17 | [import-conflict-batch](stage-2-experience/C2-17-import-conflict-batch.md) | Conflict | S2-21 | `4-1/task-17` |
| C2-18 | [redo-action-log](stage-2-experience/C2-18-redo-action-log.md) | Undo / Redo | S2-22 | `4-1/task-18` |
| C2-19 | [tag-suggestions](stage-2-experience/C2-19-tag-suggestions.md) | Tags | S2-23 | `4-1/task-19` |

## 切片原则

- 搜索和标签是查询/元数据能力，不改变文件位置。
- 批量能力必须先预览，再确认，再执行，并写 change log / undo action。
- 分类规则变更不得静默大面积重分类，必须先走 impact preview。
