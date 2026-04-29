# S1-31 settings-about - 关于

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-31
> 页面类型：设置
> 页面文件：`S1-31-settings-about.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 设置窗口
- **建议目录**：`apps/macos/AreaMatrix/Features/Settings/`
- **建议组件**：`AboutSettingsPane`、`DiagnosticsExportButton`
- **实现说明**：用于版本、许可证、诊断和反馈入口。

## 页面背景

用户需要查看版本、许可证，或在遇到问题时导出诊断。

入口：Settings > About。
退出：关闭 Settings、切换设置 tab、打开外部链接、导出诊断、打开日志。

## 页面功能

- 展示 App/Core/schema 版本。
- 展示许可证。
- 链接 GitHub / Issue / Discussions。
- 收集诊断。
- 打开日志。

## 布局与内容

版本信息：

- App version
- Core version
- Schema version

许可证：`PolyForm Noncommercial`

链接：

- GitHub
- Issue
- Discussions

诊断：

- `Collect diagnostics...`
- `Open logs in Console`

## 状态与规则

- 诊断收集中显示进度。
- 诊断失败显示可复制错误。
- 版本号可复制。
- 默认状态：显示 App/Core/schema 版本；schema 读取失败时显示 `Unknown` 并提供 `Collect diagnostics...`。
- 外部链接打开失败时显示非阻断 toast，保留链接文本可复制。
- 打开日志失败时显示 `Open logs failed`，提供 `Copy logs path`。
- Collect diagnostics 弹隐私确认；确认中禁用重复点击。

## 交互

- 外部链接使用系统浏览器。
- Open logs 打开 Console 或 Finder 中日志目录。
- Collect diagnostics 弹出隐私说明后输出脱敏诊断包；诊断不包含用户文件内容，不自动上传。
- 诊断导出成功后显示保存位置和 `Reveal in Finder`。
- 诊断导出失败时保留错误码，可重试，不自动上传。

## 数据与依赖

- Bundle version。
- Core version。
- schema version。
- logs path。
- diagnostics export state。
- external link opener。

## 验收清单

- 用户能找到诊断入口。
- 许可证可见。
- 版本信息完整。
- 诊断导出不包含用户文件内容。
- 外链、日志、诊断失败都有非阻断恢复路径。

## 来源

- `docs/ux/settings-panel.md#tab关于about`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-26 settings-general](S1-26-settings-general.md)
- [S1-30 settings-advanced](S1-30-settings-advanced.md)
