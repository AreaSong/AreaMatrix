# Stage 1 MVP Core 能力索引

> Stage 1 目标是支撑 macOS 单机闭环：选择资料库 -> 初始化/接管 -> 拖入 -> 自动归类 -> 树状导航 -> 详情查看 -> 改动可追踪。

## 能力列表

| ID | 能力 | 类型 | 主要消费页面 | Prompt |
|---|---|---|---|---|
| C1-01 | [validate-repo-path](stage-1-mvp/C1-01-validate-repo-path.md) | Repo | S1-02, S1-03, S1-11, S1-32 | `1-1/task-01` |
| C1-02 | [init-empty-repo](stage-1-mvp/C1-02-init-empty-repo.md) | Repo | S1-04, S1-05, S1-07, S1-08 | `1-1/task-02` |
| C1-03 | [adopt-existing-repo](stage-1-mvp/C1-03-adopt-existing-repo.md) | Repo | S1-03, S1-04, S1-05, S1-10 | `1-1/task-03` |
| C1-04 | [load-update-config](stage-1-mvp/C1-04-load-update-config.md) | Config | S1-26, S1-27, S1-28, S1-30 | `1-1/task-04` |
| C1-05 | [classify-preview](stage-1-mvp/C1-05-classify-preview.md) | Classify | S1-16, S1-17, S1-18, S1-19, S1-28 | `1-2/task-01` |
| C1-06 | [import-copy-file](stage-1-mvp/C1-06-import-copy-file.md) | Import | S1-17, S1-20, S1-21, S1-09 | `1-2/task-02` |
| C1-07 | [import-move-file](stage-1-mvp/C1-07-import-move-file.md) | Import | S1-17, S1-20, S1-21, S1-26 | `1-2/task-03` |
| C1-08 | [import-index-file](stage-1-mvp/C1-08-import-index-file.md) | Import | S1-17, S1-20, S1-21, S1-27 | `1-2/task-04` |
| C1-09 | [detect-duplicate](stage-1-mvp/C1-09-detect-duplicate.md) | Conflict | S1-22, S1-24 | `1-2/task-05` |
| C1-10 | [resolve-name-conflict](stage-1-mvp/C1-10-resolve-name-conflict.md) | Conflict | S1-23, S1-24 | `1-2/task-06` |
| C1-11 | [list-files](stage-1-mvp/C1-11-list-files.md) | Query | S1-08, S1-09, S1-10, S1-15 | `1-3/task-01` |
| C1-12 | [get-file-detail](stage-1-mvp/C1-12-get-file-detail.md) | Query | S1-12, S1-15 | `1-3/task-02` |
| C1-13 | [list-change-log](stage-1-mvp/C1-13-list-change-log.md) | Query | S1-13, S1-21, S1-32 | `1-3/task-03` |
| C1-14 | [read-write-note](stage-1-mvp/C1-14-read-write-note.md) | Note | S1-14 | `1-3/task-04` |
| C1-15 | [build-tree](stage-1-mvp/C1-15-build-tree.md) | Query | S1-08, S1-09, S1-10 | `1-3/task-05` |
| C1-16 | [recover-on-startup](stage-1-mvp/C1-16-recover-on-startup.md) | Recovery | S1-05, S1-10, S1-32 | `1-4/task-01` |
| C1-17 | [sync-external-created](stage-1-mvp/C1-17-sync-external-created.md) | Sync | S1-09, S1-10, S1-13 | `1-4/task-02` |
| C1-18 | [sync-external-renamed](stage-1-mvp/C1-18-sync-external-renamed.md) | Sync | S1-09, S1-13 | `1-4/task-03` |
| C1-19 | [sync-external-removed](stage-1-mvp/C1-19-sync-external-removed.md) | Sync | S1-09, S1-11, S1-13 | `1-4/task-04` |
| C1-20 | [overview-generated](stage-1-mvp/C1-20-overview-generated.md) | Overview | S1-27, S1-30 | `1-4/task-05` |
| C1-21 | [error-mapping](stage-1-mvp/C1-21-error-mapping.md) | Error | S1-03, S1-06, S1-11, S1-25, S1-32 | `1-4/task-06` |
| C1-22 | [rename-file](stage-1-mvp/C1-22-rename-file.md) | File Action | S1-33 | `1-5/task-01` |
| C1-23 | [delete-remove-index](stage-1-mvp/C1-23-delete-remove-index.md) | File Action | S1-34 | `1-5/task-02` |
| C1-24 | [move-to-category](stage-1-mvp/C1-24-move-to-category.md) | File Action | S1-35 | `1-5/task-03` |
| C1-25 | [list-icloud-conflicts](stage-1-mvp/C1-25-list-icloud-conflicts.md) | Conflict | S1-36, S1-25 | `1-5/task-04` |
| C1-26 | [repair-reindex-metadata](stage-1-mvp/C1-26-repair-reindex-metadata.md) | Recovery | S1-37, S1-11, S1-32 | `1-5/task-05` |

## 内部能力

Stage 1 暂无“完全无 UI 消费”的 Core 能力。`C1-16` recovery、`C1-21` error mapping 和 `C1-26` metadata repair 虽然偏内部，但必须被 UI 启动、错误页、修复页与验收 prompt 消费。

## 切片原则

- 一个能力最多覆盖一个主动作或一个 Core 闭环。
- 能力可以依赖前置能力，但不得偷偷实现后续能力。
- UI prompt 只能把已完成或同任务绑定的能力接入页面；不能用 mock 通过最终验收。
