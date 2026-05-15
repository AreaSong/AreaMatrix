# Codex Workflow And Tools Reference

本文档记录当前 Codex 工作流、原生工具、hooks、MCP、plugins、skills、Computer Use / Browser Use 以及它们在 AreaMatrix 中的落点。

> 说明：本文只描述 Codex 运行材料和协作方式，不是 AreaMatrix 产品语义的源事实。产品、架构、API 和用户体验仍以 `docs/` 为准。

## 当前结论

新的 Codex 工作流已经不是单一聊天框或单一 shell。它更接近一个可组合的 agent runtime：

```text
AGENTS.md / rules
-> skills / plugins / MCP
-> shell / apply_patch / web search / browser use / computer use
-> hooks / permissions / sandbox
-> codex exec / app-server / cloud / task-loop
-> verification / checkpoint / archive
```

AreaMatrix 当前对应关系：

- `workflow/`：大功能、版本、重构和优化的规划生命周期。
- `tasks/prompts/**`：已经批准的 live task queue。
- `./task-loop`：串联 copy-ready 与 verify-ready 的自动执行闭环。
- `.codex/skills-src/**`：AreaMatrix repo-local skills 的源事实。
- `.agents/skills/**`：repo-local skill 发现入口。
- `.codex/references/**`：Codex 运行参考材料，不承载产品语义。

## 本机当前状态

当前本机 Codex CLI：

```bash
codex --version
# codex-cli 0.130.0-alpha.5
```

当前默认模型配置在 `~/.codex/config.toml`：

```toml
model_provider = "cliproxyapi"
model = "gpt-5.5"
model_reasoning_effort = "xhigh"
```

当前 AreaMatrix task-loop 子进程形态：

```bash
codex exec -m gpt-5.5 \
  -c model_reasoning_effort=xhigh \
  --full-auto \
  -s danger-full-access \
  --cd /Users/as/Ai-Project/project/AreaMatrix \
  -o .codex/task-loop-logs/<run_id>/<task>-copy-attempt-1.log \
  -
```

当前已启用的主要 feature flags：

- `hooks`: stable, enabled
- `plugins`: stable, enabled
- `computer_use`: stable, enabled
- `browser_use`: stable, enabled
- `in_app_browser`: stable, enabled
- `image_generation`: stable, enabled
- `multi_agent`: stable, enabled
- `shell_tool`: stable, enabled
- `unified_exec`: stable, enabled
- `workspace_dependencies`: stable, enabled
- `memories`: experimental, enabled
- `plugin_hooks`: under development, disabled
- `remote_control`: under development, disabled
- `builtin_mcp`: under development, disabled

当前已安装但未启用的 bundled plugin：

- `latex-tectonic@openai-bundled`：存在于 bundled marketplace，可提供 LaTeX / Tectonic 相关能力；当前 `~/.codex/config.toml` 未启用。

## 官方文档入口

优先使用官方 OpenAI 文档：

- Codex docs home: https://developers.openai.com/codex
- Codex workflows: https://developers.openai.com/codex/workflows
- Codex CLI reference: https://developers.openai.com/codex/cli/reference
- Codex hooks: https://developers.openai.com/codex/hooks
- Codex plugins: https://developers.openai.com/codex/plugins
- Codex skills: https://developers.openai.com/codex/skills
- Codex MCP: https://developers.openai.com/codex/mcp
- Codex Computer Use: https://developers.openai.com/codex/app/computer-use
- Codex App features: https://developers.openai.com/codex/app
- Codex Automations: https://developers.openai.com/codex/app/automations
- Codex In-app Browser: https://developers.openai.com/codex/app/in-app-browser
- Codex Chrome Extension: https://developers.openai.com/codex/chrome
- Codex IDE Extension: https://developers.openai.com/codex/ide
- Codex Web: https://developers.openai.com/codex/web
- Codex GitHub integration: https://developers.openai.com/codex/github
- Codex GitHub Action: https://developers.openai.com/codex/github-action
- Codex Slack integration: https://developers.openai.com/codex/slack
- Codex Linear integration: https://developers.openai.com/codex/linear
- Codex Worktrees: https://developers.openai.com/codex/worktrees
- Codex Local Environments: https://developers.openai.com/codex/local-environments
- Codex Subagents: https://developers.openai.com/codex/subagents
- Codex SDK: https://developers.openai.com/codex/sdk
- Codex Security: https://developers.openai.com/codex/security
- Codex Config: https://developers.openai.com/codex/config
- Codex Feature Maturity: https://developers.openai.com/codex/feature-maturity
- Codex Open Source: https://developers.openai.com/codex/open-source
- OpenAI model docs: https://developers.openai.com/api/docs/models
- GPT-5.5 model docs: https://developers.openai.com/api/docs/models/gpt-5.5

截至 2026-05-15 本轮核对，Codex 官方文档目录还包含以下工作层面。它们不一定都是 AreaMatrix 当前执行路径，但属于最新官网公开的 Codex 工作面：

- Getting Started：Overview、Quickstart、Explore use cases、Migrate、Pricing。
- Concepts：Prompting、Customization、Memories / Chronicle、Sandboxing / Auto-review、Subagents、Workflows、Models、Cyber Safety。
- App：Overview、Features、Settings、Review、Automations、Worktrees、Local Environments、In-app browser、Chrome extension、Computer Use、Commands、Windows、Troubleshooting。
- IDE Extension：Overview、Features、Settings、IDE Commands、Slash commands。
- CLI：Overview、Features、Command Line Options、Slash commands。
- Web：Overview、Environments、Internet Access。
- Integrations：GitHub、Slack、Linear。
- Codex Security：Overview、Setup、Improving the threat model、FAQ。
- Configuration：Config Basics、Advanced Config、Config Reference、Sample Config、Speed、Rules、Hooks、AGENTS.md、MCP、Plugins、Build plugins、Skills、Subagents。
- Administration：Authentication、Access tokens、Agent approvals & security、Remote connections、Enterprise Admin Setup、Enterprise Governance、Managed configuration、Windows。
- Automation：Non-interactive Mode、Codex SDK、App Server、MCP Server、GitHub Action。
- Learn：Best practices、Videos、Community、Using skills to accelerate OSS maintenance、Building frontend UIs with Codex and Figma、Build an Agent Improvement Loop with Traces/Evals/Codex、Build iterative repair loops with Codex、Building AI Teams。
- Releases：Changelog、Feature Maturity、Open Source。

本机已安装官方 OpenAI Docs MCP：

```bash
codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp
codex mcp list
```

`openaiDeveloperDocs` 是只读文档 MCP，用于从 Codex 中查 OpenAI developer docs；它不是业务 API 调用凭证，也不替代仓库文档。

## Codex 原生命令入口

常用命令：

```bash
codex
codex exec
codex review
codex login
codex logout
codex mcp
codex plugin
codex mcp-server
codex app-server
codex remote-control
codex app
codex completion
codex update
codex cloud
codex apply
codex resume
codex fork
codex exec-server
codex sandbox
codex debug
codex features
```

关键用途：

- `codex`：交互式 TUI。
- `codex exec`：非交互执行，适合 task-loop、CI-like repair、脚本化验证。
- `codex review`：非交互 code review。
- `codex login` / `codex logout`：管理本机认证；`login status` 可查登录状态。
- `codex mcp`：管理外部 MCP server。
- `codex plugin`：管理 plugin marketplace。
- `codex mcp-server`：把 Codex 暴露成 MCP server。
- `codex app-server`：实验性 app server / protocol tooling。
- `codex remote-control`：实验性 headless app-server remote control。
- `codex app`：打开 Codex Desktop app，可指定 workspace path。
- `codex completion`：生成 shell completion，支持 bash / elvish / fish / powershell / zsh。
- `codex update`：更新 Codex CLI。
- `codex cloud`：浏览、提交、查看、应用 Codex Cloud task。
- `codex apply`：把 Codex task diff 应用到本地 worktree。
- `codex resume`：恢复已有交互 session。
- `codex fork`：从已有交互 session fork 新会话。
- `codex exec-server`：实验性 standalone exec-server。
- `codex sandbox`：用 Codex 提供的 macOS / Linux / Windows sandbox 跑命令。
- `codex debug`：查看模型 catalog、app-server 调试、prompt input。
- `codex features`：查看或切换 feature flags。

`codex exec` 常用参数：

```bash
codex exec -m gpt-5.5 -C /path/to/repo "prompt"
codex exec -c model_reasoning_effort=xhigh "prompt"
codex exec -s read-only "read-only verify prompt"
codex exec -s workspace-write "implementation prompt"
codex exec --json "machine-readable run"
codex exec --output-last-message /tmp/last-message.txt "prompt"
codex exec --skip-git-repo-check "prompt"
codex exec --ephemeral "do not persist session files"
codex exec --ignore-user-config "ignore config.toml defaults"
codex exec --ignore-rules "ignore user/project execpolicy rules"
codex exec --output-schema schema.json "structured output"
```

注意：`codex exec` 的真实运行配置以启动 header 和命令参数为准；只看 `config.toml` 可能不够。

## Native Tools

Codex 当前可组合的工具大致分为几类。

Shell 与文件：

- `shell_tool` / `unified_exec`：执行 shell 命令，适合检查、构建、测试、格式化。
- `apply_patch`：结构化修改文件，适合精确补丁。
- `workspace_dependencies`：读取本地打包的运行时和文档/表格/幻灯片处理库路径。
- `sandbox`：限制命令访问边界，按平台使用 macOS Seatbelt、Linux bubblewrap / landlock、Windows restricted token。

检索与文档：

- `web search`：CLI 可用 `--search` 暴露 native Responses `web_search`。
- `MCP`：接入官方文档、Context7、DeepWiki、time、Chrome DevTools 等外部上下文。
- `tool_search` / `tool_suggest`：在可用工具很多时辅助查找工具。

UI 与视觉：

- `computer_use`：看屏幕并操作本机应用。
- `browser_use`：操作 Codex in-app browser，适合 localhost / file URL / 普通网页验证。
- `chrome`：操作用户 Chrome，适合登录态、扩展、已有 profile、远程认证页面。
- `image_generation`：生成或编辑 bitmap 视觉资产。

协作与自动化：

- `multi_agent`：并行子 agent。
- `plugins`：打包和安装 skills、MCP、app integrations。
- `hooks`：在 Codex 生命周期里运行确定性命令。
- `cloud`：云端任务与本地 diff 应用。
- `app-server` / `remote-control` / `exec-server`：实验性远程控制、协议和执行器能力，当前不作为 AreaMatrix 主路径。

官方存在但 AreaMatrix 当前不落地的 Codex 工作面：

- Automations：Codex app 中的自动化任务/周期性工作流；当前 AreaMatrix 用 `./task-loop` 管 live queue，不依赖 Codex app automations。
- Worktrees：Codex Cloud / app 可围绕独立 worktree 管理任务；当前 AreaMatrix live runner 直接跑本仓库 checkout。
- Local Environments：为 Cloud / remote work 配置环境初始化；当前 AreaMatrix 主要用本机 dev tools。
- App Review / Commands / Windows / Troubleshooting：属于 Codex app 的操作层能力；当前 AreaMatrix 只记录入口，不把它们作为 task-loop 必需门禁。
- IDE Extension / Web / GitHub / Slack / Linear integrations：属于官方入口和协作集成；当前未作为 AreaMatrix 必要执行入口。
- Authentication / Access tokens / Agent approvals & security / Remote connections / Enterprise managed configuration：属于管理、权限和企业治理层；当前 AreaMatrix 只记录为官方工作面，不在项目内保存任何凭证。
- GitHub Action：可用于把 Codex 接入 GitHub workflow；当前 AreaMatrix 仍以本地 `./dev check ...` 与仓库 CI 配置为准。
- Subagents / SDK：官方支持更复杂的 agent 编排和嵌入式开发；当前 AreaMatrix 只在需要并行代码探索/实现时临时使用 subagent，不作为固定 task-loop 协议。
- Learn / Releases：Best practices、Changelog、Feature Maturity、Open Source 等用于跟踪官方变化；每次声称“最新”前都应重新打开官方目录核对。

## MCP

MCP 用于把外部工具和资料接入 Codex。当前本机 MCP：

```text
context7             npx -y @upstash/context7-mcp
sequential-thinking  npx -y @modelcontextprotocol/server-sequential-thinking
mcp-server-time      uvx mcp-server-time --local-timezone=Asia/Shanghai
mcp-deepwiki         npx -y mcp-deepwiki@latest
chrome-devtools      npx -y chrome-devtools-mcp@latest
computer-use         Codex Computer Use MCP client
openaiDeveloperDocs  https://developers.openai.com/mcp
```

使用原则：

- OpenAI 相关问题优先查 `openaiDeveloperDocs` 或官方域名。
- 第三方库/API 优先用 Context7 查官方文档。
- GitHub repo 架构梳理可以用 DeepWiki。
- 本机时间转换用 time MCP。
- 浏览器调试可用 Chrome DevTools MCP 或 Browser/Chrome plugin。

## Plugins

Plugin 是 Codex 的分发单元，可以包含：

- skills
- MCP servers
- app integrations
- runtime-specific capabilities

当前启用插件：

```toml
[plugins."documents@openai-primary-runtime"]
enabled = true

[plugins."spreadsheets@openai-primary-runtime"]
enabled = true

[plugins."presentations@openai-primary-runtime"]
enabled = true

[plugins."computer-use@openai-bundled"]
enabled = true

[plugins."browser-use@openai-bundled"]
enabled = true

[plugins."chrome@openai-bundled"]
enabled = true
```

当前 bundled marketplace 还包含但未启用：

- `latex-tectonic@openai-bundled`

常用插件能力：

- Documents：创建、编辑、渲染、验证 `.docx`。
- Spreadsheets：分析、生成、修改 `.xlsx` / `.csv` 等。
- Presentations：生成、编辑、渲染、导出 slide deck。
- Browser：操作 Codex in-app browser。
- Chrome：操作用户 Chrome。
- Computer Use：操作 macOS app UI。
- LaTeX / Tectonic：当前未启用；只有文档排版确实需要时再开启。

## Skills

Skill 是 Codex 可复用工作流，通常由 `SKILL.md` 加 `references/`、`scripts/`、`templates/`、`assets/` 组成。

AreaMatrix repo-local skills：

- `areamatrix-task-loop`：启动、监控、恢复 silent task-loop。
- `areamatrix-validation-driver`：按改动范围选择最小充分验证集。
- `areamatrix-doc-sync`：防止 docs / API / UDL / prompt manifest 漂移。
- `areamatrix-file-safety`：用户文件、staging、metadata、migration 等高风险边界。
- `areamatrix-git-checkpoint`：PASS task 的 commit / push / 恢复策略。
- `areamatrix-workflow-planning`：v* workflow discussion gate、版本骨架、规划生命周期。
- `areamatrix-enterprise-governance`：review、安全、依赖、CI、CODEOWNERS 治理。

AreaMatrix skill 路径规则：

```text
源事实：.codex/skills-src/<skill>/SKILL.md
发现入口：.agents/skills/<skill>/SKILL.md
```

不要让 `codex exec` 猜 `/Users/as/.codex/skills-src/...` 这类全局路径；AreaMatrix 任务 prompt 应写明 repo-local skill 路径。

## Hooks

Hooks 是 Codex 生命周期钩子，用于运行确定性脚本或安全检查。官方支持的事件包括：

- `SessionStart`
- `PreToolUse`
- `PermissionRequest`
- `PostToolUse`
- `UserPromptSubmit`
- `Stop`

Hooks 可从以下位置加载：

- `~/.codex/hooks.json`
- `~/.codex/config.toml`
- `<repo>/.codex/hooks.json`
- `<repo>/.codex/config.toml`

当前本机：

- `hooks` feature 是 stable 且 enabled。
- `plugin_hooks` 仍是 under development 且 disabled。
- AreaMatrix 当前没有 repo-local `.codex/hooks.json`。
- `~/.codex/config.toml` 有 `notify`：

```toml
notify = [
  "/Users/as/.codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient",
  "turn-ended",
]
```

- `~/.codex/config.toml` 里记录了 AreaSong 的 trusted hook hash。

建议用法：

- 适合做轻量、确定性的 preflight / post-check / notification。
- 不适合把核心验收唯一地压在 hooks 上；官方说明 `PreToolUse` 是 guardrail，不是完整 enforcement boundary，且当前不能拦截所有 shell 路径、`WebSearch` 或其他非 shell / 非 MCP 工具。
- 当前 release 行为以官方 Hooks 页面为准；schema `main` 分支可能包含尚未发布字段。
- 只有 `type: "command"` handler 会运行；`prompt`、`agent` 会被解析但跳过，`async: true` command hook 也会被跳过。
- 如果给 AreaMatrix 增加 hooks，优先考虑只读检查，例如防止 live runner 重复启动、提示 dirty worktree 会挡 checkpoint、或在 session start 打印当前 `./dev status` 摘要。

## Computer Use

Computer Use 允许 Codex 读取屏幕、点击、输入、滚动和操作本机 app UI。它需要 macOS 的 Screen Recording 和 Accessibility 权限。

官方当前说明：Computer Use 在 Codex app 中面向 macOS 可用，发布初期不包含欧洲经济区、英国和瑞士。它需要先安装 Computer Use plugin，并在 macOS 授权 Screen Recording 与 Accessibility。Codex 还会对具体 app 使用请求进行审批，文件读写和 shell 仍受当前 thread 的 sandbox / approval 设置约束。

适合场景：

- 验证 macOS SwiftUI app 真实界面。
- 复现只在 GUI 出现的问题。
- 操作需要用户登录态或系统 UI 的流程。
- 对比截图、检查按钮、表单、菜单、窗口状态。

不适合场景：

- 本地 web app 的普通功能验证优先用 Browser plugin。
- 涉及密码、支付、隐私、系统权限授权时应由用户确认。
- 不应作为唯一安全门禁；关键结论仍要用命令、测试、截图或日志证据闭环。

AreaMatrix 中的合理落点：

- macOS app task 完成后，用 Computer Use 进行 smoke UI check。
- 与 `xcodebuild`、SwiftLint、SwiftFormat、Rust tests 搭配，而不是替代它们。
- 通过 screenshots 或操作记录补充验收证据。

## Browser Use 与 Chrome

Browser plugin 用于 Codex in-app browser，适合：

- `localhost` / `127.0.0.1` / `file://` 页面验证。
- 前端开发后的截图、点击、表单、布局检查。
- 不依赖用户 Chrome 登录态的网页流程。

Chrome plugin 用于用户真实 Chrome，适合：

- 需要用户 cookies / 登录态。
- 需要用户 Chrome 扩展。
- 需要检查已有 tab 或远程认证页面。

AreaMatrix 是 macOS 原生 app，Browser/Chrome 不是主验收工具；但 docs preview、本地静态报告、future web inspector 或外部服务登录态可以用它们。

## AreaMatrix 当前工作流

AreaMatrix 当前有两层：

```text
workflow/
  大版本、大功能、重构、优化的规划生命周期

tasks/prompts/**
  已批准、可执行、可验收的 live queue
```

当前 live queue：

- `v1-mvp`
- `637` tasks
- 进度源事实：`tasks/prompts/_shared/progress.json`
- 健康检查：`python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- 状态检查：`python3 tasks/prompts/_shared/prompt_pipeline.py status`
- 自动执行：`./task-loop run`
- 总控入口：`./dev`

`./task-loop` 闭环：

```text
copy-ready
-> codex exec implementation
-> verify-ready
-> read-only acceptance
-> FAIL: inject failure summary and retry same task
-> PASS: update progress, Git checkpoint, next task
```

默认配置：

```bash
MODEL=gpt-5.5
MODEL_REASONING_EFFORT=xhigh
CODEX_EXEC_SANDBOX=danger-full-access
GIT_CHECKPOINT=commit
GIT_BRANCH_POLICY=auto
RISK_GATE=mission-critical
RISK_POLICY=pause
MAX_RETRIES=0
```

全静默执行需要显式：

```bash
RISK_POLICY=allow MAX_RETRIES=0 ./task-loop run
```

需要优雅停止：

```bash
./dev drain
./dev status
```

不要在已有 live runner 时启动第二个 runner。

## 推荐演进方向

短期：

- 保持 AreaMatrix 当前 `./dev + ./task-loop + repo-local skills` 结构。
- 不把 `workflow/` 直接写入 live `tasks/prompts/**`。
- 将 Computer Use 作为 macOS UI smoke 的补充证据。
- 使用 OpenAI Docs MCP 查最新 Codex / model / API 文档。

中期：

- 给 AreaMatrix 增加 repo-local hooks，但先只做只读提示和安全检查。
- 为 macOS UI task 增加 Computer Use 验收 runbook。
- 将常用 task-loop 操作固化为更明确的 `./dev` guide。
- 继续让 repo-local skills 承担治理知识，避免把规则散落在 prompt 里。

高风险边界：

- 不用 hooks 自动修改用户文件。
- 不用 Computer Use 自动处理密码、支付、系统权限、隐私授权。
- 不在 v1 live queue 未完成前移动、重命名或归档 `tasks/prompts/**`。
- 不把 `.codex/` 文档当作产品行为源事实。

## 常用检查命令

Codex / runtime：

```bash
codex --version
codex --help
codex exec --help
codex features list
codex mcp list
```

AreaMatrix：

```bash
./dev status --once
./dev processes
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
python3 tasks/prompts/_shared/prompt_pipeline.py status
./task-loop status
./dev workflow doctor
./dev workflow status
```

Docs / governance：

```bash
./dev check skills
./dev check governance
```
