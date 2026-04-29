# S1-32 error-recovery - 错误与恢复共享 UI 组件规格

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-32
> 页面类型：错误恢复共享组件 / 页面区域
> 页面文件：`S1-32-error-recovery.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 错误恢复
- **建议目录**：`apps/macos/AreaMatrix/Features/ErrorRecovery/`
- **建议组件**：`ErrorBanner`、`InlineErrorView`、`CriticalErrorView`、`DiagnosticsView`
- **实现说明**：这不是独立可导航页面，而是 toast、banner、inline error、alert、critical error view 的共享规格。具体页面复用这些组件；DB corrupted 的危险修复确认由 `S1-37 db-repair-confirm` 承接。

## 页面背景

AreaMatrix 涉及文件系统、SQLite、iCloud、配置和 Core 调用。错误不能只显示技术异常，必须告诉用户下一步怎么办。

页面边界：本文件不是独立可导航页面，而是错误恢复共享 UI 组件规格；toast、banner、inline error、alert 和 critical block 都由具体来源页面嵌入或承接。

入口：各页面遇到 CoreError、平台错误、iCloud placeholder、配置错误或诊断失败时嵌入本规格对应组件。
退出：Retry 成功后关闭组件并回到来源页面；Cancel/Close 返回来源页面；DB corrupted 进入 `S1-37 db-repair-confirm`；Remove from index 进入 `S1-34 file-delete-confirm`。

## 页面功能

- 按严重程度选择 UI 形态。
- 显示用户可读错误文案。
- 提供 Retry、Change Path、Diagnostics 等恢复动作。
- 展开技术详情。

## 布局与内容

严重程度映射：

- low：toast。
- medium：banner 或 inline error。
- high：alert。
- critical：全窗口错误页。

常见错误：

- IO / PermissionDenied
- Disk full
- DB locked
- DB corrupted：显示 critical 入口，但不在本页执行修复。
- Config error
- iCloud placeholder
- Duplicate / Conflict
- Internal error

按钮按场景出现：

- `Retry`
- `Change Path`
- `Collect Diagnostics...`
- `Show in Finder`
- `Remove from index`
- `Open repair...`，仅 DB corrupted 时显示，进入 `S1-37 db-repair-confirm`

默认错误映射：

| 场景 | 形态 | 主按钮 | 次按钮 | 承接页面 |
|---|---|---|---|---|
| 单文件 IO / Permission | toast 或 inline | Retry | Collect Diagnostics... | 来源页 |
| 当前 List DB locked | inline error | Retry | Collect Diagnostics... | 来源 List，不阻断 Tree |
| DB corrupted | critical block | Open repair... | Export diagnostics... | `S1-37` |
| Config error | sheet / inline | Open rules | Revert to last valid | `S1-28` |
| iCloud placeholder | sheet | Download & retry | Cancel / Switch local | 来源页或 `S1-03` |
| File missing | inline banner | Locate... | Remove from index | `S1-34` |
| Internal error | critical block | Restart | Collect Diagnostics... | 来源页 |

## 状态与规则

- DB locked 不应让整个 Tree 变灰，优先显示 List inline error。
- DB corrupted 是 critical，主动作进入 `S1-37 db-repair-confirm`。
- iCloud placeholder 可提供 Download & retry。
- Internal error 必须提供诊断入口。
- Collect Diagnostics 不包含用户文件内容，不自动上传，路径和用户名会脱敏。
- low toast 不提供破坏性动作；medium+ 至少提供 Retry、Cancel/Close 或 Diagnostics 中的一个恢复动作。
- Retry 执行中禁用重复点击，按钮文案变为 `Retrying...`。
- `Change Path` 只出现在 repo 选择或 repo 打开相关错误中，不在单文件错误中显示。
- `Remove from index`、`Open repair...` 等高风险动作只做跳转，不在共享组件内直接执行。

## 交互

- Retry 只重试当前失败动作。
- Collect Diagnostics 不修改用户文件。
- `Remove from index` 必须进入 `S1-34 file-delete-confirm` 的 Remove from index 模式。
- `Open repair...` 必须进入 `S1-37 db-repair-confirm`，不直接运行修复。
- 技术详情默认折叠。
- Close/Cancel 只关闭当前错误组件，不清空用户输入、不删除队列、不修改 repo 配置。
- Download & retry 先显示 iCloud 下载进度，失败仍留在来源页并保留 Retry。

## 数据与依赖

- CoreError 映射表。
- diagnostics exporter。
- NSFileCoordinator / iCloud 占位符处理。
- DB status。
- source route and retry action token。

## 验收清单

- 每类 CoreError 至少有一个恢复动作或诊断入口。
- 错误状态不只靠颜色表达。
- 高风险修复不自动执行。
- DB corrupted 只能进入 S1-37，不能在本页直接修复。
- DB locked 在 List/Detail inline 呈现时 Tree 仍可操作。
- Retry 执行中防重复点击，Cancel 不产生写入副作用。
- 复用本规格的具体页面必须声明来源入口、关闭或 Cancel 后返回路径，以及 Retry 的作用对象。

## 来源

- `docs/ux/error-messages.md`（直接）。
- `docs/ux/ui-states.md#关键错误态设计不阻断`（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-03 validate-path](S1-03-validate-path.md)
- [S1-34 file-delete-confirm](S1-34-file-delete-confirm.md)
- [S1-37 db-repair-confirm](S1-37-db-repair-confirm.md)
- [S1-28 settings-classifier](S1-28-settings-classifier.md)
