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
| P0.2 | 为外部 skills / workflow 建 admission gate | 规则表或 runbook | 每个候选必须说明 source of truth、触发条件、验证方式、owner、是否影响主线 |
| P0.3 | 明确 Vibe-Skills 只能先作为候选能力池 | Vibe-Skills 吸收原则 | 不直接安装全量 skills，不让 `vibe` 成为 AreaMatrix canonical runtime |

## P1: Codex 官方原生能力吸收

| 项 | 内容 | 候选落点 | 完成标准 |
|---|---|---|---|
| P1.1 | 固化 OpenAI Docs MCP 使用规则 | `.ai-governance/` 或 `.codex/references/` | 涉及 OpenAI/Codex/API/model 最新判断时，默认先查官方 MCP 或官方域名 |
| P1.2 | 设计 repo-local 只读 hooks guardrail | `.codex/hooks.json` 方案或 hooks runbook | 只提醒或阻断明显风险；不自动修改文件 |
| P1.3 | 建立 Computer Use macOS UI smoke runbook | `.codex/references/` 或 repo-local skill | macOS UI 任务有窗口、点击、截图或操作证据补充 |
| P1.4 | 强化现有 AreaMatrix repo-local skills | `.codex/skills-src/**` | 不新增重复 skill；优先补现有 skill 的触发、边界和引用 |

## P2: 并行、刷新与 Vibe-Skills 筛选

| 项 | 内容 | 候选来源 | 完成标准 |
|---|---|---|---|
| P2.1 | 定义 subagent 使用边界 | Codex Subagents、Vibe subagent patterns | 只读审计可并行；写入必须拆分 disjoint write set |
| P2.2 | 筛选 Vibe-Skills 横向能力 | `systematic-debugging`、`tdd-guide`、`verification-before-completion`、`code-reviewer`、`security-threat-model`、`architecture-patterns`、`docs-review`、`writing-plans` | 每个候选标注吸收、暂缓、只参考，并说明原因 |
| P2.3 | 建立 Codex 官方刷新流程 | Codex changelog / feature maturity | 每次声称“最新 Codex 工作流”前重新核对官方 docs |

## P3-P5: 暂缓项

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
git diff --check -- .codex/references/codex-workflow-and-tools.md tasks/backlog/README.md tasks/backlog/codex-native-area-vibe-optimization.md
```

## 非目标

- 不修改 `tasks/prompts/**` live queue。
- 不启动第二个 `./task-loop`。
- 不安装或启用 Vibe-Skills 全量 skill 仓库。
- 不让外部 runtime 替代 AreaMatrix 的 `docs/`、`.ai-governance/`、`workflow/` 和 `tasks/prompts/**`。
