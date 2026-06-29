# Codex Operating System v1

> 本文件是 AreaMatrix 的 Codex 操作层投影，不是产品、治理或 live execution 的 source of truth。
> 产品语义仍看 `docs/**`，治理边界仍看 `.ai-governance/**`，live 执行仍只从
> `workflow/versions/<version>/execution/**` 和 `./task-loop` 进入。

## 目标

Codex Operating System v1 的目标是把“聊天线程”变成可观测、可恢复、可验证、可归档的工作系统。

核心闭环：

```text
Intake -> Register -> Explore -> Plan -> Execute -> Verify -> Evidence -> Handoff -> Closeout -> Health Check
```

## 0-100% 日常流程

Codex OS 的目标不是让操作者记住更多命令，而是把任务生命周期固定成三个入口：

```bash
./dev codex-os preflight --task-id AM-20260629-001 --strict
./dev codex-os task start --task-id AM-20260629-001 --write
./dev codex-os finish --task-id AM-20260629-001 --status Done --validation "<fresh result>" --evidence-note "<summary>" --write
```

推荐自然语言入口：

```text
Change：按 Codex OS 处理这个任务。先 preflight，必要时登记 task；完成后运行最小充分验证，finish 收尾，并只给归档建议。
```

完整生命周期：

1. Intake：确认 lane、risk、source of truth、允许路径、禁止路径和人工确认边界。
2. Register：把恢复入口写入 `.codex/runtime/codex-os/task-registry.json`。
3. Preflight：检查 registry、task、handoff、验证计划、owner thread、dirty worktree 和 task-loop lock。
4. Explore：用户已授权 subagents 时，用只读 subagents 分别审计代码、文档治理、验证和风险。
5. Plan / Execute：Quick 可直接执行；Change 先计划；Mission-Critical 先说明影响、风险、验证和回滚并等待确认。
6. Verify：按改动范围选择最小充分验证，不默认跑 `./dev check all`。
7. Evidence：记录新鲜验证命令、结果、未验证项、剩余风险和 drift 检查。
8. Finish / Closeout：`Done` 必须有 validation 与 evidence / closeout 引用；`Blocked` 必须有 next action 或 handoff。
9. Health Check：刷新 dashboard，复核 archive candidates；归档仍只由人工确认。

`codex-os doctor` 只验证 Codex 操作层材料、模板、registry 和只读 state 可读性，不能替代 Rust、Swift、docs、workflow、review、CI 或安全验证。

## 非目标

- 不创建第二套 runner、progress、queue、promotion 或 checkpoint。
- 不直接写 Codex 内部 SQLite。
- 不自动归档线程，只生成候选和健康分级。
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

新任务推荐使用 `.codex/templates/codex-intake-template.md`。

打印 intake 模板：

```bash
./dev codex-os intake --lane Change --task-id AM-20260629-001
```

## 任务注册表

本地注册表位于：

```text
.codex/runtime/codex-os/task-registry.json
```

它是 Codex 操作面的本地恢复索引，不是产品源事实，也不是 live queue。默认 gitignored。

初始化：

```bash
./dev codex-os registry init --write
```

新增任务：

```bash
./dev codex-os registry add \
  --task-id AM-20260629-001 \
  --lane Change \
  --status Ready \
  --handoff-file tasks/active/example/HANDOFF.md \
  --next-action "Read handoff and continue." \
  --validation "./dev codex-os doctor" \
  --write
```

更新任务：

```bash
./dev codex-os registry update --task-id AM-20260629-001 --status Verifying --write
```

检查：

```bash
./dev codex-os registry status
./dev codex-os registry list
```

兼容的可选字段：

```text
risk_level
confirmation_status
evidence_file
closeout_file
evidence_note
closeout_note
validation_status
automation_scope
finished_at
```

这些字段仍属于本机操作层恢复索引，不是 live queue 或产品源事实。

## Task Lifecycle 命令

开始前预检：

```bash
./dev codex-os preflight --task-id AM-20260629-001 --strict
./dev codex-os preflight --task-id AM-20260629-001 --write-dashboard
```

任务查看和状态流转：

```bash
./dev codex-os task list
./dev codex-os task next --lane Change
./dev codex-os task show --task-id AM-20260629-001
./dev codex-os task start --task-id AM-20260629-001 --write
./dev codex-os task verify --task-id AM-20260629-001 --validation "./dev check codex-os" --write
./dev codex-os task block --task-id AM-20260629-001 --next-action "Wait for confirmation." --write
```

收尾：

```bash
./dev codex-os finish \
  --task-id AM-20260629-001 \
  --status Done \
  --validation "./dev check codex-os: PASS" \
  --evidence-note "Fresh validation passed after final change." \
  --closeout-note "No remaining required work." \
  --archive-recommendation review \
  --write
```

`finish --status Done` 必须能指向新鲜 validation 和 evidence / closeout；`finish --status Blocked`
必须能指向 next action 或 handoff。`--archive-recommendation archive` 只写建议，不执行归档。

## 状态机

任务状态只能使用：

```text
Backlog
Ready
Running
Waiting Confirmation
Blocked
Verifying
Done
Archived
Abandoned
```

`Done` 需要新鲜验证证据或明确未验证项；没有证据时只能是 `Blocked`、`Running` 或 `Waiting Confirmation`。

## Handoff / Evidence

恢复交接模板：

```bash
./dev codex-os handoff --task-id AM-20260629-001
```

证据记录模板：

```bash
./dev codex-os evidence --task-id AM-20260629-001
```

建议所有 Change / Mission-Critical 任务至少有 handoff；所有 Done 任务必须能指向 evidence 或 closeout 中的新鲜验证结果。

## 线程健康分级

工具只读 `~/.codex/state_5.sqlite`，生成派生健康分：

```text
Active
Warm
Cold
Archive Candidate
Risk Review
Archived
```

健康分是 triage 提示，不是官方运行状态。尤其是：

- `Archive Candidate` 只表示“可以人工复核归档”，不是自动归档许可。
- `Risk Review` 必须人工看标题、handoff 和相关任务状态。
- `thread_spawn_edges.status = open` 只表示有打开的派生关系，不等价于仍在执行。

命令：

```bash
./dev codex-os status
./dev codex-os thread-health --limit 50
./dev codex-os thread-health --json --write
./dev codex-os archive-candidates --limit 50
```

## Dashboard

生成本地 dashboard 和 health report：

```bash
./dev codex-os dashboard --write
```

输出：

```text
.codex/runtime/codex-os/dashboard.md
.codex/runtime/codex-os/health-report.md
.codex/runtime/codex-os/thread-health.json
```

这些文件用于本机观测，不作为完成证据提交。

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

## Closeout

每个线程结束前使用：

```bash
./dev codex-os closeout --task-id <task-id>
```

最小 closeout 字段：

```text
状态
任务 ID
完成内容
验证
未验证项
剩余风险
下一步入口
是否建议归档
```

没有 closeout 的线程默认不能批量归档，只能进入人工 triage。

## Health Check

本地健康检查：

```bash
./dev codex-os doctor
./dev check codex-os
```

推荐周期：

- 每天：`./dev codex-os dashboard --write`
- 每周：复核 `Archive Candidate` 和 `Risk Review`
- 每个 Change / Mission-Critical 结束：closeout + registry 更新 + 项目验证

## 自然语言入口

可以直接对 Codex 说：

```text
Ops：做一次 Codex 工作区体检，只读生成 dashboard，不归档。
Ops：列出 AreaMatrix 可归档候选，但不要执行归档。
Change：读取 task registry，从 next_action 继续。
Review：检查 Done 但没有验证证据的任务。
```

## 验证

改动本操作层后，至少运行：

```bash
./dev codex-os doctor
./dev check codex-os
./dev check skills
./dev check quality
git diff --check -- .codex/references .codex/templates scripts/dev_tools
```

若改到 workflow、Rust、Swift 或治理源事实，再追加对应验证。
