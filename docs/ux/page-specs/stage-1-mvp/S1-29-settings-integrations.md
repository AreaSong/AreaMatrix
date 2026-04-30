# S1-29 settings-integrations - 集成设置

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-29
> 页面类型：设置
> 页面文件：`S1-29-settings-integrations.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 设置窗口。
- **建议目录**：`apps/macos/AreaMatrix/Features/Settings/IntegrationsSettingsPane.swift`。
- **建议组件**：`IntegrationsSettingsPane`、`ICloudStatusCard`、`ExternalToolsHelpCard`。
- **实现说明**：Stage 1 只展示 iCloud 状态和帮助，不做复杂同步设置，不接入第三方云盘 SDK。

## 页面背景

用户可能把资料库放在 iCloud Drive，希望知道 AreaMatrix 是否支持、有什么风险、遇到占位符或冲突时怎么办。本页不是同步控制台，不能让用户误以为 AreaMatrix 自己提供云同步服务。

入口：Settings > Integrations。
退出：打开 iCloud 帮助、打开 Finder、返回设置主页。

## 页面功能

- 显示当前 repo 是否位于 iCloud Drive。
- 显示 iCloud 可用性，若无法检测则显示 Unknown。
- 解释占位符按需下载和同步延迟。
- 解释冲突副本不会被自动删除。
- 提供打开 iCloud 帮助入口。
- 显示 Finder 等外部工具的只读说明。

## 布局与内容

顶部卡片：`iCloud Drive`

字段：
- `Repository location`: `iCloud Drive` / `Local folder`
- `iCloud status`: `Available` / `Unavailable` / `Unknown`
- `Placeholder handling`: `Downloaded when AreaMatrix needs to read the file`
- `Conflict handling`: `Conflicted copies are shown for review`

说明文案：
`AreaMatrix stores your files in a normal folder. If that folder is in iCloud Drive, iCloud controls sync timing. AreaMatrix will not delete conflict copies automatically.`

按钮：
- `Open iCloud help`
- `Reveal repository in Finder`
- `Retry status`，仅检测失败或 Unknown 时显示。
- `Review conflicts`，仅当前存在 iCloud 冲突时显示，进入 `S1-36 icloud-conflict-list`。

外部工具卡：
- 标题：`Finder and other apps`
- 说明：`You can open files directly in Finder. External changes are picked up by file watching when available.`

## 状态与规则

- 默认状态：非 iCloud repo 显示 `Local folder`，不显示冲突入口，帮助入口可用。
- 非 iCloud 路径显示普通本地状态，不显示黄色风险提示。
- iCloud 路径显示黄色提示，但不禁止使用。
- iCloud 状态 Unknown 时不得显示成 Available。
- 本页不修改系统 iCloud 设置。
- 本页不提供“强制同步所有文件”按钮，除非错误恢复页针对占位符提供下载重试。
- 不自动删除任何 iCloud 冲突副本。
- 状态检测中禁用 `Retry status`，保留 `Open iCloud help`。
- 无冲突时禁用或隐藏 `Review conflicts`。
- 空态不适用：Integrations tab 至少显示 iCloud Drive 状态和帮助入口；非 iCloud repo 是 `Local folder` 默认状态。

## 交互

1. 打开页面时检测 repo path 和 iCloud 状态。
2. 点击 `Open iCloud help` 打开应用内帮助或 ADR 文档。
3. 点击 `Reveal repository in Finder` 打开 repo 根目录。
4. 检测失败时状态显示 Unknown，并提供 `Retry status`。
5. 如果当前有 iCloud 冲突，显示入口 `Review conflicts`，跳转到 `S1-36 icloud-conflict-list`。

## 可访问性

- iCloud 状态、风险说明和冲突数量必须用文本读出。
- Review conflicts 隐藏或禁用时需要明确原因。
- Open iCloud help、Retry status、Review conflicts 必须可通过键盘访问。

## 数据与依赖

- iCloud path detection。
- iCloud availability best-effort detector。
- NSFileCoordinator 行为说明。
- Conflict count provider。
- Finder reveal。
- Help link。

## 验收清单

- iCloud 用户能看到同步延迟、占位符和冲突副本说明。
- 非 iCloud 用户不会看到不必要警告。
- Unknown 状态不会被误写为 Available。
- 本页不修改系统 iCloud 设置，不强制下载文件。
- 冲突存在时有可发现入口。
- VoiceOver 能读出 iCloud 状态和风险提示。

## 来源

- `docs/ux/settings-panel.md#tab集成integrations`（直接）。
- `docs/adr/0006-icloud-support.md`（组合）。
- `docs/ux/dedup-conflict.md#icloud-conflicted-copy冲突解决-ux`（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-36 icloud-conflict-list](S1-36-icloud-conflict-list.md)
