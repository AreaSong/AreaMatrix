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

- OpenAI Docs MCP: https://developers.openai.com/learn/docs-mcp

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

### OpenAI Docs MCP 使用规则

- 涉及 OpenAI、Codex、model、API、SDK、hooks、MCP、skills、plugins、Computer Use 或其他 OpenAI 运行层能力时，优先使用 `openaiDeveloperDocs` 查询官方文档。
- 如果当前 Codex 环境无法使用 `openaiDeveloperDocs`，只能退到 OpenAI 官方域名，例如 `developers.openai.com` 或 `platform.openai.com`；不要用第三方文章或旧记忆替代官方来源。
- 回答“最新”“当前默认”“是否支持”“地区/价格/功能状态”等易变化问题前，必须重新核对官方文档，并在需要固化到仓库时标注核对日期和来源链接。
- OpenAI 官方文档只裁定 OpenAI / Codex 运行层能力和限制，不裁定 AreaMatrix 产品行为。AreaMatrix 产品、架构、API、UX 和开发规范仍以 `docs/**` 为源事实，AI 协作规则仍以 `.ai-governance/**` 为源事实。
- 不在仓库文档中写死易过期的模型、价格、地区、配额或 release 阶段；如果为了追踪当下状态必须记录，必须使用“截至 YYYY-MM-DD 核对”措辞并附官方来源。
- OpenAI Docs MCP 是 documentation-only 的只读文档入口，不是 API key、auth token 或产品运行凭证；仓库不得保存个人 token、auth 配置或全局 `~/.codex/**` 内容。

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

- OpenAI / Codex 相关问题优先查 `openaiDeveloperDocs`；不可用时仅退到 OpenAI 官方域名。
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
- AreaMatrix 当前默认工作层只允许 warn-only / read-only hooks：可以提醒重复 runner、dirty worktree、危险边界或验证缺口，但不使用 block / deny / continue，不自动改文件或改变审批结果。
- P1 repo-local hooks guardrail 的具体设计见 [hooks guardrail runbook](hooks-guardrail-runbook.md)。当前结论是先保留 runbook，不新增 `.codex/hooks.json`；未来如启用，必须只读、需 `/hooks` review / trust，并提供禁用和回滚路径。

## Computer Use

Computer Use 允许 Codex 读取屏幕、点击、输入、滚动和操作本机 app UI。它需要 macOS 的 Screen Recording 和 Accessibility 权限。

官方当前说明：Computer Use 在 Codex app 中面向 macOS 可用，发布初期不包含欧洲经济区、英国和瑞士。它需要先安装 Computer Use plugin，并在 macOS 授权 Screen Recording 与 Accessibility。Codex 还会对具体 app 使用请求进行审批，文件读写和 shell 仍受当前 thread 的 sandbox / approval 设置约束。

AreaMatrix 的 macOS UI smoke 细则见 [Computer Use macOS UI smoke runbook](computer-use-macos-ui-smoke-runbook.md)。它只补真实窗口、点击、输入、菜单、截图或状态检查证据，不替代 Rust tests、`xcodebuild`、SwiftLint / SwiftFormat、prompt verify 或 docs / UDL / Core API 核对。

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
- 密码、系统权限、隐私授权、支付、真实用户文件删除 / 移动 / 覆盖确认必须人工介入；Computer Use 不点击批准。

## Subagents

Subagents 是 Codex 的并行 agent workflow。官方当前说明：Codex 可以 spawn specialized agents 并行探索、处理或分析；Codex 只在明确要求 subagents / parallel agent work 时 spawn；内置 agent 包括 `default`、`worker`、`explorer`；subagents 继承当前 sandbox policy。官方还建议从 read-heavy work 起步，parallel write-heavy workflow 需要谨慎处理冲突和协调成本。

AreaMatrix 的落点见 [Codex subagent boundaries runbook](subagent-boundaries-runbook.md)，源规则见 [Subagent Boundaries](../../.ai-governance/workflows/subagent-boundaries.md)。

AreaMatrix 当前采用：

- explicit-only：用户或当前任务明确要求时才用 subagent。
- 只读探索可并行：独立问题、明确读取范围、禁止写入、返回 evidence。
- 写入实现可谨慎并行：必须先定义 owner 和 disjoint write set。
- live runner 禁区：不让 subagent 修改 progress、logs、run summaries、checkpoint、branch、commit、stash、reset 或 clean；不把同一 live task 拆给多个 writer。
- 主 agent 负责最终整合、diff 复核、验证和结论；subagent 输出不能直接等价于 PASS、checkpoint 成功或 merge-ready。

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

### P0 主线保护

AreaMatrix v1 live execution 的唯一主线是：

```text
AGENTS.md / .ai-governance
-> workflow/ planning gate
-> tasks/prompts/** live queue
-> ./dev / ./task-loop
-> repo-local skills
```

`tasks/backlog/**` 是规划记录和可复制提示词暂存区，不进入 `./task-loop`，不写 `tasks/prompts/_shared/progress.json`，也不替代 `workflow/` 的 planning gate。Codex Automations、Cloud、Worktrees、Vibe-Skills、SDK、app-server、remote-control 目前只能作为候选能力、参考资料或未来评估项；v1 live queue 阶段不得接管 `tasks/prompts/**`、`./dev`、`./task-loop`、progress、checkpoint 或 repo-local skill 主线。

因此，任何优化都不得新增第二套 runner、progress、queue 或 promotion 机制。需要接入外部能力时，先经过 [.ai-governance 外部能力接入门禁](../../.ai-governance/workflows/external-capability-admission.md) 与 `workflow/` gate，并说明 source of truth、触发条件、验证方式、owner，以及是否影响 live 主线。

Automations / Cloud / Worktrees 的细化门禁见 [Codex Automations / Cloud / Worktrees Gate](codex-automations-cloud-worktrees-gate.md)。当前结论是：Automations 只允许提醒、周期性只读检查和状态汇报候选；Cloud 只作为未来隔离执行候选；Worktrees 只作为隔离实验或并行独立任务候选。三者都不得写 `tasks/prompts/**`、progress、task-loop logs、run summaries、runner lock、checkpoint 或替代 `./task-loop`。

## AreaMatrix 对比矩阵

本节把 OpenAI / Codex 官方能力版图对照到 AreaMatrix 当前项目体系。状态含义：

- `已有`：当前项目已有稳定对应物，短期不需要另起一套。
- `部分已有`：已有基础，但缺制度化规则、runbook 或边界。
- `缺失-建议补`：当前缺口会影响稳定性、证据链或人工负担，建议纳入近期治理。
- `暂不接入`：官方有能力，但当前 v1 live queue 阶段不适合接入主线。
- `仅记录`：只作为官方能力跟踪或未来选项。

| 官方能力 / 工作层面 | AreaMatrix 当前对应物 | 当前状态 | 为什么是这个状态 | 是否建议补 | 补了满足什么 | 风险与边界 | 优先级 |
|---|---|---|---|---|---|---|---|
| AGENTS.md / project instructions | 根 `AGENTS.md`、局部规则读取顺序 | 已有 | 已定义入口顺序、源事实、高风险边界和验证要求 | 不补主结构 | 继续稳定 Codex 行为边界 | 不把 `.codex/` 当产品语义源事实 | P0 保持 |
| Rules / governance | `.ai-governance/`、工程质量规则、file-safety、validation-driver | 已有 | 已覆盖 Quick / Change / Mission-Critical、Forbidden Touches、验证门禁 | 不补主结构 | 继续保证文档驱动和风险分级 | 高风险任务仍需显式说明影响、验证、回滚 | P0 保持 |
| Docs as source of truth | `docs/`、`docs/api/core-api.md`、capability specs、UX specs | 已有 | 项目已明确产品、架构、API、UX 的权威来源 | 不补主结构 | 避免 Codex runtime 文档反客为主 | 代码与 docs 冲突时先按 SSOT 查证 | P0 保持 |
| Workflow / large feature lifecycle | `workflow/`、discussion gate、middle-layer、changes、plans、drafts、queue、promotion preview | 已有 | 已区分规划层和 live queue，v1 live-running 时 dependent versions 不得 promote | 不补主结构 | 保障新 v* 不绕过讨论和规划门禁 | 不从 `workflow/` 直接写 `tasks/prompts/**` | P0 保持 |
| Live task queue | `tasks/prompts/**`、637-task v1-mvp queue、manifest、copy-ready / verify-ready | 已有 | 当前 265/637 完成，`4-1/task-16` 正在跑 | 不补主结构 | 继续作为唯一 live 执行面 | 不启动第二个 live runner | P0 保持 |
| Non-interactive CLI | `codex exec` 由 `./task-loop` 调用 | 已有 | task-loop 已用 `gpt-5.5`、`xhigh`、`danger-full-access` 执行 copy / verify | 不补主结构 | 保持自动闭环能力 | `codex exec` 真实配置以启动参数和 header 为准 | P0 保持 |
| Dev console / local operator UX | `./dev`、`./dev status`、`./dev processes`、`./dev check ...` | 已有 | 已封装状态、进程、恢复、健康检查，避免记忆长命令 | 小幅优化即可 | 降低操作失误和状态误读 | 当前 live runner + dirty worktree 时不能继续启动 | P0 保持 |
| Task-loop closed repair loop | `./task-loop run`、verify fail retry、summary、progress、lock | 已有 | 已实现 copy -> verify -> retry -> PASS -> checkpoint | 不补主结构 | 支撑长队列静默推进 | checkpoint 失败后不得继续下一 task | P0 保持 |
| Git checkpoint | `GIT_CHECKPOINT=commit|push|off`、git-checkpoint skill、summary evidence | 已有 | PASS task 默认本地 commit，push 显式 opt-in | 不补主结构 | 保留可回溯证据链 | dirty worktree 会挡 checkpoint，不能混入既有改动 | P0 保持 |
| Validation matrix | validation-driver、`./dev check task`、Rust/macOS/docs/prompt gates | 已有 | 已按改动路径选择最小充分验证集 | 不补主结构 | 防止每个 task 都跑过宽或过窄验证 | macOS test fallback 只适用于明确 sandbox 限制 | P0 保持 |
| Repo-local Skills | `.codex/skills-src/**`、`.agents/skills/**` | 已有 | 已有 7 个 AreaMatrix skills，且 `./dev check skills` 通过 | 继续强化内容 | 把重复治理知识固化为可复用视角 | skill 语义变更先同步 `.ai-governance/` | P1 持续 |
| OpenAI Docs MCP | `openaiDeveloperDocs` MCP 已启用 | 部分已有 | 工具已启用，但使用规则还未成为所有 OpenAI/Codex 判断的硬习惯 | 建议补规则 | 涉及 OpenAI/Codex/API/model 时默认先查官方 | 不把 OpenAI docs 用作 AreaMatrix 产品 SSOT | P1 |
| Context7 / DeepWiki / time MCP | `context7`、`mcp-deepwiki`、`mcp-server-time` | 部分已有 | 工具已启用，但按场景选用的规则还可更清晰 | 建议补轻规则 | 第三方库、外部 repo、时间查询不靠记忆 | 外部资料不能覆盖本仓库 docs | P2 |
| Browser Use | Browser plugin、in-app browser feature | 部分已有 | 能力启用，但 AreaMatrix 是 macOS 原生 app，不是主验收面 | 不急补 | 用于 docs preview、localhost、file URL 验证 | 不替代 macOS app 测试 | P3 |
| Chrome | Chrome plugin、chrome-devtools MCP | 部分已有 | 能力启用，适合登录态或真实 Chrome profile | 暂不制度化 | 需要 cookies、扩展或远程认证时可用 | 不处理敏感账号/支付自动化 | P3 |
| Computer Use | computer-use plugin / MCP 已启用 | 部分已有 | 能力启用，但尚未纳入 macOS UI 验收 runbook | 建议补 | 为 SwiftUI 页面和交互提供真实 UI smoke 证据 | 不替代 `xcodebuild`；密码、权限、隐私需人工确认 | P1 |
| Hooks | Codex hooks feature enabled；AreaMatrix 无 repo-local `.codex/hooks.json` | 缺失-建议补 | 当前靠人工记忆检查 live runner、dirty worktree、危险路径 | 建议补 warn-only / read-only hooks | 在 session start / pre-tool 提醒重复 runner、checkpoint 风险、危险边界 | hooks 是 guardrail，不是完整 enforcement boundary；不自动修改文件，不 block / deny / continue | P1 |
| Plugin hooks | `plugin_hooks` disabled / under development | 暂不接入 | 官方和本机都显示仍在开发中 | 不补 | 等成熟后再评估 | 不依赖其做关键门禁 | P4 |
| Subagents | Codex multi-agent feature enabled；已有边界 runbook | 已有边界 | 可用于读/审计/验证；并行写必须有 owner 和 disjoint write set | 不补主结构 | 加速大范围只读审计、日志归因、分模块验证 | 不碰 live runner / progress / checkpoint；不把同一 live task 拆给多个 writer | P2 |
| Automations | Codex app automations 官方存在；项目用 `./task-loop` | Trigger-based only | 官方 automations 是后台无人值守，local mode 可能修改正在编辑的文件；v1 live queue 已有稳定 runner | 不补主线 | 未来可做提醒、周期性只读检查或状态汇报候选 | 不写 repo state；不创建第二套进度源；不替代 `./task-loop` | P4 |
| Codex Cloud | `codex cloud` CLI 存在；AreaMatrix 当前本地 live runner | 暂缓 | Cloud 会改变执行环境，需要 local env、凭证、隐私、网络、diff apply 和 checkpoint 方案 | 暂不接 | 未来可做隔离 review / PR 实验 | 不作为 canonical runtime；不绕过 `workflow/` gate 和 local validation | P4 |
| Worktrees | 官方存在；AreaMatrix 直接跑当前 checkout | 暂缓 | Worktree 只能隔离文件变更，不能定义 AreaMatrix task 语义；并行会放大状态复杂度 | 暂不接 | 未来可隔离 vN 规划、spike 或独立并行任务 | 不作为 live queue 默认执行环境；不抢占 live task label | P4 |
| Local Environments | 官方存在；AreaMatrix 用本机 dev tools | 仅记录 | 当前项目依赖 macOS/Xcode、本机状态和 task-loop | 不补 | 未来 Cloud/remote 执行前再设计 | 不把环境初始化写成破坏性脚本 | P4 |
| GitHub Action | 官方存在；项目已有本地 `./dev check ...` 和 CI 治理 | 暂不接入 | 当前主要问题是 live queue 收口，不是 GitHub 触发 Codex | 暂不接 | 未来用于 PR review / repair bot | 不让 GitHub Action 修改 live progress | P4 |
| IDE Extension / Web | 官方存在；项目主路径是 Codex app / CLI / local runner | 仅记录 | 对当前自动闭环不是必要入口 | 不补 | 作为个人使用入口即可 | 不作为验收证据源 | P4 |
| Slack / Linear integrations | 官方存在；项目未使用 | 仅记录 | 与当前本地开发闭环无直接关系 | 不补 | 未来团队协作时再接 | 不把外部 issue 状态当 task truth | P5 |
| Codex SDK / app-server / remote-control / exec-server | 官方/CLI 存在，多为实验或嵌入能力 | 仅记录 | 当前不需要自己嵌入 Codex runtime | 不补 | 未来平台化 `./dev` 或外部 dashboard 时再评估 | 不接入 v1 live runner 主线 | P5 |
| Security / administration / access tokens | 官方存在；项目不保存凭证 | 部分已有 | 本机 config 有 auth/MCP，但仓库规则禁止存密钥 | 只补提醒 | 明确凭证不进 repo，不在 `.codex/` 写 token | 任何远程/企业配置先确认 | P2 |
| Changelog / Feature Maturity | 官方存在；文档已列入口 | 部分已有 | 已记录要查，但尚无固定刷新节奏 | 建议补轻流程 | 每次声称“最新”前打开官方目录核对 | 不把旧记忆当最新事实 | P2 |
| Image generation | feature enabled，项目当前非视觉资产主线 | 仅记录 | AreaMatrix 当前以原生 UI 和 docs 为主 | 不补 | 未来需要营销/图示/bitmap asset 时再用 | 不替代 UI 实现或截图验证 | P5 |
| Documents / Spreadsheets / Presentations plugins | 已启用 | 仅记录 | 对当前代码任务不是主线 | 不补 | 需要交付办公文档时可用 | 不生成低价值报告文件 | P5 |
| LaTeX / Tectonic plugin | bundled marketplace 存在但未启用 | 仅记录 | 当前没有 LaTeX 工作负载 | 不补 | 未来排版需求再启用 | 不为无需求开启插件 | P5 |

### 优先级建议

| 优先级 | 建议动作 | 为什么现在做 | 不做会怎样 |
|---|---|---|---|
| P0 | 保护当前 `./task-loop` 主线，不启动第二 runner | 当前已有 live lock，且 dirty worktree 会挡 checkpoint | 状态源冲突，可能让 PASS task 无法 checkpoint |
| P1 | 增加 repo-local warn-only / read-only hooks guardrail | 当前依赖人工记住 runner / dirty worktree / 危险路径边界 | 容易重复启动、误碰高风险路径或错过 checkpoint 风险 |
| P1 | 制定 Computer Use macOS UI smoke runbook | Phase 2/4 页面任务需要真实 UI 证据 | 验收仍偏命令层，缺少交互和窗口状态证据 |
| P1 | 固化 OpenAI Docs MCP 使用规则 | 官方 Codex / model / API 更新快 | 容易用过期记忆判断“最新” |
| P2 | 定义 Subagent 使用边界 | 大范围审计可以并行，但写入冲突风险高 | 并行 agent 可能互相覆盖或重复工作 |
| P2 | 增加 Changelog / Feature Maturity 刷新流程 | Codex 能力变化快 | 文档会逐渐落后官网 |
| P4 | 暂缓 Automations / Cloud / Worktrees / GitHub Action 接主线 | v1 live queue 仍在跑，本地 runner 已能闭环 | 过早接入会多一个状态系统；Automations 仅允许非写入提醒 / 检查 / 汇报候选 |
| P5 | 暂缓 SDK / app-server / remote-control / Slack / Linear | 当前不是平台化 Codex runtime 的阶段 | 增加复杂度但不提高当前验收质量 |

### 短期任务清单

短期优化记录在 [../../tasks/backlog/codex-native-area-vibe-optimization.md](../../tasks/backlog/codex-native-area-vibe-optimization.md)。该 backlog 不是 `tasks/prompts/**` live queue，不由 `./task-loop` 自动执行。

| 优先级 | 工作包 | 要做什么 | 吸收来源 | 交付物 | 完成口径 |
|---|---|---|---|---|---|
| P0 | 主线保护 | 明确当前 `./dev + ./task-loop + tasks/prompts/**` 仍是唯一 live execution 主线 | Codex 官方 workflow / AreaMatrix 当前体系 | 文档规则和 backlog 任务边界 | 不新增第二 runner，不让 Vibe/Codex Automations/Cloud 接管 live queue |
| P0 | 外部能力接入门禁 | 定义 Vibe-Skills 或其他外部 skills 的 admission gate | Vibe-Skills custom skill governance、Codex migrate/customization docs | [外部能力接入门禁](../../.ai-governance/workflows/external-capability-admission.md) | 目录存在不等于启用；外部 runtime 不得成为 AreaMatrix canonical runtime；必须说明 source of truth、触发条件、验证和 owner |
| P1 | OpenAI Docs MCP 规则 | 固化“涉及 OpenAI/Codex/API/model 最新判断时优先查官方 MCP” | Codex 官方 docs、openaiDeveloperDocs MCP | `.ai-governance` 或 `.codex/references` 规则补充 | 以后不靠旧记忆声称最新 |
| P1 | repo-local warn-only / read-only hooks | 设计只读 hooks guardrail，先提示 live runner、dirty worktree、危险路径和验证缺口 | Codex hooks | [hooks guardrail runbook](hooks-guardrail-runbook.md)；未来再评估 `.codex/hooks.json` | hooks 只提醒或补充上下文，不自动修改文件，不 block / deny / continue |
| P1 | Computer Use UI smoke | 为 macOS SwiftUI 任务补真实 UI smoke 路径 | Codex Computer Use | [Computer Use macOS UI smoke runbook](computer-use-macos-ui-smoke-runbook.md) | UI 任务除命令验证外有窗口、点击、截图或操作证据 |
| P1 | AreaMatrix skills 强化 | 强化现有 7 个 repo-local skills 的触发和边界 | AreaMatrix 当前 skills | skills-src / index / validation matrix 的小步补强 | 不新增重复 skill；先复用现有 skill owner |
| P2 | Subagent 边界 | 定义并行 agent 的使用边界、ownership 和禁止区 | Codex Subagents、Vibe subagent patterns | [subagent boundaries runbook](subagent-boundaries-runbook.md) / `.ai-governance` 规则 | 只读审计可并行；写入必须拆分 disjoint write set |
| P2 | Vibe-Skills 横向能力筛选 | 从 Vibe-Skills 中筛选调试、TDD、验证、审查、安全、架构、文档类能力 | Vibe-Skills bundled skills | 候选吸收矩阵 | 每个候选标注吸收/不吸收/参考、原因和落点 |
| P2 | 官方变更刷新 | 建立 Codex changelog / feature maturity 的刷新习惯 | Codex Releases / Feature Maturity | 轻量刷新步骤 | 每次更新“最新 Codex 工作流”前重新打开官方文档 |
| P3 | Browser / Chrome 场景化 | 只为 docs preview、localhost、登录态网页建立使用边界 | Codex Browser / Chrome plugin | 场景说明 | 不把 Browser/Chrome 当 macOS app 主验收 |
| P4 | Automations / Cloud / Worktrees gate | 暂缓接入主线，只记录未来评估条件和禁写边界 | Codex Automations / Cloud / Worktrees | [Automations / Cloud / Worktrees gate](codex-automations-cloud-worktrees-gate.md) | v1 live queue 完成前不新增状态源；三者先过 external admission |
| P5 | SDK / app-server / remote-control | 仅记录，不进入近期实现 | Codex SDK / app-server / remote-control | 无近期交付 | 等需要平台化 Codex runtime 时再设计 |

### Vibe-Skills 吸收原则

`/Users/as/Ai-Project/project/Vibe-Skills` 当前定位为外部候选能力池和治理参考，不是 AreaMatrix 的 canonical runtime。AreaMatrix 不直接启用 `vibe` 接管主流程，也不把 Vibe-Skills 的目录结构原样并入 `tasks/prompts/**`。具体判断以 [.ai-governance 外部能力接入门禁](../../.ai-governance/workflows/external-capability-admission.md) 为准。

| 结论 | 适用条件 | AreaMatrix 落点 |
|---|---|---|
| 吸收 | 能补明确缺口、不重复现有 owner、可验证、不改变 live 主线 | `.ai-governance/**`、`.codex/references/**`、`.codex/skills-src/**` 或经批准的 `workflow/**` |
| 暂缓 | 有潜在价值，但 owner、触发、验证或安全边界未闭合 | `tasks/backlog/**` 候选记录 |
| 只参考 | 主要提供 wording、taxonomy、case、checklist 或上游设计启发 | `.codex/references/**` 或 backlog note |
| 拒绝 | 与主线冲突、重复率过高、需要第二 runtime / supervisor、无法说明 source of truth 或危及用户文件安全 | 可在 backlog 记录拒绝原因，但不安装、不链接、不触发 |

## 推荐演进方向

短期：

- 保持 AreaMatrix 当前 `./dev + ./task-loop + repo-local skills` 结构。
- 不把 `workflow/` 直接写入 live `tasks/prompts/**`。
- 将 Computer Use 作为 macOS UI smoke 的补充证据。
- 使用 OpenAI Docs MCP 查最新 Codex / model / API 文档。

中期：

- 给 AreaMatrix 增加 repo-local hooks，但先只做 warn-only / read-only 提示和安全检查。
- 为 macOS UI task 增加 Computer Use 验收 runbook。
- 将常用 task-loop 操作固化为更明确的 `./dev` guide。
- 继续让 repo-local skills 承担治理知识，避免把规则散落在 prompt 里。

高风险边界：

- 不用 hooks 自动修改用户文件。
- 不用 hooks 自动启动/停止 runner、控制 Git、block / deny / continue 或替代 verify-ready。
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
