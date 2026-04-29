# S1-36 icloud-conflict-list - iCloud 冲突列表

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-36
> 页面类型：冲突
> 页面文件：`S1-36-icloud-conflict-list.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 主窗口页面区域或设置入口目标页。
- **建议目录**：`apps/macos/AreaMatrix/Features/Conflicts/ICloudConflictListView.swift`。
- **建议组件**：`ICloudConflictListView`、`ConflictPairRow`。
- **实现说明**：列出 iCloud conflicted copy；具体保留策略由 `S1-25 icloud-conflict-min` sheet 执行。

## 页面背景

iCloud 可能生成冲突副本。用户从 Settings 或文件详情进入后，需要看到所有待处理冲突，而不是跳到不存在的“冲突列表”。

入口：`S1-29 settings-integrations` 的 `Review conflicts`；`S1-12 detail-meta` 的 iCloud 冲突提示；主窗口冲突 badge。
退出：解决全部冲突后回到来源页面；Cancel / Close 返回来源页面；单项 Resolve 打开 `S1-25 icloud-conflict-min`。

## 页面功能

- 展示当前资料库中的 iCloud 冲突副本列表。
- 显示每组冲突的两个版本、修改时间和位置。
- 提供单项 Resolve 入口。
- 提供 Reveal in Finder 和刷新。

## 布局与内容

标题：`iCloud Conflicts`

说明：
```text
iCloud created conflict copies for these files. AreaMatrix will not delete any version automatically.
```

工具区：
- `Refresh`
- `Reveal repository in Finder`

表格列：
- File
- Original version
- Conflict copy
- Modified
- Status
- Action

行操作：
- `Resolve...`
- `Reveal`

底部按钮：`Close`。

## 状态与规则

- 默认状态：打开后加载冲突列表，表格未加载前不显示过期数据。
- 空态：`No iCloud conflicts found`，提供 `Refresh`。
- 加载态：显示 `Checking iCloud conflicts...`。
- 检测失败：显示错误、`Retry`、`Collect Diagnostics...`。
- Resolve 只打开单项解决 sheet，不在列表页直接删除或移动任何版本。
- 冲突副本识别不确定时，状态显示 `Needs review`，不得自动归并。
- 加载中禁用 `Resolve...`，保留 `Close`。
- 单项解决中禁用该行 `Resolve...`，其他行仍可查看但不自动删除。

## 交互

1. 打开页面时加载冲突列表。
2. 点击 `Resolve...` 打开 `S1-25 icloud-conflict-min`。
3. 单项解决成功后回到列表并刷新该行。
4. 点击 `Reveal` 在 Finder 中定位对应文件。
5. `Close` 返回来源页面，不改任何文件。

## 数据与依赖

- iCloud conflicted copy 文件名识别。
- conflict pair provider。
- Finder reveal。
- Diagnostics exporter。
- `S1-25 icloud-conflict-min` 单项解决结果。

## 验收清单

- Settings 的 `Review conflicts` 有明确目标页。
- 列表页不会自动删除或移动任何冲突副本。
- 空态、加载态、错误态和单项解决后刷新都可见。
- 诊断导出不包含用户文件内容，不自动上传。

## 来源

- `docs/ux/dedup-conflict.md#icloud-conflicted-copy冲突解决-ux`（直接）。
- `docs/ux/settings-panel.md#tab集成integrations`（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-12 detail-meta](S1-12-detail-meta.md)
- [S1-25 icloud-conflict-min](S1-25-icloud-conflict-min.md)
- [S1-29 settings-integrations](S1-29-settings-integrations.md)
