# Computer Use macOS UI Smoke Runbook

> 本 runbook 用于 AreaMatrix macOS SwiftUI 任务完成后的真实 UI smoke 补证。它只补窗口、点击、输入、菜单、截图或状态检查证据，不替代 Rust tests、`xcodebuild`、SwiftLint / SwiftFormat、prompt verify、文档 / UDL / Core API 核对。

## 官方能力基线

截至 2026-05-15，已用 OpenAI Docs MCP 核对 [Codex Computer Use 官方文档](https://developers.openai.com/codex/app/computer-use)：

- Computer Use 在 Codex app 中用于 macOS 图形界面，可以读取屏幕、截图，并操作窗口、菜单、键盘输入和剪贴板状态。
- 使用前需要安装 Computer Use plugin，并由用户在 macOS 授权 Screen Recording 与 Accessibility。
- Codex 对具体 app 的使用仍有 app approval；文件读写和 shell 命令仍受当前 thread 的 sandbox / approval 设置约束。
- 本地 web app 优先使用 Codex in-app Browser。
- Computer Use 不能自动化 Terminal app 或 Codex 本身，也不能以管理员身份认证，不能批准 macOS 安全与隐私权限提示。
- 可见 app 内容、浏览器页面、截图和打开的文件都可能被 Codex 作为上下文处理，因此敏感窗口应在任务前关闭。

## 何时使用

| 工具 | 使用场景 | AreaMatrix 边界 |
|---|---|---|
| Computer Use | macOS SwiftUI 真实窗口、按钮、菜单、输入框、sheet、alert、首屏、视觉状态、GUI-only bug 复现 | 只作为 UI smoke 补证；必须搭配命令验证；不得自动处理密码、支付、系统权限、隐私授权或真实用户文件破坏性确认 |
| Browser | `localhost`、`127.0.0.1`、`file://`、docs preview、本地静态报告或 web inspector 类页面 | 本地 web app / 文档预览优先用 Browser；不把 Browser 当 macOS app 验收 |
| Chrome | 需要用户 Chrome profile、cookies、扩展、已有 tab 或远程认证页面 | 仅在任务确实依赖用户 Chrome 状态时使用；账号、安全、支付、隐私相关动作必须用户在场确认 |
| 命令测试 | Rust、Core API、UDL、Swift build/test、SwiftLint、SwiftFormat、prompt doctor、governance / skill check | 这是正式门禁；Computer Use 通过不得覆盖命令失败或未运行 |

## 前置检查

1. 先按 task / manifest / docs 确认验收范围，尤其是 `apps/macos/AGENTS.md` 和 `docs/development/testing.md`。
2. 先运行该任务要求的命令门禁。macOS UI 改动至少需要 `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` 和 `./dev test macos`，除非任务 manifest 给出更窄或更宽的验证。
3. 使用专用 QA repo、临时目录或 fixture 文件；不要对用户真实资料库做删除、移动、覆盖、rename、reindex 或 repair 流程。
4. 关闭不相关的敏感 app、浏览器页面和文件窗口。
5. 若 macOS 弹出 Screen Recording、Accessibility、Full Disk Access、Files and Folders、iCloud、Keychain、admin password 等权限或认证提示，由用户人工判断和操作；Codex 不点击批准。
6. 每次只给 Computer Use 一个明确目标 app / window / flow，避免跨窗口误操作。

## 执行步骤

1. 用命令构建或启动目标 `.app`。不要要求 Computer Use 操作 Terminal 或 Codex；需要 shell 时使用普通命令工具。
2. 用 Computer Use 读取目标 app 状态，记录 app 名、窗口标题、主要可见区域和当前页面。
3. 执行 3 到 5 个最小但有代表性的 UI 操作，例如点击主按钮、打开菜单、输入合成测试文本、关闭 sheet、确认只读状态。
4. 对每个关键断言保留截图或状态描述。截图可附在当前对话，或记录为可追溯的本地 artifact 路径。
5. UI smoke 后补一条命令侧验证，证明 UI 操作没有破坏底层状态。例如 DB `PRAGMA integrity_check`、fixture checksum、`git diff --check`、相关 XCTest 或 prompt doctor。
6. 若遇到权限、隐私、用户文件破坏性确认或真实账号动作，停止自动化并标记 `BLOCKED`，等待用户人工介入。

## 安全边界

Computer Use 不得自动执行：

- 输入或提交密码、token、恢复码、支付信息、管理员密码。
- 批准系统权限、隐私授权、Keychain、TCC、Screen Recording、Accessibility、Full Disk Access 或 Files and Folders prompt。
- 对真实用户文件点击删除、移动、覆盖、重命名、清空废纸篓、reindex、repair、iCloud 下载确认。
- 在已登录浏览器里进行账号、安全、网络、支付、隐私或不可逆设置变更。
- 操作 Terminal、Codex、shell prompt 或任何试图绕过 Codex sandbox / approval 的界面。

如果产品流程本身包含破坏性确认，只能在合成 fixture / QA repo 上 smoke；若任务必须覆盖真实用户文件边界，先回到 Mission-Critical 流程，说明影响、风险、验证、回滚并等待明确确认。

## 最小证据格式

```text
UI smoke evidence:
- Scope: <task label / page / flow>
- Command gates:
  - `<command>`: PASS / FAIL / BLOCKED, <key result>
- Target app/window:
  - App: AreaMatrix
  - Window title: <observed title>
  - Build/artifact: <Debug app / Release local QA app / DMG app>
- Environment:
  - macOS: <version if relevant>
  - Repo fixture: <temp QA repo path, never personal library>
- Steps:
  1. <click/menu/input>
  2. <click/menu/input>
  3. <state assertion>
- Visual/status evidence:
  - Screenshot: <attached in thread or artifact path>
  - Observed state: <visible label / button enabled state / alert text / row count>
- Safety notes:
  - <no passwords / no system permission prompt / fixture-only user files>
- Result: PASS / FAIL / BLOCKED
- Residual risk: <for example: local QA smoke only, not clean Mac / Gatekeeper / notarized app>
```

## 判定规则

- `PASS`：命令门禁通过，Computer Use 看到目标窗口并完成 scoped UI 操作，截图或状态证据与预期一致，且没有越过安全边界。
- `FAIL`：目标 UI 与任务预期不一致，点击或输入无法完成，或 UI smoke 暴露真实功能错误。
- `BLOCKED`：缺少 macOS 权限、目标 app 无法启动、环境没有真实 iCloud / Finder / signed app 条件、出现系统隐私或用户文件确认，需要用户或外部环境介入。

Release 相关 smoke 必须标清证据等级。`local QA smoke` 只能证明当前开发机上的受控构建可打开和可交互，不能写成 clean Mac、Gatekeeper、Developer ID signing、notarization 或正式 DMG 放行证据。

## 示例

```text
UI smoke evidence:
- Scope: S1 settings page smoke after `2-x/task-yy`
- Command gates:
  - `xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO`: PASS
  - `./dev test macos`: PASS
- Target app/window:
  - App: AreaMatrix
  - Window title: AreaMatrix
  - Build/artifact: Debug app from current workspace
- Environment:
  - Repo fixture: `/tmp/areamatrix-ui-smoke/settings-fixture`
- Steps:
  1. Opened AreaMatrix and observed the main three-column shell.
  2. Clicked Settings.
  3. Typed `ui-smoke-fixture` into the synthetic note field.
  4. Closed the sheet and reopened Settings.
- Visual/status evidence:
  - Screenshot: attached in current Codex thread
  - Observed state: Settings button enabled; synthetic value visible after reopen.
- Safety notes:
  - Fixture-only repo; no password, system permission, payment, privacy, or real user file confirmation.
- Result: PASS
- Residual risk: Local UI smoke only; not a release clean-Mac launch proof.
```
