# S1-05 initializing - 初始化 / 接管中

> 所属阶段：Stage 1 MVP
> 页面 ID：S1-05
> 页面类型：首次启动
> 页面文件：`S1-05-initializing.md`
> 上级索引：[stage-1-mvp.md](../stage-1-mvp.md)

## 开发位置

- **目标平台**：macOS 首次启动向导
- **建议目录**：`apps/macos/AreaMatrix/Features/Onboarding/`
- **建议组件**：`InitializingStepView`、`InitProgressView`、`OnboardingStore`
- **实现说明**：绑定 Core 初始化/接管进度回调。页面可取消，但取消不应删除用户原文件。

## 页面背景

用户已经确认初始化或接管。AreaMatrix 正在创建内部目录、初始化数据库、扫描文件、写入索引和生成概览。

## 页面功能

- 显示当前资料库路径。
- 显示当前阶段和总进度。
- 显示接管扫描数量和当前文件。
- 允许用户取消或等待完成。

## 布局与内容

标题按场景变化：

- 空目录：`正在创建资料库`
- 非空目录：`正在接管已有目录`

路径信息框显示 repoPath。

进度区：

- 当前阶段，例如 `正在初始化本地索引`。
- 线性进度条；未知总量时使用 spinner。
- 详情，例如 `已扫描：324 / 1200 个文件`。
- 当前文件，例如 `docs/contracts/2026-q1.pdf`。

步骤列表：

- 创建 `.areamatrix/`
- 初始化 `index.db`
- 创建默认分类
- 扫描现有文件
- 写入索引
- 生成资料库概览

底部按钮：`Cancel`。

## 状态与规则

- 默认状态：进入页面后立即执行初始化/接管，Back 和主初始化按钮不再显示。
- 执行中禁用重复初始化；Cancel 确认弹窗打开时禁用底层进度页交互。
- 空目录初始化可显示较短步骤列表。
- 非空目录接管必须显示扫描进度。
- 单个文件不可访问时显示 warning，继续处理其他文件。
- Core 返回 fatal error 时进入 `S1-06 init-failed`。
- 用户点击 Cancel 后进入 paused/interrupted 语义：已完成的 metadata 步骤保留为可恢复状态，未完成的 staging 临时项由 Core 清理或标记为可恢复；不得删除用户原文件。
- Cancel 后如果 Core 无法确认安全暂停，按钮显示处理中并等待当前安全点，不允许强制删除 `.areamatrix/`。

## 交互

- 点击 `Cancel` 弹确认：`退出初始化？AreaMatrix 会在下次启动时继续或清理未完成状态。`
- 确认 Cancel 后，当前任务在安全点停止，页面进入 `正在暂停...`，完成后退出向导；下次启动进入 `S1-06 init-failed` 的恢复说明或回到本页继续。
- 用户取消 Cancel 确认后继续当前初始化。
- 初始化成功自动进入 `S1-07 init-done`。
- fatal error 自动进入 `S1-06 init-failed`，保留错误码和恢复信息。
- 强制退出后，下次启动应把 Running scan session 标记为 Interrupted，并提供 Resume / Clean up and retry。

## 数据与依赖

- Core init/adopt progress callback。
- scan session 状态。
- staging recovery 状态。
- cancel/pause request state。

## 验收清单

- 长时间扫描时 UI 有可见进度，不像卡死。
- 取消不影响用户已有文件，并有下次恢复路径。
- fatal error 能进入失败页。
- 强退后重启能看到 Resume 或 Clean up and retry，不静默重跑危险操作。

## 来源

- `docs/ux/first-launch.md#5-initializing初始化中`（直接）。

---

## Related

- [Stage 1 页面索引](../stage-1-mvp.md)
- [逐页 UI 开发规格索引](../README.md)
- [S1-06 init-failed](S1-06-init-failed.md)
- [S1-07 init-done](S1-07-init-done.md)
