# Stage 1 MVP Control Map

> 本文是 Stage 1 的合同矩阵，绑定 UX 页面、Core 能力、API、DB、文件系统、副作用、错误态和 prompt 任务。它用于防止“前端做完但 Core 不够用”或“Core 做出页面不消费的能力”。

## 验收原则

- 页面验收必须同时回到页面规格、对应 `C1-*` 能力和本矩阵。
- 标记为 Real Core 的页面，最终验收不得用 mock、fixture 或静态占位通过。
- 标记为 Preview 可 mock 的页面，只允许在 UI 初期使用 mock；一旦进入对应纵向闭环 task，必须接真实 Core。
- Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。

## 页面到能力矩阵

| UX | 页面 | Core 能力 | Core API | DB 表 | 文件系统 | 错误态 | Prompt | Core 接入 |
|---|---|---|---|---|---|---|---|---|
| S1-01 | welcome | C1-04 | `load_config` | `repo_config` | app config | Config | `2-1/task-01` | Real Core（config routing） |
| S1-02 | choose-path | C1-01 | `validate_repo_path` | none | selected path stat | InvalidPath, PermissionDenied | `2-1/task-02` | Real Core |
| S1-03 | validate-path | C1-01, C1-03, C1-21 | `validate_repo_path`, `get_latest_scan_session` | `scan_sessions` | `.areamatrix/` probe | InvalidPath, PermissionDenied, ICloudPlaceholder | `2-1/task-03`, `2-1/task-04`, `2-1/task-05`, `2-1/task-06` | Real Core |
| S1-04 | confirm-init | C1-02, C1-03 | `init_repo` | `schema_version`, `repo_config`, `scan_sessions` | `.areamatrix/**` | Config, PermissionDenied | `2-1/task-07`, `2-1/task-08`, `2-1/task-09` | Real Core |
| S1-05 | initializing | C1-02, C1-03, C1-16 | `init_repo`, `recover_on_startup`, `get_latest_scan_session` | `scan_sessions`, `files` | staging cleanup, generated overview | Db, Io | `2-1/task-10`, `2-1/task-11`, `2-1/task-12`, `2-1/task-13` | Real Core |
| S1-06 | init-failed | C1-21 | error mapping only | none | none | all init errors | `2-1/task-14` | Real Core |
| S1-07 | init-done | C1-02, C1-03 | `load_config`, `list_tree_json` | `repo_config`, `files` | `.areamatrix/` | Config | `2-1/task-15`, `2-1/task-16`, `2-1/task-17` | Real Core |
| S1-08 | main-empty | C1-11, C1-15 | `list_files`, `list_tree_json` | `files` | repo tree read | RepoNotInitialized, Db | `2-1/task-19`, `2-1/task-20`, `2-1/task-21` | Real Core |
| S1-09 | main-list | C1-11, C1-12, C1-15 | `list_files`, `get_file`, `list_tree_json` | `files` | file paths | Db, FileNotFound | `2-1/task-22`, `2-1/task-23`, `2-1/task-24`, `2-1/task-25` | Real Core |
| S1-10 | main-loading | C1-03, C1-15, C1-16 | `get_latest_scan_session`, `resume_scan_session`, `list_tree_json` | `scan_sessions` | scan path | Db, Io | `2-1/task-26`, `2-1/task-27`, `2-1/task-28`, `2-1/task-29` | Real Core |
| S1-11 | main-repo-error | C1-01, C1-19, C1-21 | `validate_initialized_repo_path`, `sync_external_changes` | `files` | missing path checks | RepoNotInitialized, Db, PermissionDenied | `2-1/task-30`, `2-1/task-31`, `2-1/task-32`, `2-1/task-33` | Real Core |
| S1-12 | detail-meta | C1-12 | `get_file` | `files` | target file metadata | FileNotFound | `2-3/task-01` | Real Core |
| S1-13 | detail-log | C1-13, C1-17, C1-18, C1-19 | `list_changes`, `sync_external_changes` | `change_log` | event paths | Db | `2-3/task-02`, `2-3/task-03`, `2-3/task-04`, `2-3/task-05`, `2-3/task-06` | Real Core |
| S1-14 | detail-note | C1-14 | `read_note`, `write_note` | `notes`, `change_log` | sidecar `.md` | FileNotFound, Io | `2-3/task-07` | Real Core |
| S1-15 | detail-multi | C1-11, C1-12 | `list_files`, `get_file` | `files` | none | Db | `2-3/task-08`, `2-3/task-09`, `2-3/task-10` | Real Core |
| S1-16 | drag-hover | C1-05 | `predict_category` | none | source path stat | InvalidPath, ICloudPlaceholder | `2-2/task-01` | Preview 可 mock，闭环必须真实 |
| S1-17 | import-single-sheet | C1-05, C1-06, C1-07, C1-08 | `predict_category`, `import_file` | `files` | staging, final file | DuplicateFile, InvalidPath | `2-2/task-02`, `2-2/task-03`, `2-2/task-04`, `2-2/task-05`, `2-2/task-06` | Real Core |
| S1-18 | import-batch-sheet | C1-05, C1-06, C1-09 | `predict_category`, `import_file` | `files` | staging, final files | DuplicateFile, Io | `2-2/task-07`, `2-2/task-08`, `2-2/task-09`, `2-2/task-10` | Real Core |
| S1-19 | import-folder-sheet | C1-05, C1-06, C1-08 | `predict_category`, `import_file` | `files` | recursive source scan | InvalidPath, PermissionDenied | `2-2/task-11`, `2-2/task-12`, `2-2/task-13`, `2-2/task-14` | Real Core |
| S1-20 | import-progress | C1-06, C1-07, C1-08 | `import_file` | `files`, `change_log` | staging lifecycle | Io, Db | `2-2/task-15`, `2-2/task-16`, `2-2/task-17`, `2-2/task-18` | Real Core |
| S1-21 | import-result | C1-06, C1-13 | `import_file`, `list_changes` | `files`, `change_log` | final path | DuplicateFile, Conflict | `2-2/task-19`, `2-2/task-20`, `2-2/task-21` | Real Core |
| S1-22 | conflict-duplicate | C1-09 | `import_file` | `files` | hash source + target | DuplicateFile | `2-2/task-22` | Real Core |
| S1-23 | conflict-name | C1-10 | `import_file`, `rename_file` | `files`, `change_log` | conflict rename | Conflict, InvalidPath | `2-2/task-23` | Real Core |
| S1-24 | replace-confirm | C1-09, C1-10 | `import_file`, `delete_file` | `files`, `change_log` | Trash / overwrite target | DuplicateFile, Conflict, Io | `2-2/task-24`, `2-2/task-25`, `2-2/task-26` | Real Core |
| S1-25 | icloud-conflict-min | C1-01, C1-21 | `validate_repo_path`, `import_file` | none | iCloud placeholder probe | ICloudPlaceholder | `2-4/task-01`, `2-4/task-02`, `2-4/task-03` | Real Core |
| S1-26 | settings-general | C1-04, C1-07 | `load_config`, `update_config` | `repo_config` | app config | Config | `2-3/task-12`, `2-3/task-13`, `2-3/task-14` | Real Core |
| S1-27 | settings-repository | C1-04, C1-08, C1-20 | `load_config`, `update_config` | `repo_config` | overview output path | Config, PermissionDenied | `2-3/task-15`, `2-3/task-16`, `2-3/task-17`, `2-3/task-18` | Real Core |
| S1-28 | settings-classifier | C1-04, C1-05 | `load_config`, `predict_category` | `repo_config` | classifier.yaml | Config, Classify | `2-3/task-19`, `2-3/task-20`, `2-3/task-21` | Real Core |
| S1-29 | settings-integrations | C1-04 | `load_config`, `update_config` | `repo_config` | app config | Config | `2-3/task-22` | Preview 可 mock |
| S1-30 | settings-advanced | C1-04, C1-16, C1-20 | `recover_on_startup`, `reindex_from_filesystem`, `update_config` | `scan_sessions`, `repo_config` | staging, generated overview | Db, Io | `2-3/task-23`, `2-3/task-24`, `2-3/task-25`, `2-3/task-26` | Real Core |
| S1-31 | settings-about | none | `get_version` | none | none | none | `2-3/task-27` | Real Core |
| S1-32 | error-recovery | C1-16, C1-21 | `recover_on_startup`, error mapping | `files`, `scan_sessions` | staging cleanup | Db, Io, Internal | `2-3/task-28`, `2-3/task-29`, `2-3/task-30` | Real Core |
| S1-33 | file-rename-sheet | C1-22 | `rename_file` | `files`, `change_log` | safe rename or index-only metadata | InvalidPath, Conflict, PermissionDenied | `2-3/task-32` | Real Core |
| S1-34 | file-delete-confirm | C1-23 | `delete_file`, `remove_index_entry` | `files`, `change_log` | Trash or index-only removal | FileNotFound, PermissionDenied, Io | `2-3/task-33` | Real Core |
| S1-35 | change-category-sheet | C1-24, C1-10 | `preview_move_to_category`, `move_to_category` | `files`, `change_log` | safe preview, safe move or index-only metadata | Classify, Conflict, PermissionDenied | `2-3/task-34`, `2-3/task-35`, `2-3/task-36` | Real Core |
| S1-36 | icloud-conflict-list | C1-25 | `list_icloud_conflicts` | conflict state, change_log | read conflicted copies only | ICloudPlaceholder, Io | `2-4/task-04` | Real Core |
| S1-37 | db-repair-confirm | C1-26, C1-16 | `repair_metadata`, `reindex_from_filesystem` | `scan_sessions`, `files` | metadata repair only | Db, PermissionDenied, Io | `2-4/task-05`, `2-4/task-06`, `2-4/task-07` | Real Core |

## Core 能力到 Prompt

| 能力范围 | Prompt | 说明 |
|---|---|---|
| C1-01..C1-04 | `1-1/task-01` 到 `1-1/task-19` | Repo path、init/adopt、config |
| C1-05..C1-10 | `1-2/task-01` 到 `1-2/task-29` | classify、copy/move/index import、重复与同名冲突 |
| C1-11..C1-15 | `1-3/task-01` 到 `1-3/task-21` | list/detail/change log/note/tree |
| C1-16..C1-21 | `1-4/task-01` 到 `1-4/task-30` | recovery、sync、overview、error mapping |
| C1-22..C1-26 | `1-5/task-01` 到 `1-5/task-25` | rename、delete/remove index、change category、iCloud conflict list、metadata repair |
| S1-01..S1-11 | `2-1/task-01` 到 `2-1/task-34` | 首次启动与主窗口真实 Core 闭环 |
| S1-16..S1-24 | `2-2/task-01` 到 `2-2/task-27` | 导入、进度、结果和冲突 |
| S1-12..S1-15, S1-26..S1-35 | `2-3/task-01` 到 `2-3/task-37` | 详情、日志、笔记、设置、错误恢复、单文件操作 |
| S1-25, S1-36, S1-37 + watcher/overview | `2-4/task-01` 到 `2-4/task-08` | FSEvents、iCloud、概览、DB 修复 |

## Mock 边界

- 可 mock：纯静态欢迎页、设置集成页中 Stage 2+ 才启用的第三方入口。
- 不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。
- 临时 mock 必须在 task 汇报中标明“不能通过最终验收”，并在对应真实闭环 task 移除。

## Related

- [../ux/page-specs/stage-1-mvp.md](../ux/page-specs/stage-1-mvp.md)
- [../core/capability-specs/stage-1-mvp.md](../core/capability-specs/stage-1-mvp.md)
- [../api/core-api.md](../api/core-api.md)
