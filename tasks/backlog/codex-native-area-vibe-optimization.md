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

## Next Roadmap Decision

本节是 closeout 后的路线判断记录，不是 live task approval，不进入 `tasks/prompts/**`，也不授权 hooks、Automations、Cloud、Worktrees、Vibe-Skills、Browser / Chrome、Computer Use 或 subagents 接管 AreaMatrix 主线。

### Baseline 判断

- 当前 Codex / AreaMatrix 工作层可以视为稳定基线：inventory 已明确 source of truth、execution、state、skill owner 分层；backlog 和 playbook 只做 planning / 操作投影；本轮边界扫描未发现 diff 触碰 live queue、产品代码、workflow version 或 task-loop runtime state。
- 默认路线应回到 AreaMatrix 产品主线开发，继续使用 `docs/** -> workflow/ planning gate -> tasks/prompts/** -> ./dev / ./task-loop -> repo-local skills`。
- 若后续发现 source-of-truth、execution、state 或 skill owner 污染，路线第一项立即改为污染修复；在 blocker 清零前，不再宣称稳定基线。
- 后续任何外部能力都必须先通过 [外部能力接入门禁](../../.ai-governance/workflows/external-capability-admission.md)，并形成缺口、去重、source of truth、触发条件、live 主线影响、用户文件 / 隐私影响、验证、owner / landing 和结论记录。

### 路线表

| 分类 | 项 | 路线判断 | 触发条件 | 门禁 |
|---|---|---|---|---|
| Recommended now | AreaMatrix 产品主线 | 回到已批准的产品实现、验收和 task-loop 主线 | closeout 无 blocker；live queue / progress / checkpoint 未被外部层污染 | 继续按 `tasks/prompts/**` task / manifest、verify-ready、`./dev check ...` 和 Git checkpoint 证据执行 |
| Recommended now | 当前 Codex / AreaMatrix 工作层 | 作为稳定基线保留 | 日常开发、验收、失败归因、规划 handoff | `.ai-governance/**` 仍是治理源事实；`.codex/**` 只做操作投影；backlog 不执行 |
| Recommended now | Browser / Chrome | 只作为场景化验证工具，不作为主线能力改造 | Browser：localhost / file URL / 本地 web 预览；Chrome：需要用户 profile、cookies、扩展或远程登录态 | 不替代命令门禁；不处理账号、安全、支付、隐私或不可逆设置；必要时单项 admission |
| Trigger-based only | Computer Use | 仅用于 macOS SwiftUI UI smoke 补证 | 任务需要真实窗口、点击、输入、菜单、sheet、alert、截图或 GUI-only bug 复现 | 先跑命令门禁；使用 fixture / QA repo；不点击系统权限、密码、隐私授权或真实用户文件破坏性确认 |
| Trigger-based only | subagents | explicit-only，并行协作工具 | 用户或任务明确要求 subagents / parallel agent work；只读探索问题独立，或写入有 disjoint write set | 遵守 subagent boundaries；不写 progress、logs、run summaries、checkpoint；主 agent 复核和最终验证 |
| Trigger-based only | Vibe professional skills | 单项、具体任务触发 | 出现科研、金融、法律、图像、视频、ML、数据库、云平台等明确专业任务，且现有 repo-local skill 无法覆盖 | 逐项 admission；只吸收方法价值或参考；不安装全量 Vibe-Skills，不启用 Vibe runtime |
| Defer | hooks | 暂缓真实启用，仅保留 runbook | 重复 runner、dirty checkpoint、高风险路径、完成前缺验证等明显风险需要 repo-local guardrail | 只读脚本、人工 `/hooks` review / trust、dry check；不得写文件、启动/停止 runner、commit、push、reset、clean 或 stash |
| Defer | Automations | 暂不创建 | 需要周期性、线程外、可恢复的非 live-queue 观察任务，且不会替代 `./task-loop` | automation prompt 与 live queue 解耦；不得写 progress / checkpoint；先 admission 和人工确认 |
| Defer | Cloud | 暂不接入 AreaMatrix 主线 | 需要远端隔离执行、review 或云端协作，且本地 runner 不适合 | local env、凭证、隐私、用户文件边界、diff apply 和 checkpoint 方案通过 admission；不得成为 canonical runtime |
| Defer | Worktrees | 暂不作为默认执行方式 | 需要隔离大改、并行版本或实验分支，且当前 checkout 风险过高 | 明确 worktree owner、同步/回收、checkpoint、冲突解决和 forbidden paths；不绕过 workflow planning gate |
| Reject / do not adopt | Vibe runtime / VCO / `.vibeskills/**` / memory plane / specialist router | 不进入 AreaMatrix 默认主线 | 无默认触发 | 需要第二 runtime、source-of-truth 或 state surface 的方案直接拒绝 |
| Reject / do not adopt | 第二套 runner / progress / queue / checkpoint / promotion | 不采用 | 无默认触发 | 与 `./dev + ./task-loop + tasks/prompts/**` 主线冲突，直接拒绝 |
| Reject / do not adopt | 用 backlog roadmap 批准 live task | 不采用 | 无默认触发 | roadmap 只能记录决策；真正执行仍需已批准 task、workflow promotion 或人工明确任务 |

### 后续优先级

1. 产品主线优先：继续推进 AreaMatrix v1 live queue 或已批准产品任务。
2. 只在任务触发时使用 Browser / Chrome、Computer Use 和 subagents 补证或并行分析。
3. hooks、Automations、Cloud、Worktrees 维持 deferred，等真实痛点出现后单项 admission。
4. Vibe professional skills 维持 trigger-based only；没有具体专业任务时不继续吸收。
5. 拒绝任何会创建第二 runtime、第二 state surface 或绕过 AreaMatrix source of truth 的方案。

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

## P2.3: Writing Plans / Planning Handoff 吸收记录

- Upstream source: `/Users/as/Ai-Project/project/Vibe-Skills/bundled/skills/writing-plans/SKILL.md` 或 `core/skills/writing-plans/instruction.md`。
- AreaMatrix gap: planning / backlog prompt 需要更稳定地写出目标、非目标、精确路径、source of truth、owner / landing、执行顺序、验证命令和 blocked / rollback 口径。
- Dedup with: 不新增 `writing-plans` 同义 repo-local skill；owner 是 `.codex/skills-src/areamatrix-workflow-planning/SKILL.md`。
- Local source of truth: `workflow/**` lifecycle 与 `tasks/backlog/**` backlog 边界；产品语义仍以 `docs/**` 为准。
- Live mainline impact: 无。backlog prompt 不进入 `tasks/prompts/**`，不写 `tasks/prompts/_shared/progress.json`，不创建 checkpoint 或 runner state。
- Landing: `.codex/references/planning-handoff-runbook.md`、`workflow/templates/**`、`.codex/skills-src/areamatrix-workflow-planning/**`、`tasks/backlog/**` prompt 包说明。
- Verification: `./dev check skills`、`./dev check governance`、prompt doctor、`./dev workflow doctor`、路径级 diff check。
- Decision: 吸收 handoff-safe planning 字段和 copy-ready / verify-ready 分离方法；拒绝 Vibe 的 dedicated worktree、执行 skill handoff、自动 commit 或外部 runtime 语义。

| 优先级 | 项 | 当前处理 |
|---|---|---|
| P3 | Browser / Chrome 场景化 | 只记录使用边界，不作为 macOS app 主验收 |
| P4 | Automations / Cloud / Worktrees / GitHub Action | v1 live queue 完成前不接入主线 |
| P5 | SDK / app-server / remote-control / Slack / Linear | 仅记录，等平台化需求明确后再设计 |

## Prompt 包

可执行提示词放在 [prompts/codex-native-area-vibe-optimization/](prompts/codex-native-area-vibe-optimization/)。

该 prompt 包只供新对话手工复制使用，不接入 `tasks/prompts/**`，不由 `./task-loop` 自动执行。

第二批能力吸收提示词放在 [prompts/vibe-skills-absorption/](prompts/vibe-skills-absorption/)，用于把已筛选出的横向能力继续转成 AreaMatrix 自有 runbook、checklist 或 repo-local skill 补强。

第三批 backlog 工具化提示词放在 [prompts/dev-backlog-tooling/](prompts/dev-backlog-tooling/)，用于实现只读的 `./dev backlog list/show` 浏览入口。该工具只能打印 backlog prompt package，不执行 prompt，不写 live queue、progress、runner state 或 checkpoint。

第四批总收口提示词放在 [prompts/codex-operating-layer-closeout/](prompts/codex-operating-layer-closeout/)，用于盘点现有工作层、回归核对 source-of-truth / execution / state / skill owner 边界、沉淀短操作手册，并给出下一阶段路线。该 prompt 包不新增能力，不直接进入产品实现或 live queue。

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
