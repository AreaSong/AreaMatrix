# Stage 1 MVP 逐页 UI 开发规格

> Stage 1 目标：在 macOS 上完成“选择资料库 -> 接管/初始化 -> 拖入 -> 自动归类 -> 树状导航 -> 详情查看 -> 改动可追踪”的单机闭环。
>
> 本文是开发落地规格，不替代上游 UX / 架构文档。实现冲突时，优先回到来源文档修正。
>
> 阅读时长：约 35 分钟。

---

## 使用方式

本文件只保留阶段级索引、通用约束和验收矩阵。逐页开发时，请打开下方单页文件；每个页面文件都可以独立交给 IDE / agent 实现。

---

## 页面文件目录

| ID | 页面 | 类型 | 单页规格 |
|---|---|---|---|
| S1-01 | welcome - 欢迎页 | 首次启动 | [S1-01-welcome.md](stage-1-mvp/S1-01-welcome.md) |
| S1-02 | choose-path - 选择资料库位置 | 首次启动 | [S1-02-choose-path.md](stage-1-mvp/S1-02-choose-path.md) |
| S1-03 | validate-path - 校验与风险提示 | 首次启动 | [S1-03-validate-path.md](stage-1-mvp/S1-03-validate-path.md) |
| S1-04 | confirm-init - 初始化确认 | 首次启动 | [S1-04-confirm-init.md](stage-1-mvp/S1-04-confirm-init.md) |
| S1-05 | initializing - 初始化 / 接管中 | 首次启动 | [S1-05-initializing.md](stage-1-mvp/S1-05-initializing.md) |
| S1-06 | init-failed - 初始化失败 | 首次启动 | [S1-06-init-failed.md](stage-1-mvp/S1-06-init-failed.md) |
| S1-07 | init-done - 初始化完成 | 首次启动 | [S1-07-init-done.md](stage-1-mvp/S1-07-init-done.md) |
| S1-08 | main-empty - 空资料库主窗口 | 主窗口 | [S1-08-main-empty.md](stage-1-mvp/S1-08-main-empty.md) |
| S1-09 | main-list - 正常文件列表 | 主窗口 | [S1-09-main-list.md](stage-1-mvp/S1-09-main-list.md) |
| S1-10 | main-loading - 加载 / 扫描状态 | 主窗口 | [S1-10-main-loading.md](stage-1-mvp/S1-10-main-loading.md) |
| S1-11 | main-repo-error - 主窗口资料库错误 | 主窗口 | [S1-11-main-repo-error.md](stage-1-mvp/S1-11-main-repo-error.md) |
| S1-12 | detail-meta - 文件元数据详情 | 详情 | [S1-12-detail-meta.md](stage-1-mvp/S1-12-detail-meta.md) |
| S1-13 | detail-log - 改动时间线 | 详情 | [S1-13-detail-log.md](stage-1-mvp/S1-13-detail-log.md) |
| S1-14 | detail-note - 伴生笔记 | 详情 | [S1-14-detail-note.md](stage-1-mvp/S1-14-detail-note.md) |
| S1-15 | detail-multi - 多选摘要 | 详情 | [S1-15-detail-multi.md](stage-1-mvp/S1-15-detail-multi.md) |
| S1-16 | drag-hover - 拖拽 Hover 投放状态 | 导入 | [S1-16-drag-hover.md](stage-1-mvp/S1-16-drag-hover.md) |
| S1-17 | import-single-sheet - 单文件导入确认 | 导入 | [S1-17-import-single-sheet.md](stage-1-mvp/S1-17-import-single-sheet.md) |
| S1-18 | import-batch-sheet - 多文件导入确认 | 导入 | [S1-18-import-batch-sheet.md](stage-1-mvp/S1-18-import-batch-sheet.md) |
| S1-19 | import-folder-sheet - 文件夹递归导入确认 | 导入 | [S1-19-import-folder-sheet.md](stage-1-mvp/S1-19-import-folder-sheet.md) |
| S1-20 | import-progress - 导入进行中 | 导入 | [S1-20-import-progress.md](stage-1-mvp/S1-20-import-progress.md) |
| S1-21 | import-result - 导入结果摘要 | 导入 | [S1-21-import-result.md](stage-1-mvp/S1-21-import-result.md) |
| S1-22 | conflict-duplicate - 内容重复冲突 | 冲突 | [S1-22-conflict-duplicate.md](stage-1-mvp/S1-22-conflict-duplicate.md) |
| S1-23 | conflict-name - 同名不同内容冲突 | 冲突 | [S1-23-conflict-name.md](stage-1-mvp/S1-23-conflict-name.md) |
| S1-24 | replace-confirm - Replace 二次确认 | 冲突 | [S1-24-replace-confirm.md](stage-1-mvp/S1-24-replace-confirm.md) |
| S1-25 | icloud-conflict-min - iCloud 冲突最小处理 | 冲突 | [S1-25-icloud-conflict-min.md](stage-1-mvp/S1-25-icloud-conflict-min.md) |
| S1-26 | settings-general - 通用设置 | 设置 | [S1-26-settings-general.md](stage-1-mvp/S1-26-settings-general.md) |
| S1-27 | settings-repository - 资料库设置 | 设置 | [S1-27-settings-repository.md](stage-1-mvp/S1-27-settings-repository.md) |
| S1-28 | settings-classifier - 分类规则设置 | 设置 | [S1-28-settings-classifier.md](stage-1-mvp/S1-28-settings-classifier.md) |
| S1-29 | settings-integrations - 集成设置 | 设置 | [S1-29-settings-integrations.md](stage-1-mvp/S1-29-settings-integrations.md) |
| S1-30 | settings-advanced - 高级设置 | 设置 | [S1-30-settings-advanced.md](stage-1-mvp/S1-30-settings-advanced.md) |
| S1-31 | settings-about - 关于 | 设置 | [S1-31-settings-about.md](stage-1-mvp/S1-31-settings-about.md) |
| S1-32 | error-recovery - 错误与恢复共享 UI 组件规格 | 共享错误组件 / 页面区域 | [S1-32-error-recovery.md](stage-1-mvp/S1-32-error-recovery.md) |
| S1-33 | file-rename-sheet - 单文件重命名 | 文件操作 | [S1-33-file-rename-sheet.md](stage-1-mvp/S1-33-file-rename-sheet.md) |
| S1-34 | file-delete-confirm - 删除 / 移除索引确认 | 文件操作 | [S1-34-file-delete-confirm.md](stage-1-mvp/S1-34-file-delete-confirm.md) |
| S1-35 | change-category-sheet - 单文件改分类 | 文件操作 | [S1-35-change-category-sheet.md](stage-1-mvp/S1-35-change-category-sheet.md) |
| S1-36 | icloud-conflict-list - iCloud 冲突列表 | 冲突 | [S1-36-icloud-conflict-list.md](stage-1-mvp/S1-36-icloud-conflict-list.md) |
| S1-37 | db-repair-confirm - 数据库修复确认 | 错误恢复 | [S1-37-db-repair-confirm.md](stage-1-mvp/S1-37-db-repair-confirm.md) |

---

## 通用约束

- macOS UI 使用原生窗口、sheet、popover、toolbar、sidebar、table 和 segmented control 语义。
- 主窗口使用三栏结构：Tree / List / Detail。
- 设置页 `S1-26` 至 `S1-31` 统一由 macOS Settings tab 进入；阶段跳转图中的无入边不代表孤立页面。
- Stage 1 只实现本索引列出的单机能力；后续阶段能力不得写成必做。主窗口只允许当前列表过滤或排序，不提供跨库检索。
- 任何删除或替换都默认安全：Trash / change_log / 二次确认。
- 非空目录接管时，UI 必须反复表达“不移动、不重命名、不删除、不覆盖已有文件”。
- 所有自动生成内容默认只写 `.areamatrix/generated/`，不得暗示会覆盖 `README.md`。
- 诊断导出默认不包含用户文件内容，不自动上传，路径和用户名按隐私规则脱敏。
- 单页规格中若空态、加载态或错误态不适用，必须在该页 `状态与规则` 中写明“不适用”和原因；共享组件 `S1-32` 只定义可复用错误形态，不作为独立导航页面验收。
- 每个单页必须写明默认状态、禁用条件、空态、加载态、错误态、入口退出、数据依赖、验收清单和可访问性要求。
- `S1-24 replace-confirm` 只确认 Replace 策略并返回来源 ImportSheet 标记 `Replace confirmed`；真正文件替换只能在来源 ImportSheet 最终点击 Import 后，经 `S1-20 import-progress` 执行。

---

## 页面跳转图

```text
S1-01 welcome
  -> S1-02 choose-path
  -> S1-03 validate-path
       -> existing repo: S1-10 main-loading -> S1-08 main-empty / S1-09 main-list
       -> create/adopt: S1-04 confirm-init -> S1-05 initializing
            -> success: S1-07 init-done -> S1-10 -> S1-08 / S1-09
            -> fatal / interrupted: S1-06 init-failed -> S1-05 retry / S1-02 change path / quit
       -> DB corrupted / repair-needed: S1-37 db-repair-confirm
       -> schema / repo open critical error: S1-11 main-repo-error

S1-08 main-empty / S1-09 main-list
  -> S1-12 detail-meta -> S1-13 detail-log / S1-14 detail-note
  -> multi-select: S1-15 detail-multi
  -> drag hover: S1-16 drag-hover -> S1-17 / S1-18 / S1-19
  -> file actions: S1-33 rename / S1-34 delete-confirm / S1-35 change-category

S1-17 single / S1-18 batch / S1-19 folder
  -> conflicts: S1-22 duplicate / S1-23 name
  -> confirm replace strategy: S1-24 replace-confirm -> back to source ImportSheet
  -> final import: S1-20 import-progress
  -> S1-21 import-result or toast

S1-12 detail-meta / S1-29 settings-integrations
  -> S1-36 icloud-conflict-list
  -> S1-25 icloud-conflict-min
  -> back to source page

S1-11 / S1-27 / S1-32
  -> S1-37 db-repair-confirm
  -> S1-10 main-loading
  -> S1-09 main-list

Settings tabs:
  S1-26 general / S1-27 repository / S1-28 classifier /
  S1-29 integrations / S1-30 advanced / S1-31 about
```

---

## Stage 1 验收矩阵

- 首次启动：空目录初始化、非空目录接管、不可写路径、iCloud 路径、中断恢复均有页面路径。
- 主窗口：无 repo 不显示主界面；空库有导入入口；有文件时三栏联动稳定。
- 导入：单文件、多文件、文件夹、取消、失败、结果摘要均可见且不丢原文件。
- 冲突：重复默认跳过；同名默认保留两份；Replace 必须二次确认并走 Trash。
- 文件操作：单文件重命名、删除、移除索引、改分类都有确认、失败恢复和 change_log 路径。
- 设置：资料库路径、默认存储模式、概览输出、分类规则、诊断入口和 iCloud 冲突入口可发现。
- 错误：DB locked 不阻断 Tree；DB corrupted 进入修复确认；诊断入口统一且不泄露用户文件内容。

---

## Related

- [../first-launch.md](../first-launch.md)
- [../ui-states.md](../ui-states.md)
- [../drag-import-flow.md](../drag-import-flow.md)
- [../dedup-conflict.md](../dedup-conflict.md)
- [../settings-panel.md](../settings-panel.md)
- [../error-messages.md](../error-messages.md)
- [../../roadmap/stage-1-mvp.md](../../roadmap/stage-1-mvp.md)
