# S1-25 icloud-conflict-min - iCloud 冲突最小处理

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-25
> 页面类型：冲突
> 页面文件：`S1-25-icloud-conflict-min.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 冲突处理
- **建议目录**：`apps/macos/AreaMatrix/Features/Conflicts/`
- **建议组件**：`ICloudConflictMinimalSheet`
- **实现说明**：Stage 1 不做内容 diff，只做单组冲突的选择保留策略；列表入口由 `S1-36 icloud-conflict-list` 承接。

## 页面背景

iCloud 可能生成 `Conflicted Copy` 文件。用户从冲突列表或 Detail 提示进入本 sheet，对一组冲突选择保留策略。AreaMatrix 不能静默删除任何版本。

入口：`S1-36 icloud-conflict-list` 的 `Resolve...`，或 `S1-12 detail-meta` 的 `Resolve conflict...`。
退出：Apply 成功返回冲突列表或来源详情；Cancel 返回来源页且不改任何文件；失败留在本 sheet。

## 页面功能

- 显示同一组冲突的两个版本。
- 提供最小解决 sheet。
- 默认保留两份。
- 删除类策略必须二次确认，走 Trash 并写 change_log。

## 布局与内容

标题：`Resolve iCloud Conflict`

说明：
```text
This is an iCloud conflicted copy. AreaMatrix will not delete any version automatically.
```

版本列表：

- `报告.pdf` modified: `2026-04-01 10:20`
- `报告 (Conflicted Copy...).pdf` modified: `2026-04-01 10:21`

选项：

1. `保留两份（推荐）`
2. `仅保留第一份（把另一份移到回收站）`
3. `仅保留第二份（把另一份移到回收站）`

单保留确认区，仅选择第 2 或第 3 项时显示：

- 说明：`AreaMatrix will move the other version to system Trash and keep a change-log record.`
- 复选框：`我理解另一份冲突副本会被移到系统废纸篓`

按钮：

- 默认策略：`Cancel`、主按钮 `Apply`
- 单保留策略：`Cancel`、destructive `Move other version to Trash and Apply`

## 状态与规则

- 默认保留两份。
- `icloudConflictResolution.requiresSecondConfirmation=true` 只在选择单保留策略时生效。
- 单保留策略必须移动另一份到 Trash，不提供永久删除。
- Trash 不可用时禁用单保留策略，显示 `Single-version resolution requires system Trash`。
- 单保留策略未勾选确认复选框时，destructive 按钮禁用。
- Apply 前不移动、不删除、不重命名任何文件。
- 识别不确定时禁用单保留策略，只允许保留两份或 Cancel。
- 空态不适用：本 sheet 只在已有明确冲突组时打开；冲突组消失时关闭 sheet 并刷新来源页。
- 加载态不适用：冲突版本和 Trash 可用性应由入口页准备；若入口数据过期，显示错误并要求返回列表刷新。

## 交互

- 选择保留两份后点击 `Apply`，只清除冲突待处理状态或保留标记，不移动、不删除任何版本，并写 change_log。
- 选择单保留策略后，先勾选确认复选框，再点击 destructive 按钮；执行中按钮显示 `Moving to Trash...` 并禁止重复点击。
- 解决后刷新来源列表或 Detail 冲突标记。
- Cancel 不改任何文件。
- Apply 失败时留在 sheet，显示 `Retry` / `Cancel` / `Collect Diagnostics...`；诊断不包含用户文件内容。

## 数据与依赖

- iCloud conflicted copy 文件名识别。
- Trash API。
- change_log。
- `icloudConflictResolution.requiresSecondConfirmation`。
- 来源 route，用于成功、Cancel 或失败后返回列表或 Detail。

## 验收清单

- 冲突副本在列表和详情可见。
- 默认不删除任何版本。
- 删除类策略需要二次确认并走 Trash。
- Trash 不可用时不能执行单保留策略。
- Cancel 和失败路径不会改动文件。

## 来源

- `docs/ux/dedup-conflict.md#icloud-conflicted-copy冲突解决-ux`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-12 detail-meta](S1-12-detail-meta.md)
- [S1-36 icloud-conflict-list](S1-36-icloud-conflict-list.md)
