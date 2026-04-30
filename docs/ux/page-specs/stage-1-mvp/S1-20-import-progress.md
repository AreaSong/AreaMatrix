# S1-20 import-progress - 导入进行中

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-20
> 页面类型：导入
> 页面文件：`S1-20-import-progress.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 导入流程
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/`
- **建议组件**：`ImportProgressView`、`ImportQueueBanner`、`ImportingListRow`
- **实现说明**：导入进行中不应全局阻塞主窗口，用户仍可浏览资料库。

## 页面背景

用户点击 Import 后，Core 正在 staging、hash、分类、复制/移动、写 DB 和生成概览。

入口：`S1-17 import-single-sheet`、`S1-18 import-batch-sheet`、`S1-19 import-folder-sheet` 点击 Import。
退出：全部成功且无跳过/失败时显示 toast 并返回来源主窗口；存在跳过/失败或用户点击 `View details` 时进入 `S1-21 import-result`；队列级 fatal import error 留在本页，停止队列，不启动剩余项，并显示队列级错误面板。

## 页面功能

- 显示总进度。
- 显示当前处理文件和阶段。
- 在 List 插入临时导入行。
- 支持查看详情和取消剩余任务。

## 布局与内容

Toolbar 状态：`Importing 7 / 20`。

List 顶部 banner：

```text
正在导入 20 个文件
已完成 7，失败 1，剩余 12
当前：docs/contracts/合同.pdf
```

按钮：`View details`、`Stop after current file`。

临时行状态：

- Pending
- Copying
- Hashing
- Classifying
- Writing index
- Done
- Failed

队列级 fatal import error 面板：

```text
导入已暂停
已完成 7，失败 1，未开始 12
当前失败项：docs/contracts/合同.pdf
错误代码：StorageWriteFailed

已完成的文件会保留。未开始的文件不会自动导入。
AreaMatrix 会先确认 staging 状态，再允许重试当前项。
```

按钮：

- `Retry current item`
- `Stop and view results`
- `Collect Diagnostics...`
- `Open repository in Finder`，仅 repo path 仍可访问时显示。

## 状态与规则

- 默认状态：导入队列开始后显示 toolbar 进度和 List banner；`Stop after current file` 可用。
- 单项失败不阻断批次。
- 失败行保留错误状态。
- `Stop after current file` 只取消尚未开始的剩余项；当前正在处理项到安全点后停止，已完成项保留。
- 强退后下次启动 recovery。
- 执行中禁用重复点击 Import；允许主窗口只读浏览，禁用正在导入队列相关的 Rename/Delete/Change Category。
- 当前项失败后继续下一项；队列结束后汇总到结果页。
- 队列级 fatal import error 指导入队列无法安全继续的错误，不包含普通单项失败。
- fatal error 出现时，已完成项保留，当前项标记为 Failed，未开始项不再处理。
- staging 状态未确认前禁用 `Retry current item`，显示 `Checking recovery state...`。
- `Retry current item` 只在 Core / staging recovery 明确当前失败项可安全重试时启用。
- fatal error 不得自动清理已完成文件，不得静默重跑队列，不得启动未开始项。
- fatal error 诊断导出不包含用户文件内容，不自动上传，路径和用户名会脱敏。
- 空态不适用：本页只在已有导入队列时出现；队列为空时返回来源主窗口或结果页。

## 交互

- 点击 `Stop after current file` 弹确认：`停止剩余导入？已完成的文件会保留，未开始的文件会取消，当前文件会处理到安全点后停止。`
- 选中临时行时 Detail 显示导入详情。
- 确认停止后按钮显示 `Stopping...`，不可重复点击；停止完成后进入 `S1-21 import-result`，标明 canceled/skipped 数量。
- fatal error 面板中点击 `Retry current item` 只重试当前失败项；重试成功后恢复队列并继续处理剩余项。
- fatal error 面板中点击 `Stop and view results` 进入 `S1-21 import-result`，结果摘要必须标明 imported / failed / stopped / pending 数量。
- fatal error 面板中点击 `Collect Diagnostics...` 弹隐私说明后导出本地诊断包，不改变 import queue、不清理 staging、不修改用户文件。
- fatal error 面板中点击 `Open repository in Finder` 只 reveal repo 根目录，不执行恢复或清理。
- fatal error 后如果 recovery check 失败，保留本面板，禁用 Retry，提供 `Stop and view results` / `Collect Diagnostics...`。
- 完成后：单文件全成功显示 toast；批量有失败/跳过/取消进入 `S1-21 import-result`；批量全成功可 toast 并提供 `View details`。

## 可访问性

- 进度必须读出已完成、失败、剩余数量和当前文件名。
- `Stop after current file` 的取消语义需要文本说明。
- 失败行需要可读错误文本，不能只靠红色状态。

## 数据与依赖

- import progress callback。
- import queue state。
- staging recovery。
- fatal import error object。
- staging recovery check result。
- retry eligibility for current failed item。
- list refresh notification。
- source route and import result summary。

## 验收清单

- 批量导入时进度可见。
- 失败项不影响成功项。
- 取消语义清楚。
- 停止剩余导入不会留下 staging 悬挂记录。
- 完成后进入 toast 或 S1-21 的条件清晰。
- 队列级 fatal import error 会显示 `导入已暂停` 面板。
- fatal error 后已完成项保留，未开始项不会自动导入。
- Retry current item / Stop and view results / Collect Diagnostics 路径都可验证。

## 来源

- [docs/ux/drag-import-flow.md](../../drag-import-flow.md) 的“导入执行期间 UI（进度、取消、错误）”章节（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-17 import-single-sheet](S1-17-import-single-sheet.md)
- [S1-18 import-batch-sheet](S1-18-import-batch-sheet.md)
- [S1-19 import-folder-sheet](S1-19-import-folder-sheet.md)
- [S1-21 import-result](S1-21-import-result.md)
