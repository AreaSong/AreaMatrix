# Stage 2 Experience Control Map

> Stage 2 映射搜索、标签、Undo、批量操作、命令面板、自定义分类和冲突增强页面到 Core 能力。

## 页面到能力矩阵

| UX | 页面 | Core 能力 | API / 能力意图 | DB / 文件系统 | Prompt |
|---|---|---|---|---|---|
| S2-01 | search-results | C2-01, C2-02 | `search_files` | 只读 query/FTS | `4-1/task-96`, `4-1/task-97`, `4-1/task-98` |
| S2-02 | search-filters | C2-02 | filter/facet query | 只读 | `4-1/task-99` |
| S2-03 | saved-search-sheet | C2-03 | saved search CRUD | saved_searches | `4-1/task-100` |
| S2-04 | search-empty | C2-01 | empty result state | 只读 | `4-1/task-101` |
| S2-05 | query-error | C2-01 | query diagnostics | 只读 | `4-1/task-102` |
| S2-06 | smart-lists | C2-03, C2-04 | run/list smart lists | saved_searches | `4-1/task-103`, `4-1/task-104`, `4-1/task-105` |
| S2-07 | tags-add | C2-05 | add/remove/list tags | tags, change_log | `4-1/task-106` |
| S2-08 | tags-filter | C2-02, C2-05 | tag filter | tags 只读 | `4-1/task-107`, `4-1/task-108`, `4-1/task-109` |
| S2-09 | batch-add-tags | C2-06, C2-07 | batch tag mutation | tags, undo_actions | `4-1/task-110`, `4-1/task-111`, `4-1/task-112` |
| S2-10 | undo-toast | C2-07 | undo action | undo_actions | `4-1/task-113` |
| S2-11 | undo-history | C2-07 | list/execute undo | undo_actions | `4-1/task-114` |
| S2-12 | batch-change-category | C2-08, C2-07 | preview + batch move | files, change_log, FS move | `4-1/task-115`, `4-1/task-116`, `4-1/task-117` |
| S2-13 | batch-delete-confirm | C2-09, C2-07 | preview + Trash delete | files, change_log, Trash | `4-1/task-118`, `4-1/task-119`, `4-1/task-120` |
| S2-14 | batch-rename | C2-10, C2-07 | preview + rename | files, change_log, FS rename | `4-1/task-121`, `4-1/task-122`, `4-1/task-123` |
| S2-15 | command-palette | C2-04, C2-11 | command index | 只读 / recent command | `4-1/task-124`, `4-1/task-125`, `4-1/task-126` |
| S2-16 | classifier-correct | C2-12 | correct category | files, change_log, safe move | `4-1/task-127` |
| S2-17 | classifier-save-rule | C2-13 | save rule | classifier config | `4-1/task-128` |
| S2-18 | classifier-impact-preview | C2-14 | rule impact preview | 只读 | `4-1/task-129` |
| S2-19 | classifier-rule-editor | C2-15 | rule CRUD | classifier config | `4-1/task-130` |
| S2-20 | icloud-conflict-visual | C2-16, C1-25 | conflict preview/resolve | conflict state, Trash | `4-1/task-131`, `4-1/task-132`, `4-1/task-133` |
| S2-21 | import-conflict-batch | C2-17, C2-07 | import conflict batch decision | import session, staging, change_log | `4-1/task-134`, `4-1/task-135`, `4-1/task-136` |
| S2-22 | redo | C2-18, C2-07 | redo action | undo_actions / redo stack | `4-1/task-137`, `4-1/task-138`, `4-1/task-139` |
| S2-23 | tag-suggestions | C2-19, C2-05 | non-AI tag suggestion | tags, file_tags after confirm | `4-1/task-140`, `4-1/task-141`, `4-1/task-142` |

## 验收口径

- 搜索、filter、Smart List 不得移动、删除或改名文件。
- 批量操作必须有 preview、确认、执行报告和 undo/action log。
- 分类规则保存和影响预览分离；未预览不得大面积应用。
