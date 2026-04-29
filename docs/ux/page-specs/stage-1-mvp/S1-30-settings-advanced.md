# S1-30 settings-advanced - 高级设置

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-30
> 页面类型：设置
> 页面文件：`S1-30-settings-advanced.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 设置窗口。
- **建议目录**：`apps/macos/AreaMatrix/Features/Settings/AdvancedSettingsPane.swift`。
- **建议组件**：`AdvancedSettingsPane`、`DiagnosticsCard`、`DangerZoneDisclosure`。
- **实现说明**：高级设置只放诊断和明确安全的开发辅助项。高风险动作必须折叠并二次确认。

## 页面背景

高级设置面向需要排查问题的用户或开发者。AreaMatrix 涉及文件系统和数据库，不能把危险按钮随意暴露。本页要清楚区分“诊断”“缓存/日志”“危险区”。

入口：Settings > Advanced。
退出：导出诊断、打开日志目录、进入恢复工具、返回设置主页。

## 页面功能

- 显示诊断信息入口。
- 导出诊断包。
- 打开日志目录。
- 显示 Core version、App version、repo schema version。
- 提供恢复工具入口，但不直接执行恢复。
- 提供危险区折叠说明。
- 配置 `Allow replace during import`，默认关闭。

## 布局与内容

诊断卡：
- `App version`
- `Core version`
- `Repo schema version`
- `Last error`，若有。
- 按钮：`Export diagnostics...`

日志卡：
- `Open logs folder`
- `Copy diagnostic summary`
- 说明：`Diagnostics do not include your original file contents.`

恢复工具卡：
- `Open recovery tools...`
- 仅在错误状态或用户展开高级选项时显示。

危险区：
- 折叠标题：`Danger zone`
- 文案：`These actions can affect AreaMatrix metadata. They do not delete your original files unless explicitly stated.`
- 危险导入选项：
  - `Allow replace during import` toggle，默认 `Off`
  - 说明：`When enabled, ImportSheet may show Replace for duplicate or name conflicts. Replace still requires Trash and a second confirmation.`
- Stage 1 默认不放直接执行按钮；只放入口到专门恢复页面和危险能力开关。

开启 Replace 的确认 sheet：

- 标题：`Enable Replace during import?`
- 说明：`Replace can move an existing repository file to system Trash before importing the new file. It is hidden by default and still requires confirmation for every replace.`
- 按钮：`Cancel`、主按钮 `Enable Replace`

## 状态与规则

- 诊断导出需要说明包含内容和不包含内容。
- 打开日志目录失败时显示可恢复错误。
- 危险区默认折叠。
- 默认状态：`allowReplaceDuringImport=false`，因此 ImportSheet 的 `replaceOptionVisibility=hidden`。
- 开启 `Allow replace during import` 必须先弹确认；取消后 toggle 回到 Off。
- 开启后仍要求具体冲突页检查 Trash 可用性和二次确认；Trash 不可用时 `replaceOptionVisibility=disabled`。
- 关闭 `Allow replace during import` 不需要确认，并立即让新打开的 ImportSheet 隐藏 Replace。
- 保存危险开关失败时回滚到上一个已保存值，显示 `Could not save advanced setting` 和 `Retry save`。
- 本页不提供 `reset database`、`delete metadata`、`reindex` 的直接按钮。
- 任何需要修改 DB 或 `.areamatrix/` 的动作必须进入专页确认。
- 诊断导出或打开日志执行中禁用对应按钮的重复点击。
- 无错误状态时可隐藏或禁用 `Open recovery tools...`，但保留说明。
- 空态不适用：本页至少显示版本、诊断和 Danger zone；版本读取失败显示 Unknown 与诊断入口。

## 交互

1. 打开页面读取版本和最近错误。
2. 点击 `Export diagnostics...` 弹确认 sheet，确认文案说明不包含用户文件内容、不自动上传、路径和用户名会脱敏，确认后生成本地诊断包。
3. 点击 `Copy diagnostic summary` 复制脱敏摘要。
4. 点击 `Open logs folder` 用 Finder 打开日志目录。
5. 展开 Danger zone 只显示说明和恢复工具入口。
6. 打开 `Allow replace during import` 时先弹确认；确认后保存 settings，保存成功才显示为 On。
7. 关闭 `Allow replace during import` 时直接保存为 Off；已打开的 ImportSheet 不 retroactively 执行 Replace，下一次冲突预检按新设置隐藏 Replace。
8. 点击 `Open recovery tools...` 进入 `S1-32 error-recovery` 对应入口。

## 数据与依赖

- App/core/schema version provider。
- Diagnostic export。
- Log folder path。
- Recent error store。
- Finder reveal。
- Recovery route。
- `allowReplaceDuringImport` settings value。
- settings save state and last saved snapshot。

## 验收清单

- 用户能导出诊断包并知道不包含原文件内容。
- 版本信息清楚显示。
- Danger zone 默认折叠且无直接破坏性按钮。
- `Allow replace during import` 默认 Off，开启前必须确认。
- Replace 开关保存失败会回滚 UI，不让 ImportSheet 显示与实际设置不一致的 Replace 状态。
- 恢复工具入口不会绕过确认流程。
- 打开日志目录失败有错误提示。
- VoiceOver 能读出诊断卡和危险区展开状态。

## 来源

- `docs/ux/settings-panel.md#tab高级advanced`（直接）。
- `docs/ux/error-messages.md#诊断入口统一规范`（组合）。
- `AGENTS.md` 中高风险边界与验证要求（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-26 settings-general](S1-26-settings-general.md)
- [S1-27 settings-repository](S1-27-settings-repository.md)
- [S1-32 error-recovery](S1-32-error-recovery.md)
- [S1-31 settings-about](S1-31-settings-about.md)
