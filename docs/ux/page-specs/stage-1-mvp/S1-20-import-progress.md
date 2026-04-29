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
退出：全部成功且无跳过/失败时显示 toast 并返回来源主窗口；存在跳过/失败或用户点击 `View details` 时进入 `S1-21 import-result`；fatal import error 留在本页并显示恢复动作。

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

## 状态与规则

- 默认状态：导入队列开始后显示 toolbar 进度和 List banner；`Stop after current file` 可用。
- 单项失败不阻断批次。
- 失败行保留错误状态。
- `Stop after current file` 只取消尚未开始的剩余项；当前正在处理项到安全点后停止，已完成项保留。
- 强退后下次启动 recovery。
- 执行中禁用重复点击 Import；允许主窗口只读浏览，禁用正在导入队列相关的 Rename/Delete/Change Category。
- 当前项失败后继续下一项；队列结束后汇总到结果页。

## 交互

- 点击 `Stop after current file` 弹确认：`停止剩余导入？已完成的文件会保留，未开始的文件会取消，当前文件会处理到安全点后停止。`
- 选中临时行时 Detail 显示导入详情。
- 确认停止后按钮显示 `Stopping...`，不可重复点击；停止完成后进入 `S1-21 import-result`，标明 canceled/skipped 数量。
- 完成后：单文件全成功显示 toast；批量有失败/跳过/取消进入 `S1-21 import-result`；批量全成功可 toast 并提供 `View details`。

## 数据与依赖

- import progress callback。
- import queue state。
- staging recovery。
- list refresh notification。
- source route and import result summary。

## 验收清单

- 批量导入时进度可见。
- 失败项不影响成功项。
- 取消语义清楚。
- 停止剩余导入不会留下 staging 悬挂记录。
- 完成后进入 toast 或 S1-21 的条件清晰。

## 来源

- `docs/ux/drag-import-flow.md#导入执行期间-ui进度取消错误`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-17 import-single-sheet](S1-17-import-single-sheet.md)
- [S1-18 import-batch-sheet](S1-18-import-batch-sheet.md)
- [S1-19 import-folder-sheet](S1-19-import-folder-sheet.md)
- [S1-21 import-result](S1-21-import-result.md)
