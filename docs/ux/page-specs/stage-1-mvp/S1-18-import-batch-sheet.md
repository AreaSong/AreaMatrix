# S1-18 import-batch-sheet - 多文件导入确认

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-18
> 页面类型：导入
> 页面文件：`S1-18-import-batch-sheet.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 导入流程
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/`
- **建议组件**：`BatchImportSheet`、`BatchImportItemTable`、`BatchImportOptionsView`
- **实现说明**：批量导入必须先总览后细节，不能弹 N 个单文件对话框。

## 页面背景

用户一次拖入多个文件。AreaMatrix 需要让用户确认批量策略，同时允许少量项目逐项调整分类、名称或冲突处理策略。

入口：`S1-16 drag-hover` drop 多个文件，或 File -> Import... 选择多个文件。
退出：Cancel 返回来源主窗口且不写文件；Import 进入 `S1-20 import-progress`；预览失败可 Retry 或 Cancel。

## 页面功能

- 展示文件总数、总大小、来源。
- 设置批量分类策略、存储模式、命名策略。
- 展示预计重复和重名冲突数量，并在本 sheet 内完成逐项处理。
- 展开查看逐项预览。

## 布局与内容

标题：`导入 20 个文件`

摘要：

- 总大小：`512 MB`
- 来源：`Finder 拖入`
- 预计重复：`2 个`
- 重名冲突：`1 个`

批量设置：

- 导入到：`自动分类（推荐）` / inbox / docs / code / design / finance / media
- 存储模式：Copy（默认） / Move / Index-only
- 命名策略：使用建议命名（默认） / 保留原名 / 仅标准化字符 / 统一前缀

项目列表 disclosure：`查看 20 个项目`

表格列：图标、原文件名、建议分类、建议新名称、状态。

状态标签：OK、DUP、NAME、ICLOUD、ERROR、BLOCKED。

冲突面板，仅点击 `Review conflicts` 或存在阻断项时展开：

- 标题：`Review conflicts`
- 摘要：`2 duplicates · 1 name conflict · 0 blocked`
- 表格列：File、Conflict、Existing item、Incoming resolution、Strategy、Status、Action
- Conflict：`Duplicate content` / `Same name, different content`
- Strategy：
  - DUP 默认 `Skip`
  - NAME 默认 `Keep both (auto-number)`
  - `Replace` 仅当 `allowReplaceDuringImport=true` 时显示
- Action：
  - `Show existing file`
  - `Rename incoming...`，只影响导入文件名
  - `Confirm Replace...`，打开 `S1-24 replace-confirm`

Replace 不可用说明：

- `allowReplaceDuringImport=false`：不显示 Replace 选项，行内显示 `Replace hidden by Advanced setting`
- `allowReplaceDuringImport=true` 但 Trash 不可用：显示 disabled Replace 和 `Replace requires system Trash`

iCloud placeholder 摘要：

- `3 items need iCloud download`
- 行状态显示 `ICLOUD`。
- 行操作：`Download & retry`。

按钮：`Cancel`、`Import`。

## 状态与规则

- 全部项目错误时禁用 Import。
- 加载态：预览/冲突预检未完成时禁用 Import，并显示 `Preparing preview...`。
- 重复默认跳过。
- 同名不同内容默认保留两份。
- `replaceOptionVisibility` 由 `allowReplaceDuringImport` 和 Trash 可用性共同决定：默认 `hidden`，开启设置后为 `enabled`，Trash 不可用时为 `disabled`。
- 任何 Replace 行都必须先通过 `S1-24 replace-confirm`；未确认 Replace 时禁用 Import。
- 单个冲突行状态为 BLOCKED 时禁用 Import；用户必须改为 Skip / Keep both、重命名导入文件、完成 Replace 二次确认，或取消本次导入。
- Move 模式显示黄色风险提示。
- Index-only 模式显示来源移动/删除会导致缺失的说明。
- iCloud placeholder 项默认不可导入；未下载项计入 skipped/pending，不得静默忽略。
- 全部项目都是 iCloud placeholder 且未下载时禁用 Import。
- 只有部分项目为 iCloud placeholder 时，Import 可继续处理已就绪项目，但必须在结果页报告未下载项；用户也可先 `Download all & retry preview`。
- 批量下载中禁用 Import 和重复下载动作，保留 Cancel。
- 下载失败项保留在列表中，状态为 ERROR 或 ICLOUD，显示 `Download & retry` / `Switch to local repo...`。
- Cancel 在任何预览状态都可用，且不写文件、不写 DB。
- 单项 ERROR 可保留在列表中；只要至少一个可导入项可用，Import 可继续，并在结果页报告失败项。
- 空态不适用：本 sheet 只在至少两个输入项时打开；没有可导入项按全部错误或全部 iCloud pending 处理。
- 本页没有直接危险按钮；Replace 只通过 `Confirm Replace...` 进入 `S1-24 replace-confirm`。

## 交互

- 选择具体分类时，覆盖所有项目自动分类。
- 展开列表后可逐项调整分类、名称或冲突处理策略。
- Review conflicts 在本 sheet 内展开冲突表，不跳转到独立页面。
- 选择 DUP 行的 Skip 后，该项不会进入导入队列；结果页必须报告 skipped。
- 选择 NAME 行的 Keep both 后，Incoming resolution 显示最终自动编号名称。
- 点击 `Rename incoming...` 就地显示文件名输入框；名称非法、为空或仍冲突时该行变为 BLOCKED。
- 点击 `Confirm Replace...` 打开 `S1-24 replace-confirm`；Cancel 返回本 sheet 且该行保持原策略，确认成功后回到本 sheet，并将该行标记为 `Replace confirmed`。
- `Download all & retry preview` 先触发 iCloud 下载，再重新做 batch preview；失败项仍保留并可逐项重试。
- `Switch to local repo...` 进入 `S1-02 choose-path` / `S1-03 validate-path`，新 repo 成功打开前不修改当前 repo。
- Import 后只把 `OK`、NAME 的 Keep both / rename、DUP 的 Keep both / Replace confirmed 和已就绪文件放入导入队列并进入导入进度；DUP Skip 与未下载 iCloud 项进入结果摘要，不进入导入队列。
- Cancel 关闭 sheet，回到来源主窗口，不写文件。
- 预览失败时显示 `Retry preview` / `Cancel`；Retry 只重新做 batch preview。

## 可访问性

- 批量表格每行必须读出文件名、状态、建议分类和处理策略。
- `OK` / `DUP` / `NAME` / `ICLOUD` / `ERROR` / `BLOCKED` 不能只靠颜色表达。
- `Confirm Replace...`、逐项 retry、Cancel、Import 都必须支持键盘访问。

## 数据与依赖

- batch preview adapter：Swift 平台层把多个 source URL 预扫描为行状态，并组合 Core `predict_category`、duplicate/conflict precheck、ignore rules 与文件可读性结果。
- classifier 批量预测。
- conflict precheck adapter：输出每行 `OK` / `DUP` / `NAME` / `ICLOUD` / `ERROR` / `BLOCKED`；若 Core API 尚无独立 preview，必须以 capability spec 定义的错误和导入 dry-run 等价结果为准，不得靠产品口头确认。
- ignore rules。
- `allowReplaceDuringImport` settings value。
- Trash availability for Replace。
- per-row conflict resolution state。
- iCloud placeholder detection、download progress 和 retry result，由 Swift 平台层提供；未下载项不得进入 Core 导入队列。
- source route，用于 Cancel 后返回。

## 验收清单

- 20 个文件可一键导入。
- 能看到重复和重名冲突数量。
- 批量导入不会弹 20 次对话框。
- 冲突表有明确列、默认策略、逐项动作和 BLOCKED 状态。
- Replace 默认隐藏；开启设置且 Trash 可用后才可进入 `S1-24 replace-confirm`，确认后仍需用户点击本 sheet 的最终 `Import`。
- 未确认 Replace 或存在 BLOCKED 行时不能 Import。
- 预览中、全部错误、Move/Index-only 风险提示和 Cancel 路径都可验证。
- iCloud placeholder 有批量和逐项下载路径；未下载项不会被静默吞掉。

## 来源

- `docs/ux/drag-import-flow.md#importsheet多文件版batch`（直接）。
- `docs/ux/error-messages.md#4-coreerroricloudplaceholdericloud-占位符`（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-16 drag-hover](S1-16-drag-hover.md)
- [S1-20 import-progress](S1-20-import-progress.md)
- [S1-21 import-result](S1-21-import-result.md)
- [S1-24 replace-confirm](S1-24-replace-confirm.md)
- [S1-02 choose-path](S1-02-choose-path.md)
- [S1-03 validate-path](S1-03-validate-path.md)
