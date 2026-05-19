# Browser / Chrome / Computer Use UI Evidence Templates

> 本模板用于 AreaMatrix 任务中的 UI / GUI / web 补证。它只说明何时使用 Browser、Chrome、Computer Use，以及如何记录证据；不启动 UI 自动化，不替代命令门禁，不修改产品代码，不保存真实用户数据或截图。

## 官方能力基线

截至 2026-05-16，已用 OpenAI Docs MCP 核对：

- [Codex Browser](https://developers.openai.com/codex/app/browser#browser-use)：用于 Codex in-app browser。适合本地 dev server、file-backed preview、点击、输入、渲染状态检查、截图和页面修复验证。
- [Codex Chrome extension](https://developers.openai.com/codex/app/chrome-extension)：用于需要用户 Chrome profile、cookies、扩展、已有登录态或远程认证网站的浏览器任务；本地 preview 和不需要登录的公开页面优先用 Browser。
- [Codex Computer Use](https://developers.openai.com/codex/app/computer-use#when-to-use-computer-use)：用于依赖 GUI 且难以只靠文件或命令输出证明的任务；本地 web app 仍优先用 Browser。

这些工具只能补充 UI 证据。正式完成门禁仍按任务范围运行 `cargo`、`xcodebuild`、SwiftFormat / SwiftLint、prompt doctor、governance、skill checks、docs / UDL / Core API 核对或 manifest 指定命令。

## 触发条件表

| 工具 | 何时使用 | AreaMatrix 默认位置 | 不能替代 |
|---|---|---|---|
| Browser | `localhost` / `127.0.0.1` dev server、`file://` 或 file-backed preview、docs preview、本地静态报告、页面截图、点击 / 输入 / 渲染验证 | 本地 web / 文档预览补证；不依赖用户 Chrome profile | Rust / Swift / prompt / governance / skill 命令门禁；macOS SwiftUI 真实窗口验收 |
| Chrome | 任务必须使用用户 Chrome profile、cookies、扩展、已有 tab、远程登录态网站或内部工具 | 只在 Browser 无法覆盖登录态 / profile / extension 依赖时使用 | 本地 dev server 普通验证；账号、安全、支付、隐私或不可逆网站操作的人工判断 |
| Computer Use | macOS app、SwiftUI 窗口、菜单、sheet、alert、GUI-only bug、跨 app 工作流、无法从命令输出观察的真实窗口状态 | macOS UI smoke 补证；详见 [Computer Use macOS UI smoke runbook](computer-use-macos-ui-smoke-runbook.md) | `xcodebuild`、`./dev test macos`、SwiftFormat / SwiftLint、Rust tests、prompt verify、docs / UDL / Core API 核对 |

## 禁止动作

| 工具 | 禁止动作 |
|---|---|
| Browser | 不处理真实账号敏感操作；不提交密码、token、支付、账号安全、隐私设置或不可逆远程表单；不把公开网页或本地 preview 的截图当成命令验证通过；不保存含真实用户数据的截图 |
| Chrome | 只在需要用户登录态、cookies、profile、扩展或远程认证页面时使用；不默认用 Chrome 做本地 preview；不访问或导出浏览历史、书签、下载内容、私有文件 URL，除非任务明确需要且用户确认；不执行账号、安全、支付、隐私或不可逆网站操作 |
| Computer Use | 不点击系统权限、隐私授权、Keychain、管理员密码、Full Disk Access、Screen Recording、Accessibility、Files and Folders prompt；不对真实用户文件点击删除、移动、覆盖、重命名、清空废纸篓、reindex、repair 或 iCloud 下载确认；不操作 Terminal、Codex 或任何试图绕过 sandbox / approval 的界面 |

## UI Evidence Checklist

记录 UI 证据时，至少包含：

| 项 | 必填内容 |
|---|---|
| Scope | task label、页面 / 窗口 / flow，说明这只是 UI 补证 |
| Tool choice | Browser / Chrome / Computer Use，写明触发条件和为什么不是另一个工具 |
| Command gates | 列出已经运行或必须补跑的命令门禁；若无法运行，写 `BLOCKED` 和原因 |
| Target state | URL / window title / app name / tab group / build artifact / fixture repo；不得使用个人资料库作为默认目标 |
| Steps | 3 到 5 个最小可复现步骤：打开、点击、输入、菜单、sheet、alert 或状态切换 |
| Observable evidence | 截图路径或当前 thread 附图、可见文本、按钮状态、row count、alert 文案、rendered layout；不得保存真实用户数据截图 |
| Safety notes | 是否使用 fixture / QA repo；确认没有密码、支付、系统权限、隐私授权、真实用户文件破坏性确认或不可逆远程操作 |
| Supplemental command | UI smoke 后补一条命令侧验证，例如 `git diff --check`、prompt doctor、targeted XCTest、fixture checksum、DB integrity check 或 manifest gate |
| Result | `PASS` / `FAIL` / `BLOCKED`，并说明 residual risk |

## 最小模板

```text
UI evidence:
- Scope: <task label / page / window / flow; supplemental only>
- Tool choice: <Browser / Chrome / Computer Use>; trigger=<why this tool>
- Command gates:
  - `<command>`: PASS / FAIL / BLOCKED, <key result>
- Target state:
  - URL / app / window / tab: <observed target>
  - Build / fixture: <debug app, local server, file preview, QA repo path>
- Steps:
  1. <open / navigate / click / type / menu / sheet / alert>
  2. <state transition>
  3. <assert visible or rendered state>
- Observable evidence:
  - Screenshot / state: <attached synthetic screenshot or observable text/state>
  - No real user data screenshot: yes / no, <explain if blocked>
- Safety notes:
  - <fixture-only / no real account sensitive operation / no irreversible UI action>
- Supplemental command:
  - `<command>`: PASS / FAIL / BLOCKED
- Result: PASS / FAIL / BLOCKED
- Residual risk: <local smoke only, not release / clean machine / real account proof>
```

## Mission-Critical Escalation

立即停止 UI 自动化并回到 Mission-Critical 流程的情况：

- 真实用户文件、非空目录接管、reindex、repair、iCloud placeholder、删除 / 移动 / 覆盖 / 重命名确认。
- 隐私、远程 AI、浏览历史、用户账号、cookies、内部网站、真实业务数据或用户数据离开本机。
- 支付、计费、账号安全、权限变更、系统隐私授权、管理员认证、Keychain 或不可逆网站 / app 操作。
- 模板执行必须依赖真实 UI 操作才能写清楚。

Mission-Critical 流程必须先说明影响、风险、验证、回滚和人工确认。没有确认时，结论写 `BLOCKED`，不要用 Browser、Chrome 或 Computer Use 补证绕过。

## 判定规则

- `PASS`：命令门禁已有新鲜证据，UI 工具完成 scoped 操作，observable evidence 与预期一致，且未越过安全边界。
- `FAIL`：UI 状态与任务预期不一致，操作无法完成，或 UI smoke 暴露功能错误。
- `BLOCKED`：缺权限、缺目标环境、出现真实用户文件 / 隐私 / 远程账号 / 高影响确认，或无法在不执行真实 UI 自动化的前提下写清模板。

UI smoke、截图、页面状态、mock-only 路径、fixture-only 路径或 agent 自述，都不能覆盖失败或未运行的 `cargo`、`xcodebuild`、prompt doctor、governance、skill checks、review / security / dependency / CI / Git evidence gate。
