# Codex Native / AreaMatrix / Vibe-Skills 长期优化任务

## 定位

本任务记录近期要做的系统层优化。它不是 `tasks/prompts/**` live queue 的一部分，不由 `./task-loop` 自动执行。

核心方向：

```text
Codex 官方原生能力做底座
-> AreaMatrix 当前体系做主线
-> Vibe-Skills 做候选能力池
-> 通过 admission gate 选择性吸收
```

## 背景

- AreaMatrix 当前主线是 `AGENTS.md`、`.ai-governance/`、`workflow/`、`tasks/prompts/**`、`./dev`、`./task-loop` 和 `.codex/skills-src/**`。
- Codex 官方能力包括 rules、hooks、skills、plugins、MCP、Computer Use、Browser、subagents、`codex exec`、Automations、Cloud、Worktrees 等。
- `/Users/as/Ai-Project/project/Vibe-Skills` 是外部 “通用 AI 工作台 + 专业领域 skill 仓库”，可作为候选能力池和治理参考。
- 当前不允许让 Vibe-Skills、Codex Automations、Cloud、Worktrees 或其他外部 runtime 接管 AreaMatrix live queue。

## P0: 主线保护与接入门禁

| 项 | 内容 | 交付物 | 完成标准 |
|---|---|---|---|
| P0.1 | 明确 `./dev + ./task-loop + tasks/prompts/**` 是唯一 live execution 主线 | `.codex/references/codex-workflow-and-tools.md` 记录 | 不新增第二 runner，不修改 live queue 边界 |
| P0.2 | 为外部 skills / workflow 建 admission gate | [`.ai-governance/workflows/external-capability-admission.md`](../../.ai-governance/workflows/external-capability-admission.md) | 每个候选必须说明 source of truth、触发条件、验证方式、owner、是否影响主线，并给出吸收、暂缓、只参考或拒绝结论 |
| P0.3 | 明确 Vibe-Skills 只能先作为候选能力池 | Vibe-Skills 吸收原则 | 不直接安装全量 skills，不让 `vibe` 成为 AreaMatrix canonical runtime |

## P1: Codex 官方原生能力吸收

| 项 | 内容 | 候选落点 | 完成标准 |
|---|---|---|---|
| P1.1 | 固化 OpenAI Docs MCP 使用规则 | `.ai-governance/core/agent-principles.md` + `.codex/references/codex-workflow-and-tools.md` | 涉及 OpenAI/Codex/API/model 最新判断时，默认先查官方 MCP 或官方域名；OpenAI docs 只裁定运行层，不替代 AreaMatrix 产品 `docs/**` |
| P1.2 | 设计 repo-local 只读 hooks guardrail | [`.codex/references/hooks-guardrail-runbook.md`](../../.codex/references/hooks-guardrail-runbook.md)；暂不新增 `.codex/hooks.json` | hooks 是 guardrail，不是完整验收系统；只提醒或阻断明显风险；不自动修改文件、启动/停止 runner、提交或推送 |
| P1.3 | 建立 Computer Use macOS UI smoke runbook | [`.codex/references/computer-use-macos-ui-smoke-runbook.md`](../../.codex/references/computer-use-macos-ui-smoke-runbook.md) | Computer Use 只作为 UI smoke 补证；macOS UI 任务有窗口、点击、输入、菜单、截图或状态检查证据，且不替代命令门禁 |
| P1.4 | 强化现有 AreaMatrix repo-local skills | `.codex/skills-src/**` | 不新增重复 skill；优先补现有 skill 的触发、边界和引用 |

P1.4 owner 范围：

- `areamatrix-task-loop`：live runner / progress / logs / recovery。
- `areamatrix-git-checkpoint`：PASS 后 Git checkpoint。
- `areamatrix-validation-driver`：最小充分验证。
- `areamatrix-doc-sync`：source-of-truth 与漂移检查。
- `areamatrix-file-safety`：用户文件、DB、staging、recovery、sync 高风险边界。
- `areamatrix-workflow-planning`：v* planning gate 与 live queue 之前的中间层。
- `areamatrix-enterprise-governance`：review / security / dependency / CI / ownership 治理。

不新增同义 skill；发现缺口时先补对应 owner 的触发条件、交接边界、reference 索引或验证矩阵。

## P2: 并行、刷新与 Vibe-Skills 筛选

| 项 | 内容 | 候选来源 | 完成标准 |
|---|---|---|---|
| P2.1 | 定义 subagent 使用边界 | Codex Subagents、Vibe subagent patterns | 已在 [Subagent Boundaries](../../.ai-governance/workflows/subagent-boundaries.md) 和 [subagent boundaries runbook](../../.codex/references/subagent-boundaries-runbook.md) 明确：只读审计可并行；写入必须拆分 disjoint write set；live runner / progress / checkpoint 不委派 |
| P2.2 | 筛选 Vibe-Skills 横向能力 | `systematic-debugging`、`tdd-guide`、`verification-before-completion`、`code-reviewer`、`security-threat-model`、`architecture-patterns`、`docs-review`、`writing-plans`、`subagent-driven-development` | 已新增 [Vibe-Skills 横向能力筛选矩阵](../../.codex/references/vibe-skills-capability-screening.md)；每个候选标注吸收、暂缓、只参考或拒绝，并说明原因 |
| P2.3 | 建立 Codex 官方刷新流程 | Codex changelog / feature maturity | 每次声称“最新 Codex 工作流”前重新核对官方 docs |

## P3-P5: 暂缓项

## P2.1: Subagent 边界吸收记录

- Upstream source: OpenAI Codex Subagents 官方文档；Vibe-Skills `subagent-role-taxonomy.md`。
- AreaMatrix gap: 需要明确只读并行、写入并行、owner / write set、live runner 禁区和主 agent 复核责任。
- Dedup with: 不新增同义 skill；规则落在 `.ai-governance/workflows/subagent-boundaries.md`，Codex 操作投影落在 `.codex/references/subagent-boundaries-runbook.md`。
- Local source of truth: `.ai-governance/**`，其中 subagent 具体边界以 `workflows/subagent-boundaries.md` 为准。
- Trigger condition: explicit-only；只有用户或当前任务明确要求 subagents / parallel agent work 时使用。
- Live mainline impact: 不影响 `./dev + ./task-loop + tasks/prompts/**` 主线；不得写 progress、logs、run summaries 或 checkpoint。
- User-file / privacy / remote-call impact: 默认禁止 subagent 触碰用户文件高风险边界；命中 Mission-Critical 时仍需主 agent 先确认影响、验证和回滚。
- Verification: `./dev check governance`、`./dev check skills`、prompt doctor、路径级 diff check。
- Owner / landing: `.ai-governance/workflows/subagent-boundaries.md` + `.codex/references/subagent-boundaries-runbook.md`。
- Decision: 吸收 OpenAI subagent 使用规则；Vibe taxonomy 只参考，不成为 AreaMatrix runtime。

## P2.2: Vibe-Skills 横向能力筛选记录

- Screening matrix: [`.codex/references/vibe-skills-capability-screening.md`](../../.codex/references/vibe-skills-capability-screening.md)。
- Upstream source: `/Users/as/Ai-Project/project/Vibe-Skills/README.zh.md`、`/Users/as/Ai-Project/project/Vibe-Skills/SKILL.md`、`/Users/as/Ai-Project/project/Vibe-Skills/references/skill-distillation-rules.md`，以及各候选 skill 的 `instruction.md` 或 `SKILL.md`。
- Live mainline impact: 无。`vibe` / VCO runtime、canonical-entry、`.vibeskills/**` artifacts、Vibe memory plane 和 specialist router 不进入 AreaMatrix 主线。
- Professional vertical skills: 暂不进入默认工作流；未来只有具体任务明确需要时，按 external capability admission gate 单项评估。
- Decisions:
  - `systematic-debugging`: 吸收到 `.ai-governance` / `.codex/references` 规则。
  - `tdd-guide`: 只作为参考。
  - `verification-before-completion`: 吸收到 `.ai-governance` / `.codex/references` 规则。
  - `code-reviewer`: 吸收为 AreaMatrix repo-local skill 补强。
  - `security-threat-model`: 吸收为 AreaMatrix repo-local skill 补强。
  - `architecture-patterns`: 只作为参考。
  - `docs-review`: 只作为参考。
  - `writing-plans`: 吸收为 AreaMatrix repo-local skill 补强。
  - `subagent-driven-development`: 吸收到 `.ai-governance` / `.codex/references` 规则；不吸收其默认 runtime 化执行方式。

| 优先级 | 项 | 当前处理 |
|---|---|---|
| P3 | Browser / Chrome 场景化 | 只记录使用边界，不作为 macOS app 主验收 |
| P4 | Automations / Cloud / Worktrees / GitHub Action | v1 live queue 完成前不接入主线 |
| P5 | SDK / app-server / remote-control / Slack / Linear | 仅记录，等平台化需求明确后再设计 |

## Prompt 包

可执行提示词放在 [prompts/codex-native-area-vibe-optimization/](prompts/codex-native-area-vibe-optimization/)。

该 prompt 包只供新对话手工复制使用，不接入 `tasks/prompts/**`，不由 `./task-loop` 自动执行。

## 验证

本任务当前是规划记录，修改后至少运行：

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

## 非目标

- 不修改 `tasks/prompts/**` live queue。
- 不启动第二个 `./task-loop`。
- 不安装或启用 Vibe-Skills 全量 skill 仓库。
- 不让外部 runtime 替代 AreaMatrix 的 `docs/`、`.ai-governance/`、`workflow/` 和 `tasks/prompts/**`。
