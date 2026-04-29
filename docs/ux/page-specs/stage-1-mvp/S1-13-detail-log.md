# S1-13 detail-log - 改动时间线

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-13
> 页面类型：详情
> 页面文件：`S1-13-detail-log.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 详情面板
- **建议目录**：`apps/macos/AreaMatrix/Features/Detail/`
- **建议组件**：`LogTabView`、`ChangeTimelineView`
- **实现说明**：切到 Log tab 时加载 change_log；新导入文件可自动切一次 Log。

## 页面背景

AreaMatrix 的核心价值之一是“记账”。用户需要看到文件何时导入、如何分类、是否被外部修改或重命名。

入口：`S1-12 detail-meta` 的 `Log` tab；刚导入或刚发生外部修改时，主窗口可一次性自动切到本 tab。
退出：切回 `Meta` / `Note` tab、切换 List 选中项、清空选择或关闭主窗口。

## 页面功能

- 展示当前文件的 change_log 时间线。
- 最新记录在最上方。
- 可展开技术详情。
- 加载失败时可重试或导出诊断；诊断包不包含用户文件内容，不自动上传。

## 布局与内容

顶部保留文件摘要和 tabs，当前选中 `Log`。

标题：`Change Log`

说明：

```text
该文件的导入、移动、重命名和外部修改都会记录在这里。
```

时间线记录示例：

1. `external_modified`
   `Apr 29, 2026 14:12`
   Finder 中检测到文件修改。changed: modified_at
2. `renamed`
   `Apr 28, 2026 18:40`
   文件从 `合同.pdf` 重命名为 `2026Q1_合同_客户A.pdf`。
3. `imported`
   `Apr 28, 2026 10:32`
   通过 Copy 模式从 `~/Downloads/合同.pdf` 导入。

## 状态与规则

- 无记录：显示 `暂无改动记录`。
- 加载中：显示 spinner，不清空文件摘要。
- 加载失败：inline error `无法加载改动记录`，按钮 `Retry` / `Collect Diagnostics...`，诊断确认文案说明路径和用户名会脱敏。
- 刚发生外部修改时可追加新记录并保持当前选中。
- 默认状态：单选文件后进入本 tab 时拉取最近 change_log，最新记录在最上方。
- 文件缺失或只读 repo：仍可查看日志；只禁用会修改文件或索引的操作。
- 无选中或多选时不显示本页，分别进入 Detail empty 或 `S1-15 detail-multi`。

## 交互

- 点击记录 disclosure 展开 detail_json。
- `Refresh` 重新拉取日志。
- 切回 Meta/Note 不丢失当前文件选中。
- 切换文件时取消旧日志请求，展示新文件 loading；旧请求返回不得覆盖当前文件日志。
- `Collect Diagnostics...` 只导出脱敏错误上下文，不包含文件内容。

## 数据与依赖

- Core `list_changes`。
- change_log action 枚举。
- FSEvents 同步结果。

## 验收清单

- 导入文件至少有 imported 记录。
- 外部重命名后出现 renamed/external_modified 记录。
- 加载失败有 Retry。
- Collect Diagnostics 不包含用户文件内容。
- 切换文件时不会显示上一个文件的日志。
- 只读或缺失文件仍可查看已有日志。

## 来源

- `docs/ux/ui-states.md#tab-约定`（组合）。
- `docs/modules/change-log.md`（组合，依据现有文档推导页面细节）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-12 detail-meta](S1-12-detail-meta.md)
- [S1-14 detail-note](S1-14-detail-note.md)
- [S1-15 detail-multi](S1-15-detail-multi.md)
