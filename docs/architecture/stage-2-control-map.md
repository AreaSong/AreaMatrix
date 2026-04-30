# Stage 2 Experience Control Map

> Stage 2 映射搜索、标签、Undo、批量操作、命令面板、自定义分类和冲突增强页面到 Core 能力。

## 页面到能力矩阵

| UX | 页面 | Core 能力 | API / 能力意图 | DB / 文件系统 | Prompt |
|---|---|---|---|---|---|
| S2-01 | search-results | C2-01, C2-02 | `search_files` | 只读 query/FTS | `4-1/task-20` |
| S2-02 | search-filters | C2-02 | filter/facet query | 只读 | `4-1/task-21` |
| S2-03 | saved-search-sheet | C2-03 | saved search CRUD | saved_searches | `4-1/task-22` |
| S2-04 | search-empty | C2-01 | empty result state | 只读 | `4-1/task-23` |
| S2-05 | query-error | C2-01 | query diagnostics | 只读 | `4-1/task-24` |
| S2-06 | smart-lists | C2-03, C2-04 | run/list smart lists | saved_searches | `4-1/task-25` |
| S2-07 | tags-add | C2-05 | add/remove/list tags | tags, change_log | `4-1/task-26` |
| S2-08 | tags-filter | C2-02, C2-05 | tag filter | tags 只读 | `4-1/task-27` |
| S2-09 | batch-add-tags | C2-06, C2-07 | batch tag mutation | tags, undo_actions | `4-1/task-28` |
| S2-10 | undo-toast | C2-07 | undo action | undo_actions | `4-1/task-29` |
| S2-11 | undo-history | C2-07 | list/execute undo | undo_actions | `4-1/task-30` |
| S2-12 | batch-change-category | C2-08, C2-07 | preview + batch move | files, change_log, FS move | `4-1/task-31` |
| S2-13 | batch-delete-confirm | C2-09, C2-07 | preview + Trash delete | files, change_log, Trash | `4-1/task-32` |
| S2-14 | batch-rename | C2-10, C2-07 | preview + rename | files, change_log, FS rename | `4-1/task-33` |
| S2-15 | command-palette | C2-04, C2-11 | command index | 只读 / recent command | `4-1/task-34` |
| S2-16 | classifier-correct | C2-12 | correct category | files, change_log, safe move | `4-1/task-35` |
| S2-17 | classifier-save-rule | C2-13 | save rule | classifier config | `4-1/task-36` |
| S2-18 | classifier-impact-preview | C2-14 | rule impact preview | 只读 | `4-1/task-37` |
| S2-19 | classifier-rule-editor | C2-15 | rule CRUD | classifier config | `4-1/task-38` |
| S2-20 | icloud-conflict-visual | C2-16, C1-25 | conflict preview/resolve | conflict state, Trash | `4-1/task-39` |
| S2-21 | import-conflict-batch | C2-17, C2-07 | import conflict batch decision | import session, staging, change_log | `4-1/task-40` |
| S2-22 | redo | C2-18, C2-07 | redo action | undo_actions / redo stack | `4-1/task-41` |
| S2-23 | tag-suggestions | C2-19, C2-05 | non-AI tag suggestion | tags, file_tags after confirm | `4-1/task-42` |

## 验收口径

- 搜索、filter、Smart List 不得移动、删除或改名文件。
- 批量操作必须有 preview、确认、执行报告和 undo/action log。
- 分类规则保存和影响预览分离；未预览不得大面积应用。
