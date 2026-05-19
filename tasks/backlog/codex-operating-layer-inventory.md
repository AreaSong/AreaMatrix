# Codex Operating Layer Inventory

本 inventory 只盘点 AreaMatrix / Codex 工作层现状，不新增能力，不进入 `tasks/prompts/**` live queue。

## 基线结论

- 产品、架构、API、UX 和开发规范仍以 `docs/**` 为源事实。
- AI 协作、风险边界和完成门禁仍以 `.ai-governance/**` 为源事实。
- `.codex/**` 只承载 Codex 运行材料、runbook、checklist 和 repo-local skill 文本，不是产品语义源事实。
- `tasks/backlog/**` 是 planning / backlog 层，不由 `./task-loop` 扫描、执行、重试、验收或写 progress。
- `/Users/as/Ai-Project/project/Vibe-Skills/**` 是候选能力池和治理参考，不是 AreaMatrix canonical runtime。
- 当前 live mainline 仍是 `AGENTS.md / .ai-governance -> workflow/ planning gate -> tasks/prompts/** -> ./dev / ./task-loop -> repo-local skills`。

## Governance Rules

| 能力 | Source of truth | Owner | 状态 | 是否影响 live mainline |
|---|---|---|---|---|
| AI governance index | `.ai-governance/README.md` | `areamatrix-enterprise-governance` | 已吸收，治理源事实入口 | 是；定义主线保护和源事实层级 |
| Agent principles | `.ai-governance/core/agent-principles.md` | `areamatrix-validation-driver` | 已吸收，协作 / 调试 / 完成门禁规则 | 是；影响验证、完成声明和失败归因 |
| Project rules | `.ai-governance/project/areamatrix-rules.md` | `areamatrix-file-safety` | 已吸收，项目不变量和高风险边界 | 是；影响用户文件、DB、Core API 等高风险任务 |
| Prompt task runtime | `.ai-governance/workflows/prompt-task-runtime.md` | `areamatrix-task-loop` | 已吸收，copy-ready / verify-ready / task-loop 规则 | 是；定义 live queue 执行和验收语义 |
| External capability admission | `.ai-governance/workflows/external-capability-admission.md` | `areamatrix-workflow-planning` | 已吸收，外部能力接入门禁 | 是；阻止外部能力绕过主线 |
| Subagent boundaries | `.ai-governance/workflows/subagent-boundaries.md` | `areamatrix-workflow-planning` | 已吸收，subagent 使用边界 | 否；只在明确授权时参与，不接管 runner / state |

## Codex References

| 能力 | Source of truth | Owner | 状态 | 是否影响 live mainline |
|---|---|---|---|---|
| Codex workflow and tools map | `.codex/references/codex-workflow-and-tools.md`，受 `.ai-governance/**` 约束 | `areamatrix-workflow-planning` | 已吸收，Codex 官方能力映射 | 否；只说明运行材料落点 |
| Completion evidence checklist | `.codex/references/completion-evidence-checklist.md`，受 `.ai-governance/core/agent-principles.md` 约束 | `areamatrix-validation-driver` | 已吸收 `verification-before-completion` 方法 | 是；影响完成声明证据，不写 state |
| Debugging / failure attribution runbook | `.codex/references/debugging-failure-attribution-runbook.md`，受 `.ai-governance/core/agent-principles.md` 约束 | `areamatrix-validation-driver` | 已吸收 `systematic-debugging` 方法 | 是；影响失败归因，不直接写 live queue |
| Planning handoff runbook | `.codex/references/planning-handoff-runbook.md`，受 `workflow/**` 和 `tasks/backlog/**` 约束 | `areamatrix-workflow-planning` | 已吸收 `writing-plans` 方法 | 否；只服务 planning / backlog |
| Review and threat model runbook | `.codex/references/review-and-threat-model-runbook.md`，受 `CODE_REVIEW.md`、`SECURITY.md` 和 `.ai-governance/**` 约束 | `areamatrix-enterprise-governance` | 已吸收 `code-reviewer` / `security-threat-model` 方法 | 是；影响 review / security gate，不写 runner state |
| Hooks guardrail runbook | `.codex/references/hooks-guardrail-runbook.md`，受 `.ai-governance/workflows/prompt-task-runtime.md` 约束 | `areamatrix-enterprise-governance` | 已吸收为 runbook；未启用 repo hook | 否；不得替代 verify / CI / checkpoint |
| Subagent boundaries runbook | `.codex/references/subagent-boundaries-runbook.md`，受 `.ai-governance/workflows/subagent-boundaries.md` 约束 | `areamatrix-workflow-planning` | 已吸收 OpenAI subagent 规则；Vibe taxonomy 只参考 | 否；explicit-only，不接管主线 |
| Computer Use macOS UI smoke runbook | `.codex/references/computer-use-macos-ui-smoke-runbook.md`，受 docs / validation gate 约束 | `areamatrix-validation-driver` | 已吸收为 UI smoke 补证方法 | 否；只补 UI 证据，不替代命令门禁 |
| Browser / Chrome / Computer Use UI evidence templates | `.codex/references/ui-evidence-tool-templates.md`，受 validation / file-safety gate 约束 | `areamatrix-validation-driver` + `areamatrix-file-safety` | 已吸收为 UI / GUI / web 补证模板 | 否；不启动 UI 自动化，不替代命令门禁，不保存真实用户数据或截图 |
| Vibe-Skills capability screening | `.codex/references/vibe-skills-capability-screening.md`，受 admission gate 约束 | `areamatrix-workflow-planning` | 候选筛选记录；部分方法已吸收 | 否；Vibe runtime 不进入主线 |
| Codex references index | `.codex/references/index.md` | `areamatrix-doc-sync` | 导航索引 | 否；只提升可发现性 |

## Repo-local Skills

| Skill | Source of truth | Owner | 状态 | 是否影响 live mainline |
|---|---|---|---|---|
| `areamatrix-task-loop` | `.codex/skills-src/areamatrix-task-loop/SKILL.md` | `areamatrix-task-loop` | 已启用 repo-local skill | 是；负责 runner / progress / logs / recovery |
| `areamatrix-git-checkpoint` | `.codex/skills-src/areamatrix-git-checkpoint/SKILL.md` | `areamatrix-git-checkpoint` | 已启用 repo-local skill | 是；只在 verify PASS 后处理 Git checkpoint |
| `areamatrix-validation-driver` | `.codex/skills-src/areamatrix-validation-driver/SKILL.md` | `areamatrix-validation-driver` | 已启用 repo-local skill | 是；定义最小充分验证和报告格式 |
| `areamatrix-doc-sync` | `.codex/skills-src/areamatrix-doc-sync/SKILL.md` | `areamatrix-doc-sync` | 已启用 repo-local skill | 是；检查 docs / API / UDL / prompt / Codex 材料漂移 |
| `areamatrix-file-safety` | `.codex/skills-src/areamatrix-file-safety/SKILL.md` | `areamatrix-file-safety` | 已启用 repo-local skill | 是；守住用户文件、DB、staging、sync 高风险边界 |
| `areamatrix-workflow-planning` | `.codex/skills-src/areamatrix-workflow-planning/SKILL.md` | `areamatrix-workflow-planning` | 已启用 repo-local skill | 否；只管理 workflow / backlog / promotion 前门禁 |
| `areamatrix-enterprise-governance` | `.codex/skills-src/areamatrix-enterprise-governance/SKILL.md` | `areamatrix-enterprise-governance` | 已启用 repo-local skill | 是；影响 review / security / dependency / CI gate |

`.agents/skills/areamatrix-*` 只是发现入口；维护源事实仍在 `.codex/skills-src/**`。

## Backlog Prompt Packages

| Package | Source of truth | Owner | 状态 | 是否影响 live mainline |
|---|---|---|---|---|
| `codex-native-area-vibe-optimization` | `tasks/backlog/prompts/codex-native-area-vibe-optimization/README.md` | `areamatrix-workflow-planning` | 8 个 copy / verify prompt；P0-P2 多数已吸收，P3-P5 暂缓 | 否；backlog planning |
| `vibe-skills-absorption` | `tasks/backlog/prompts/vibe-skills-absorption/README.md` | `areamatrix-workflow-planning` | 4 个 copy / verify prompt；只吸收方法价值 | 否；不安装、不启用 Vibe-Skills |
| `dev-backlog-tooling` | `tasks/backlog/prompts/dev-backlog-tooling/README.md` | `areamatrix-workflow-planning` | 4 个 copy / verify prompt；`./dev backlog list/show` 已可用 | 否；只读浏览 |
| `codex-operating-layer-closeout` | `tasks/backlog/prompts/codex-operating-layer-closeout/README.md` | `areamatrix-workflow-planning` | 4 个 copy / verify prompt；当前 closeout 包 | 否；总收口检查，不进入 live queue |

## `./dev backlog` Status

| 能力 | Source of truth | Owner | 状态 | 是否影响 live mainline |
|---|---|---|---|---|
| `./dev backlog list` | `scripts/dev_tools/backlog.py` + `tasks/backlog/README.md` | `areamatrix-workflow-planning` | 已成为只读浏览入口；列出 package slug、title、task 数 | 否；只读打印 backlog package |
| `./dev backlog show <package>` | `scripts/dev_tools/backlog.py` + package README | `areamatrix-workflow-planning` | 已成为只读浏览入口；打印 README 和 task index | 否；不执行 prompt |
| `./dev backlog show <package> --task N --mode copy|verify` | `scripts/dev_tools/backlog.py` + package prompt 文件 | `areamatrix-workflow-planning` | 已成为只读浏览入口；打印指定 prompt 内容 | 否；不写 `tasks/prompts/**`、progress、logs 或 checkpoint |
| Console passthrough | `scripts/task_loop/actions.py` + `scripts/dev_tools/cli.py` | `areamatrix-task-loop` | 已接入 action registry passthrough | 否；控制台只负责可发现性和透传 |

## Absorbed / Candidate / Deferred

| 能力来源 | 当前结论 | 落点 | Live mainline 影响 |
|---|---|---|---|
| OpenAI Docs MCP / official docs rule | 已吸收 | `.ai-governance/core/agent-principles.md`、`.codex/references/codex-workflow-and-tools.md` | 只影响 OpenAI / Codex 信息核对 |
| Hooks | 已吸收为 runbook，未启用 hook | `.codex/references/hooks-guardrail-runbook.md` | 无；不得替代验收 |
| Computer Use | 已吸收为 macOS UI smoke 补证 | `.codex/references/computer-use-macos-ui-smoke-runbook.md` | 无；只补 UI 证据 |
| Browser / Chrome / Computer Use templates | 已吸收为 UI / GUI / web 补证模板 | `.codex/references/ui-evidence-tool-templates.md` | 无；不替代命令门禁，不进入默认主线 |
| Subagents | 已吸收 explicit-only / write-set 边界 | `.ai-governance/workflows/subagent-boundaries.md`、`.codex/references/subagent-boundaries-runbook.md` | 无；不接管 runner / progress / checkpoint |
| `systematic-debugging` | 已吸收方法价值 | `.codex/references/debugging-failure-attribution-runbook.md` | 影响失败归因纪律 |
| `verification-before-completion` | 已吸收方法价值 | `.codex/references/completion-evidence-checklist.md` | 影响完成声明纪律 |
| `code-reviewer` / `security-threat-model` | 已吸收方法价值 | `.codex/references/review-and-threat-model-runbook.md`、repo-local owner skill | 影响 review / security gate |
| `writing-plans` | 已吸收方法价值 | `.codex/references/planning-handoff-runbook.md`、`areamatrix-workflow-planning` | 无；只服务 planning / backlog |
| `tdd-guide`、`architecture-patterns`、`docs-review` | 只参考 | `.codex/references/vibe-skills-capability-screening.md` | 无 |
| Vibe-Skills professional vertical skills | 暂缓 | `tasks/backlog/**` 或后续 admission record | 无；具体任务明确需要时单项评估 |
| Vibe runtime / VCO / `.vibeskills/**` / memory plane / specialist router | 拒绝进入默认主线 | 筛选记录 | 无；不安装、不启用、不触发 |
| Automations / Cloud / Worktrees / GitHub Action | 暂缓 | `tasks/backlog/codex-native-area-vibe-optimization.md` | 无；v1 live queue 完成前不接主线 |
| SDK / app-server / remote-control / Slack / Linear | 暂缓 | `tasks/backlog/codex-native-area-vibe-optimization.md` | 无；平台化需求明确后再设计 |

## Inventory Gaps

- 已补充本 inventory 的导航入口；未发现需要修改 `tasks/prompts/**` 才能成立的 inventory gap。
- 本文件不证明后续 boundary regression 已通过；边界污染回归由 `codex-operating-layer-closeout` 的后续 prompt 继续验收。
