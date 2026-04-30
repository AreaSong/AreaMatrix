# S4-WIN-03 onedrive-notice - OneDrive 提示

> 所属阶段：Stage 4 多端  
> 页面 ID：S4-WIN-03
> 页面类型：Windows dialog / onboarding step  
> 页面文件：`S4-WIN-03-onedrive-notice.md`  
> 上级索引：[stage-4-multiplatform.md](../stage-4-multiplatform.md)

## 开发位置

- **目标平台**：Windows 桌面端。
- **建议目录**：`apps/windows/AreaMatrix/Features/Onboarding/OneDriveNoticeDialog.*`。
- **建议组件**：`OneDriveNoticeDialog`、`OneDriveStatusProbe`、`CloudPathRiskView`。
- **实现边界**：这是 OneDrive 路径风险提示和确认页，不实现 OneDrive SDK 同步管理，也不尝试修改用户 OneDrive 设置。

## 页面背景

Windows 用户可能把 AreaMatrix repo 放在 OneDrive 中，用于跨设备同步。OneDrive 与 iCloud 类似，会有占位符、延迟下载、同步冲突和组织策略限制。本页要让用户知道这些风险，同时不禁止用户继续使用。

入口：`choose-repo` 检测到 OneDrive 路径；主窗口点击 OneDrive 状态说明。  
退出：用户确认后继续打开或初始化 repo；用户选择其他位置则回到路径选择；已连接场景可进入 watcher 状态页查看事件或手动 rescan 入口。

## 页面功能

- 显示当前选择的 OneDrive 路径。
- 说明 OneDrive 同步延迟和冲突副本风险。
- 说明 AreaMatrix 的安全承诺：不自动删除冲突副本，不覆盖用户文件。
- 提供确认复选框。
- 提供继续使用 OneDrive 或选择本地文件夹的分支。
- 提供等待同步、打开 OneDrive 文件夹、进入 watcher 状态页的可操作建议。
- 对高风险写入说明必须先经过导入确认、Replace 二次确认或 rescan 确认。
- 已连接场景下显示只读状态，不要求重复确认。

## 布局与内容

推荐使用模态 dialog 或 onboarding 步骤页，视觉以黄色提示为主，不使用危险红色。

标题：`OneDrive folder detected`

说明文案：
`This repository is inside OneDrive. AreaMatrix can use it, but sync timing and conflict copies are controlled by OneDrive.`

路径卡片：
- `Folder: C:\Users\you\OneDrive\AreaMatrix`
- `Sync provider: OneDrive`
- `Status: Available`、`Syncing`、`Unknown`

风险说明列表：
- `Files may appear before they are fully downloaded.`
- `Conflict copies may be created when multiple devices edit the same file.`
- `AreaMatrix will not delete either version automatically.`
- `AreaMatrix cannot control OneDrive sync timing and does not use the OneDrive SDK to manage sync.`

操作建议区：
- `Wait for OneDrive sync`：说明用户可等待 OneDrive 客户端完成同步后再重试。
- `Open OneDrive folder`：用 Explorer 打开当前路径，便于用户查看 OneDrive 客户端状态。
- `Choose Local Folder`：回到资料库选择，改用本地目录。
- `Open watcher status`：已连接场景显示，进入 [S4-WIN-04 watcher-status](S4-WIN-04-watcher-status.md)，需要手动 rescan 时仍必须再进入 [S4-X-07 rescan-confirm](S4-X-07-rescan-confirm.md)。

确认项：
- `I understand OneDrive sync may be delayed or create conflict copies.`

底部按钮：
- `Choose Local Folder`
- `Continue with OneDrive`

已连接说明版：
- 不显示确认复选框。
- 按钮：`Open OneDrive Folder`、`Open watcher status`、`Close`。

## 状态与规则

- 默认状态：首次从选择流程进入时显示路径、风险说明和未勾选确认项；`Continue with OneDrive` 禁用，`Choose Local Folder` 可用。
- 空态：未收到 OneDrive 路径或路径已被清空时显示 `Choose a folder first.`，只保留 `Choose Local Folder` 和 `Close`。
- 已连接说明态：从主窗口状态入口进入时不显示确认项；`Open OneDrive Folder` 和 `Close` 可用，页面只读，不阻断用户。
- 首次选择 OneDrive：必须勾选确认项才能继续。
- 加载态：检测 OneDrive 状态时显示 `Checking OneDrive status...`，主按钮等待确认项和检测结果。
- OneDrive 状态不可检测：显示 `Status: Unknown`，仍允许确认继续。
- 错误态：检测失败、路径丢失、权限不足或上游 repo 检测阻断时显示具体原因；检测失败显示 `Status: Unknown` 和 `AreaMatrix cannot control OneDrive sync timing.`，不阻塞只读浏览；不得把同步状态描述为安全完成。
- 组织 OneDrive 路径：显示组织名如果可得；不可得则只显示路径。
- OneDrive 占位符文件：具体文件打开时处理，本页只说明总体风险。
- 高风险写入：导入必须进入 `S4-WIN-05 import-flow`，Replace 必须进入 `S4-X-09 replace-confirm`，手动 rescan 必须进入 `S4-X-07 rescan-confirm`；本页不能直接触发写入。
- 同步状态 Unknown：允许继续连接或浏览，但导入、Replace、rescan 等写入路径仍必须执行各自的 preflight 和确认。
- 用户选择本地文件夹：返回 `choose-repo` 并清空路径或打开 picker。
- 本页不触发 reindex，不写入 repo。
- 禁用条件：未勾选确认项、路径不存在、路径不再位于 OneDrive、上游选择流程正在重新校验或 repo 检测出现阻断错误时，`Continue with OneDrive` 禁用并显示原因。

## 交互

1. 页面打开时从路径检测 OneDrive 类型和状态。
2. 用户阅读确认项并勾选后，主按钮启用。
3. 点击 `Continue with OneDrive` 返回上一流程继续 validate/init/open。
4. 点击 `Choose Local Folder` 打开 folder picker。
5. 点击路径旁 `Open in Explorer` 可打开 OneDrive 文件夹，前提是路径存在。
6. 点击 `Open watcher status` 进入 [S4-WIN-04 watcher-status](S4-WIN-04-watcher-status.md)；如果用户随后选择 `Run rescan now`，必须先看到 [S4-X-07 rescan-confirm](S4-X-07-rescan-confirm.md) 的 dry-run 影响预览和确认。

## 数据与依赖

- OneDrive path detection。
- Windows shell known folder 或环境变量检测。
- 可选 OneDrive sync status probe，状态不可得时降级为 unknown。
- Windows watcher status route。
- Explorer reveal。
- Stage 1 iCloud 风险提示的安全文案迁移。

## 验收清单

- OneDrive 路径首次继续前必须明确确认。
- 页面清楚说明 OneDrive 控制同步时序，AreaMatrix 不能保证即时同步。
- 用户可以选择本地文件夹退出 OneDrive 路径。
- 已连接后的说明版不重复阻塞用户。
- 已连接说明版能进入 watcher 状态页，且手动 rescan 不能绕过 `S4-X-07`。
- OneDrive 同步状态 Unknown 时不会显示“同步安全完成”之类承诺。
- 高风险写入仍由导入确认、Replace 二次确认或 rescan 确认承接。
- 页面明确说明不控制 OneDrive 同步，也不使用 OneDrive SDK 管理同步。
- 不出现“AreaMatrix 将自动解决冲突”的错误承诺。
- Narrator 能读出确认项和主按钮禁用原因。

## 来源

- 来源类型：组合来源。
- 直接来源：`tasks/prompts/phase-4/4-3-stage4-multiplatform/task-36-s4-win-03-onedrive-notice.md`。
- 组合来源：`docs/adr/0006-icloud-support.md` 的云盘风险模型类比。
- 组合来源：`docs/ux/dedup-conflict.md` 的冲突不静默处理原则。
- 推导说明：OneDrive 只提示风险和状态，不承诺控制同步，也不使用 OneDrive SDK 管理同步。

---

## Related

- [阶段索引](../stage-4-multiplatform.md)
- [Windows 资料库选择](S4-WIN-01-choose-repo.md)
- [Windows 主窗口](S4-WIN-02-main-window.md)
- [Windows 文件监听状态](S4-WIN-04-watcher-status.md)
- [手动重扫确认](S4-X-07-rescan-confirm.md)
- [逐页 UI 开发规格索引](../README.md)
