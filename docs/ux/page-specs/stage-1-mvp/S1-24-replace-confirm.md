# S1-24 replace-confirm - Replace 二次确认

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-24
> 页面类型：冲突
> 页面文件：`S1-24-replace-confirm.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 导入冲突处理
- **建议目录**：`apps/macos/AreaMatrix/Features/Import/Conflicts/`
- **建议组件**：`ReplaceConfirmSheet`
- **实现说明**：唯一目标是二次确认危险替换。旧文件必须去 Trash，不允许永久删除。

## 页面背景

用户在重复或同名冲突中选择了 Replace。AreaMatrix 必须明确说明哪个文件被替换、用哪个文件替换、旧文件去哪里。

入口：`S1-22 conflict-duplicate`、`S1-23 conflict-name`、`S1-17 import-single-sheet`、`S1-18 import-batch-sheet` 或 `S1-19 import-folder-sheet` 中已显示且可选的 Replace。
退出：Cancel 返回来源冲突区域；Replace 确认成功后返回来源 ImportSheet，并把当前冲突项标记为 `Replace confirmed`；失败留在本 sheet。只有用户随后在来源 ImportSheet 点击最终 `Import` / `Import Folder`，才进入 `S1-20 import-progress`。

## 页面功能

- 展示被替换文件和替换来源。
- 说明旧文件移到系统废纸篓。
- 说明操作会写入 change_log。
- 要求用户明确确认。

## 布局与内容

标题：`确认替换？`

主说明：

```text
你将用新文件替换资料库中的已有文件。
```

将被替换：

- `docs/reports/报告.pdf`
- 大小：`860 KB`
- 修改时间：`Apr 20, 2026 09:14`

替换为：

- `~/Downloads/报告.pdf`
- 大小：`912 KB`
- 修改时间：`Apr 29, 2026 11:30`

影响说明：

- 旧文件将移到系统废纸篓。
- 新文件将写入原目标位置。
- 这次操作会记录到改动日志。
- 如果导入失败，AreaMatrix 会保持原文件不变或恢复到安全状态。

按钮：`Cancel`、destructive `Replace`。

## 状态与规则

- 默认状态：确认复选框未勾选，destructive `Replace` 禁用。
- 必选确认复选框：`我理解这是替换操作`；未勾选禁用 Replace。
- 如果 `allowReplaceDuringImport=false`，本 sheet 不应被打开；若因状态过期打开，显示错误并返回来源冲突区域。
- Trash 不可用时禁止 Replace。
- 确认状态保存失败或上下文过期时显示错误，不得执行导入或移动文件。
- 确认前不移动、不删除、不覆盖任何文件。
- 空态不适用：本 sheet 只在已有明确 replace target 和 incoming file 时打开；上下文缺失时显示错误并返回来源冲突区域。
- 加载态不适用：Trash 可用性和文件摘要应由来源冲突页准备；执行中属于按钮 loading。

## 交互

- Cancel 返回上一冲突页。
- Replace 确认后关闭本 sheet，返回来源 ImportSheet，并把当前冲突项标记为 `Replace confirmed`；不得在确认 sheet 内直接启动导入、移动文件或写 DB。
- 来源 ImportSheet 的底部 `Import` / `Import Folder` 仍是最终提交点；点击后进入 `S1-20 import-progress`。
- `S1-20 import-progress` 完成后，如果存在失败、跳过、取消或用户点击 `View details`，进入 `S1-21 import-result`；单文件全成功可按 S1-20 规则显示 toast。
- 最终导入成功后 Detail Log 追加 replace/delete 相关记录。
- 确认状态保存失败时留在本 sheet，显示 `Retry` / `Cancel` / `Collect Diagnostics...`；诊断不包含用户文件内容。

## 可访问性

- 被替换文件、替换来源和影响说明必须逐项可读。
- destructive `Replace` 的禁用原因需要读出确认复选框未勾选或 Trash 不可用。
- Cancel、确认复选框、Replace、Diagnostics 均可通过键盘访问。

## 数据与依赖

- Trash API。
- `allowReplaceDuringImport` settings value。
- final import uses Core `import_file(..., duplicate_strategy=Overwrite)` or equivalent replace-capable import command; confirmation sheet itself never calls it.
- change_log。
- staging transaction。

## 验收清单

- Replace 每次必须二次确认。
- 确认复选框未勾选时不能 Replace。
- 旧文件不得永久删除。
- 确认成功后返回来源 ImportSheet 并显示 `Replace confirmed`，不直接进入 S1-20、结果页或主窗口。
- 用户从来源 ImportSheet 点击最终 Import 后才进入 S1-20。
- 确认状态保存失败可恢复。

## 来源

- `docs/ux/dedup-conflict.md#replace二次确认规范`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-17 import-single-sheet](S1-17-import-single-sheet.md)
- [S1-18 import-batch-sheet](S1-18-import-batch-sheet.md)
- [S1-19 import-folder-sheet](S1-19-import-folder-sheet.md)
- [S1-22 conflict-duplicate](S1-22-conflict-duplicate.md)
- [S1-23 conflict-name](S1-23-conflict-name.md)
