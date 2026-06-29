# Codex Operating System

> 本文件是 AreaMatrix 的 Codex 操作层投影，不是产品、治理或 live execution 的 source of truth。
> 产品语义仍看 `docs/**`，治理边界仍看 `.ai-governance/**`，live 执行仍只从
> `workflow/versions/<version>/execution/**` 和 `./task-loop` 进入。

## 目标

Codex Operating System 的目标是把“聊天线程”变成可观测、可恢复、可验证、可收口、可归档建议化的工作系统。

核心闭环：

```text
Intake -> Register -> Context -> Preflight -> Explore -> Execute -> Recommend Validation -> Evidence -> Closeout -> Finish -> Operate
```

## 0-100% 日常流程

Codex OS 的目标不是让操作者记住更多命令，而是让任务生命周期能从固定入口自动串起来：

```bash
./dev codex-os context --task-id AM-20260629-001
./dev codex-os preflight --task-id AM-20260629-001 --strict
./dev codex-os task start --task-id AM-20260629-001 --write
./dev codex-os recommend-validation
./dev codex-os evidence --task-id AM-20260629-001 --write
./dev codex-os closeout --task-id AM-20260629-001 --write
./dev codex-os finish --task-id AM-20260629-001 --status Done --validation "<fresh result>" --evidence-file "<path>" --closeout-file "<path>" --write
```

完整生命周期：

1. Intake / New：确认 lane、risk、source of truth、允许路径、禁止路径和人工确认边界；必要时用 `new --write` 登记本机恢复入口。
2. Context / Resume：用 `context` 或 `resume` 聚合当前任务、registry、工作区 diff、推荐验证和 guardrails。
3. Preflight：检查 registry、task、handoff、验证计划、owner thread、dirty worktree、task-loop lock 和高风险确认。
4. Explore：用户已授权 subagents 时，用只读 subagents 分别审计代码、文档治理、验证和风险。
5. Plan / Execute：Quick 可直接执行；Change 先计划；Mission-Critical 先说明影响、风险、验证和回滚并等待确认。
6. Recommend Validation：按改动范围推荐最小充分验证；该命令只推荐，不自动执行。
7. Evidence / Closeout：写入本地 evidence / closeout 文件，并回填 registry 引用。
8. Finish：`Done` 必须有 validation 与 evidence / closeout 引用；`Blocked` 必须有 next action 或 handoff。
9. Operate：用 `archive-review`、`title-suggestions`、`weekly`、`diagnose`、`health-score` 做运营复盘；归档和改标题仍只由人工确认。

## 非目标

- 不创建第二套 runner、progress、queue、promotion 或 checkpoint。
- 不直接写 Codex 内部 SQLite。
- 不自动归档线程，只生成候选、建议和健康分级。
- 不覆盖 `docs/**`、`.ai-governance/**`、workflow gates 或 repo-local skills 的权威地位。
- 不把 subagent 输出当作 PASS、Done、merge-ready 或 closeout 证据。

## Lane

| Lane | 入口含义 | 默认协议 |
|---|---|---|
| Quick | 低风险小任务 | 理解 -> 执行 -> 最小验证 -> Closeout |
| Change | 中等变更、跨文件或需要设计判断 | 只读探索 -> 计划 -> 确认 -> 执行 -> 验证 -> Closeout |
| Mission-Critical | 用户文件、DB、迁移、隐私、权限、密钥等高风险 | 影响/风险/验证/回滚 -> 等确认 -> 执行 -> 双重验证 |
| Explore | 只读调查 | 证据 -> 结论 -> 下一步建议 |
| Review | 只读评审 | findings -> 严重级排序 -> 测试缺口 |
| Ops | 工作流维护、线程清理、状态同步 | 扫描 -> 分类 -> 候选清单 -> 确认 -> 操作 |

## 任务注册表

本地注册表位于：

```text
.codex/runtime/codex-os/task-registry.json
```

它是 Codex 操作面的本地恢复索引，不是产品源事实，也不是 live queue。默认 gitignored。

```bash
./dev codex-os registry init --write
./dev codex-os new --task-id AM-20260629-001 --title "Codex OS workflow automation" --lane Change --recommend-validation --path scripts/dev_tools/codex_os.py --write
./dev codex-os registry status --strict
./dev codex-os registry list
```

兼容字段包括 `risk_level`、`confirmation_status`、`evidence_file`、`closeout_file`、`validation_status`、`automation_scope` 和 `finished_at`。这些字段仍属于本机操作层恢复索引，不是 live queue 或产品源事实。

## Context / Resume / Validation

```bash
./dev codex-os context --task-id AM-20260629-001 --write
./dev codex-os resume --task-id AM-20260629-001
./dev codex-os recommend-validation --changed
./dev codex-os recommend-validation --path scripts/dev_tools/codex_os.py --path .codex/skills-src/areamatrix-codex-os/SKILL.md
```

`recommend-validation` 只输出建议，不执行 registry 中的命令字符串。

## Task Lifecycle

```bash
./dev codex-os preflight --task-id AM-20260629-001 --strict
./dev codex-os task list
./dev codex-os task next --lane Change
./dev codex-os task show --task-id AM-20260629-001
./dev codex-os task start --task-id AM-20260629-001 --write
./dev codex-os task verify --task-id AM-20260629-001 --validation "./dev check codex-os" --write
./dev codex-os task block --task-id AM-20260629-001 --next-action "Wait for confirmation." --write
./dev codex-os lifecycle --task-id AM-20260629-001
```

收尾：

```bash
./dev codex-os evidence --task-id AM-20260629-001 --write
./dev codex-os closeout --task-id AM-20260629-001 --write
./dev codex-os finish \
  --task-id AM-20260629-001 \
  --status Done \
  --validation "./dev check codex-os: PASS" \
  --evidence-file ".codex/runtime/codex-os/evidence/AM-20260629-001.md" \
  --closeout-file ".codex/runtime/codex-os/closeout/AM-20260629-001.md" \
  --archive-recommendation review \
  --write
```

`finish --status Done` 必须能指向新鲜 validation 和 evidence / closeout；`finish --status Blocked`
必须能指向 next action 或 handoff。`--archive-recommendation archive` 只写建议，不执行归档。

## 线程健康与运营

工具只读 `~/.codex/state_5.sqlite`，生成派生健康分：

```text
Active
Warm
Cold
Archive Candidate
Risk Review
Archived
```

健康分是 triage 提示，不是官方运行状态。

```bash
./dev codex-os status
./dev codex-os thread-health --limit 50
./dev codex-os thread-health --json --write
./dev codex-os archive-candidates --limit 50
./dev codex-os archive-review --write
./dev codex-os title-suggestions --write
./dev codex-os dashboard --write
./dev codex-os weekly --write
./dev codex-os health-score --write
./dev codex-os diagnose --task-id AM-20260629-001
```

`Archive Candidate` 只表示“可以人工复核归档”，不是自动归档许可。`Risk Review` 必须人工看标题、handoff 和相关任务状态。

## Subagents

在用户明确要求 subagents、delegation 或并行 agent work 时，复杂任务优先只读并行，主线程写入：

| 角色 | 职责 |
|---|---|
| Main Agent | 决策、写入、验证、最终汇报 |
| Code Explorer | 只读代码路径、调用链、实现风险 |
| Governance Explorer | 只读规则、source of truth、门禁 |
| Validation Explorer | 只读测试命令、历史失败、验证范围 |
| Risk Reviewer | 只读挑错、风险、遗漏 |

写入型 subagent 必须先声明 owner、allowed write set、forbidden touches 和 validation。共享文件只能有一个 owner。

Subagent 输出只能作为主 agent 的输入。PASS、Done、merge-ready、closeout 仍以主 agent 复核后的新鲜验证证据为准。

## 本地输出

常见输出位于：

```text
.codex/runtime/codex-os/dashboard.md
.codex/runtime/codex-os/health-report.md
.codex/runtime/codex-os/thread-health.json
.codex/runtime/codex-os/context.md
.codex/runtime/codex-os/recommend-validation.json
.codex/runtime/codex-os/archive-review.md
.codex/runtime/codex-os/weekly.md
.codex/runtime/codex-os/health-score.json
```

这些文件用于本机观测，不作为产品完成证据提交。

## Health Check

```bash
./dev codex-os doctor
./dev codex-os registry status --strict
./dev check codex-os
```

改动本操作层后，至少运行：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest scripts.dev_tools.test_codex_os
PYTHONDONTWRITEBYTECODE=1 ./dev check codex-os
./dev check skills
./dev check quality
git diff --check -- .codex/references .codex/templates .codex/skills-src .agents/skills scripts/dev_tools
```

若改到 workflow、Rust、Swift 或治理源事实，再追加对应验证。
