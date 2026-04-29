# S1-19 import-folder-sheet - 文件夹递归导入确认

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-19
> 页面类型：导入
> 页面文件：`S1-19-import-folder-sheet.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 导入流程
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/`
- **建议组件**：`FolderImportSheet`、`FolderPreflightView`、`IgnoredRulesSummaryView`
- **实现说明**：文件夹导入必须先预扫描，确认前不复制、不移动。

## 页面背景

用户拖入一个文件夹。AreaMatrix 需要递归展开文件，并告诉用户将导入什么、跳过什么、采用什么策略。

入口：`S1-16 drag-hover` drop 一个或多个文件夹，或 File -> Import... 选择文件夹。
退出：Cancel 返回来源主窗口且不写文件；Import Folder 进入 `S1-20 import-progress`；预扫描失败可 Retry 或 Cancel。

## 页面功能

- 显示文件夹路径、文件数、总大小、子文件夹数。
- 展示默认排除规则。
- 设置导入目标和存储模式。
- 展示预估重复和冲突，并在本 sheet 内完成逐项处理。

## 布局与内容

标题：`导入文件夹`

文件夹信息：

- 文件夹：`~/Downloads/客户A/`
- 已发现：`128 个文件`
- 总大小：`1.8 GB`
- 子文件夹：`12 个`

默认排除：

- `.DS_Store`
- `.git/`
- `.areamatrix/`
- `node_modules/`
- 隐藏文件
- 符号链接不跟随

批量设置：

- 导入到：自动分类 / 当前分类 / 具体分类
- 存储模式：Copy（默认） / Move / Index-only
- 目录处理说明：Stage 1 不提供复杂目录结构策略；最终落位由 drop 目标、用户选择分类和 Copy/Move/Index 共同决定。

文件明细表，点击 `View files...` 后展开：

- 表格列：File、Relative path、Suggested category、Suggested name、Status
- Status：OK、DUP、NAME、ICLOUD、ERROR、BLOCKED

冲突面板，点击 `Review conflicts` 后展开：

- 标题：`Review folder conflicts`
- 摘要：`4 duplicates · 2 name conflicts · 1 blocked`
- 表格列：File、Conflict、Existing item、Incoming resolution、Strategy、Status、Action
- DUP 默认 `Skip`
- NAME 默认 `Keep both (auto-number)`
- `Replace` 仅当 `allowReplaceDuringImport=true` 时显示
- Action：`Show existing file`、`Rename incoming...`、`Confirm Replace...`

按钮：`View files...`、`Review conflicts`、`Cancel`、`Import Folder`。

iCloud placeholder 摘要，仅预扫描发现占位符时显示：

- `12 files are still in iCloud`
- 按钮：`Download & retry scan`、`Switch to local repo...`

## 状态与规则

- 预扫描中显示 spinner 和当前扫描路径，禁用 Import Folder。
- 没有可导入文件时显示空态。
- 冲突预检未完成时禁用 Import Folder，并显示 `Checking conflicts...`。
- `replaceOptionVisibility` 由 `allowReplaceDuringImport` 和 Trash 可用性共同决定：默认 `hidden`，开启设置后为 `enabled`，Trash 不可用时为 `disabled`。
- 任何 Replace 行都必须先通过 `S1-24 replace-confirm`；未确认 Replace 时禁用 Import Folder。
- 单个冲突行状态为 BLOCKED 时禁用 Import Folder；用户必须改为 Skip / Keep both、重命名导入文件、完成 Replace 二次确认，或取消本次导入。
- Move 模式说明源文件夹中的文件会被移走。
- Index-only 模式说明只记录原位置，源文件移动/删除会导致缺失。
- 符号链接默认不跟随，避免循环。
- 权限错误或遍历失败显示错误摘要、已发现数量、`Retry scan` / `Cancel`；不得开始导入。
- iCloud placeholder：占位符文件不进入可导入就绪列表，必须显示数量和路径摘要；不得静默跳过。
- 全部可见文件都是 iCloud placeholder 时禁用 `Import Folder`。
- 部分文件为 iCloud placeholder 时，允许导入已就绪文件，但必须在结果页报告未下载项；用户可先执行 `Download & retry scan`。
- iCloud 下载中禁用 `Import Folder` 和重复下载动作，保留 `Cancel`。
- iCloud 下载失败时留在本 sheet，显示失败数量、错误原因和 `Download & retry scan` / `Switch to local repo...`。
- 高级选项中的隐藏文件和符号链接开关变化后必须重新预扫描，重新预扫描期间禁用 Import Folder。
- Cancel 在任何预扫描状态都可用，且不写文件、不写 DB。
- 本页没有直接危险按钮；Replace 只通过 `Confirm Replace...` 进入 `S1-24 replace-confirm`。

## 交互

- View files 展开文件明细表。
- Review conflicts 在本 sheet 内展开预扫描发现的冲突表，不跳转到独立页面。
- 选择 DUP 行的 Skip 后，该文件不会进入导入队列；结果页必须报告 skipped。
- 选择 NAME 行的 Keep both 后，Incoming resolution 显示最终自动编号名称。
- 点击 `Rename incoming...` 就地显示文件名输入框；名称非法、为空或仍冲突时该行变为 BLOCKED。
- 点击 `Confirm Replace...` 打开 `S1-24 replace-confirm`；Cancel 返回本 sheet 且该行保持原策略，确认成功后该行标记 `Replace confirmed`。
- 高级选项默认折叠，可启用隐藏文件等。
- `Download & retry scan` 触发 iCloud 下载后重新预扫描；重新预扫描不得清空用户已选择的存储模式。
- `Switch to local repo...` 进入 `S1-02 choose-path` / `S1-03 validate-path`，新 repo 成功打开前不修改当前 repo。
- Import Folder 后只把 `OK`、NAME 的 Keep both / rename、DUP 的 Keep both / Replace confirmed 和已就绪文件放入导入队列并进入导入进度；DUP Skip 与未下载 iCloud 项进入结果摘要，不进入导入队列。
- Cancel 关闭 sheet，回到来源主窗口，不写文件。
- Retry scan 只重新遍历当前文件夹，不改变用户已选择的存储模式。

## 数据与依赖

- 目录遍历。
- ignore.yaml。
- conflict preview。
- `allowReplaceDuringImport` settings value。
- Trash availability for Replace。
- per-row conflict resolution state。
- iCloud placeholder detection、download progress 和 retry result。
- import batch API。
- source route，用于 Cancel 后返回。

## 验收清单

- 预扫描完成前不能导入。
- 默认排除规则可见。
- 确认前无文件系统写入。
- 冲突表有明确列、默认策略、逐项动作和 BLOCKED 状态。
- Replace 默认隐藏；开启设置且 Trash 可用后才可进入 `S1-24 replace-confirm`。
- 未确认 Replace 或存在 BLOCKED 行时不能 Import Folder。
- 预扫描失败、无可导入文件、Move/Index-only 风险提示都有明确 UI。
- iCloud placeholder 文件必须可见、可下载重试或明确进入结果页，不静默处理。

## 来源

- `docs/ux/drag-import-flow.md#文件夹拖入folder-import`（直接）。
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
