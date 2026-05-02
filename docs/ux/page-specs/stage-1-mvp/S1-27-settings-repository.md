# S1-27 settings-repository - 资料库设置

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-27
> 页面类型：设置
> 页面文件：`S1-27-settings-repository.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 设置窗口。
- **建议目录**：`apps/macos/AreaMatrix/Features/Settings/RepositorySettingsPane.swift`。
- **建议组件**：`RepositorySettingsPane`、`RepositoryPathCard`、`RepositoryHealthCard`。
- **实现说明**：Stage 1 本页展示资料库信息、安全动作入口和 Change repository 入口。Change repository 只切换当前打开的 repo，不迁移、不移动、不删除、不覆盖当前 repo。

## 页面背景

用户需要查看当前资料库位置、状态、版本和基础健康信息，也可能需要在 Finder 中打开资料库或导出诊断。本页必须避免把高风险动作放得太近，例如重建索引、修复数据库、接管目录等都应进入明确确认流程。

入口：Settings > Repository。
退出：打开 Finder、导出诊断、进入错误恢复、进入选择资料库流程或返回设置主页。

## 页面功能

- 显示当前 repo 名称和路径。
- 显示 `.areamatrix/` metadata 状态。
- 显示数据库状态、文件数量、最近扫描时间。
- 显示 generated overview 输出模式和实际输出位置。
- 提供 `Reveal in Finder`。
- 提供 `Change repository...`，只用于打开另一个资料库或选择新资料库位置。
- 提供 `Export diagnostics`。
- 显示只读健康提示，不直接执行高风险修复。

## 布局与内容

路径卡：
- `Repository name: AreaMatrix`
- `Location: ~/Documents/AreaMatrix`
- `Metadata: .areamatrix/ found`
- 按钮：`Reveal in Finder`、`Copy path`、`Change repository...`

健康卡：
- `Database: OK / Locked / Needs recovery`
- `Files indexed: 1,248`
- `Last scan: Apr 29, 2026 11:30`
- `Watcher: Running / Paused`

概览输出卡：
- `Generated overview: Generated only / Root AREAMATRIX.md enabled`
- `Generated path: .areamatrix/generated/root.md`
- `Root file: Off / AREAMATRIX.md`
- `README.md: User file, never managed by AreaMatrix`
- 按钮：`Reveal generated overview`

安全动作区：
- `Export diagnostics...`
- `Open recovery tools...`，仅错误状态显示。

说明区：
`Deleting the .areamatrix folder removes AreaMatrix metadata, not your original files. Do this only if you know what you are doing.`

## 状态与规则

- 默认状态：repo 正常时显示只读健康摘要和安全动作区。
- repo 正常：显示健康摘要，不显示恢复工具。
- DB locked：显示黄色提示和 `Retry status`。
- metadata 缺失：显示错误并引导错误恢复，不自动重建。
- DB corrupted / Needs recovery：`Open recovery tools...` 进入 `S1-37 db-repair-confirm`。
- 路径不存在：显示 `Folder missing`，提供重新连接。
- 不提供 `Move repository`，除非未来阶段另有规格。
- `Change repository...` 不等于 Move repository：不得迁移当前 repo、不得重写路径、不得删除当前 repo 配置，直到新 repo 成功打开。
- 点击 `Change repository...` 后进入 `S1-02 choose-path`；选中路径后必须经过 `S1-03 validate-path`。
- 新路径是完整 AreaMatrix repo 时，走 `S1-03` 的 `Open Repository` 分支；新路径为空目录或非空目录时，继续 `S1-04 confirm-init`。
- 新 repo 打开或初始化失败时，保留当前已打开 repo 和当前 settings 页面可返回，不把 app 留在无 repo 状态。
- 不提供删除 repo 的危险按钮。
- 健康状态读取中禁用 `Retry status`，保留 Reveal / Copy path。
- repo opening / switching 期间禁用 `Change repository...` 防止重复流程，显示 `Opening repository...`。
- repo path 缺失时禁用 Reveal，保留 Copy last known path 和恢复入口。
- 空态不适用：Repository tab 始终显示当前或 last known repo 信息；无 repo 时应回到 onboarding，不显示空 tab。
- 加载态：读取健康状态时显示 `Checking repository...`，禁用重复 Retry，不阻断 Copy last known path。
- `overviewOutput=GeneratedOnly` 时只展示 `.areamatrix/generated/root.md` 作为 Core 管理输出。
- `overviewOutput=RootAreaMatrixFile` 时额外展示根目录 `AREAMATRIX.md`，并说明只管理 AreaMatrix marker block。
- 本页只展示当前 overview 输出策略和路径；切换策略进入 `S1-30 settings-advanced` 的确认流程。
- 不把 `README.md` 显示为 AreaMatrix 输出目标，也不得暗示应用会覆盖用户已有 `README.md`。

## 交互

1. 打开页面时读取 repo summary 和 health snapshot。
2. 点击 `Reveal in Finder` 打开当前 repo 根目录。
3. 点击 `Copy path` 将路径复制到剪贴板并显示 toast。
4. 点击 `Reveal generated overview` 打开 `.areamatrix/generated/`，失败时显示可恢复错误。
5. 点击 `Retry status` 重新读取健康状态。
6. 点击 `Export diagnostics...` 打开导出确认。
7. 点击 `Open recovery tools...`：DB corrupted 进入 `S1-37 db-repair-confirm`；其他错误进入 `S1-32 error-recovery`。
8. 点击 `Change repository...` 进入 `S1-02 choose-path`，并携带 `source=settingsRepository`；Cancel 或 Back 返回本页且不修改当前 repo。
9. 新 repo 在 `S1-03` / `S1-10` 打开成功后，才更新当前 repo 选择和 Settings 显示；失败进入 `S1-11 main-repo-error`，并允许回到旧 repo。

## 可访问性

- repo path、健康状态、schema version 必须有可读标签。
- overview 输出模式、generated path、root file 状态必须有可读标签。
- 错误状态和恢复入口不能只靠颜色或图标表达。
- Change repository、Open recovery tools、Export diagnostics 必须可通过键盘访问。

## 数据与依赖

- Repo summary API。
- Database health status。
- File count/index stats。
- Watcher status。
- `overviewOutput` settings value。
- generated overview output status。
- Finder reveal/copy path。
- Diagnostics export。
- repository switch route state。
- last opened repo snapshot，用于新 repo 失败时保留旧 repo。

## 验收清单

- 用户能看到 repo 路径、metadata 状态、数据库状态和最近扫描时间。
- 正常状态不展示高风险恢复动作。
- metadata 缺失不会自动重建。
- Reveal in Finder 和 Copy path 可用。
- Change repository 入口可发现，且不迁移、不删除、不覆盖当前 repo。
- 新 repo 未成功打开前，当前 repo 配置保持不变。
- Change repository 取消或失败后能回到旧 repo。
- 用户能看到 C1-20 generated overview 当前输出模式和 `.areamatrix/generated/root.md`。
- `RootAreaMatrixFile` 开启时显示根 `AREAMATRIX.md` 是显式配置的可选输出。
- 页面明确 `README.md` 是用户文件，不由 AreaMatrix 生成或覆盖。
- 诊断导出前说明不包含用户文件内容。
- VoiceOver 能读出每张卡的标题和值。

## 来源

- `docs/ux/settings-panel.md#tab资料库repository`（直接）。
- `docs/ux/error-messages.md#2-coreerrordb数据库错误`（组合）。
- `AGENTS.md` 中资料库高风险边界与不变量（组合）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-32 error-recovery](S1-32-error-recovery.md)
- [S1-37 db-repair-confirm](S1-37-db-repair-confirm.md)
- [S1-02 choose-path](S1-02-choose-path.md)
- [S1-03 validate-path](S1-03-validate-path.md)
- [S1-11 main-repo-error](S1-11-main-repo-error.md)
