# S1-15 detail-multi - 多选摘要

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-15
> 页面类型：详情
> 页面文件：`S1-15-detail-multi.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 详情面板
- **建议目录**：`apps/macos/AreaMatrix/Features/Detail/`
- **建议组件**：`MultiSelectionDetailView`、`SelectionUtilityActions`
- **实现说明**：多选时不显示单文件 Meta/Log/Note，而是显示选中摘要和只读辅助动作；Stage 1 不提供会修改文件或索引的批量动作。

## 页面背景

用户在 List 中选择多个文件，需要知道选中了什么，并执行不改变文件或索引的辅助操作。

入口：`S1-09 main-list` 中选择 2 个或更多文件。
退出：清空选择进入 Detail empty；改为单选进入 `S1-12 detail-meta`；切换 Tree 节点时清空选择并回到对应 List 状态。

## 页面功能

- 显示选中文件数量和范围。
- 汇总总大小、分类、存储模式、导入时间范围。
- 提供 Show in Finder 和 Copy Paths 辅助操作。
- 对缺失和 Index-only 文件给提示。

## 布局与内容

标题：`5 个文件已选中`

副标题：`docs 中的 5 个项目`

统计信息：

- Total size：`18.6 MB`
- Categories：`docs, finance`
- Storage modes：`Copy, Indexed`
- Earliest imported：`Apr 20, 2026`
- Latest imported：`Apr 29, 2026`

文件类型分布：

- PDF：3
- Markdown：1
- Image：1

辅助操作：

- `Show in Finder`
- `Copy Paths`

## 状态与规则

- 默认状态：显示只读摘要和辅助操作，不显示 Meta/Log/Note tabs。
- 本页不单独发起加载请求；统计信息来自当前 List selection 和已加载 metadata。若聚合数据仍在刷新，显示 `Updating selection...`，不阻塞 `Copy Paths`。
- 聚合失败时显示 inline warning `部分选中项无法读取元数据`，保留可用统计和 `Copy Paths`；高风险写操作仍不出现。
- 包含缺失文件：显示 warning `选中的文件中有 1 个缺失条目`。
- 包含 Index-only：提示某些条目的来源路径可能在资料库外。
- 选择数为 0 时不进入本页。
- Stage 1 不显示任何同时修改多个文件、移动多个文件或删除多个文件的按钮。

## 交互

- Show in Finder 只在选中 1 个文件时可用；多选时禁用并显示说明 `Open one file at a time`。
- Copy Paths 将所有选中路径写入剪贴板。
- 用户需要修改或删除时，必须先切回单选，再进入 S1-33 / S1-34 / S1-35。

## 数据与依赖

- List selection。
- 文件 metadata 聚合。
- Finder / clipboard 能力。

## 验收清单

- 多选时隐藏单文件 tabs。
- 统计信息正确。
- 切回单选或清空选择时有明确退出路径。
- 页面不提供任何批量写入动作。
- Copy Paths 不修改文件或索引。

## 来源

- `docs/ux/ui-states.md#附录-bdetail-multi-视图建议ascii`（直接）。
- `docs/roadmap/stage-1-mvp.md#不做out-of-scope`（组合，按 Stage 1 边界收敛）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-09 main-list](S1-09-main-list.md)
- [S1-12 detail-meta](S1-12-detail-meta.md)

说明：单文件 Rename / Delete / Change Category 必须先从多选切回单选，再由 `S1-09` 或 `S1-12` 进入对应 sheet。
