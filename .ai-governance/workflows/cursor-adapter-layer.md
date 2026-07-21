# Cursor Adapter Layer

> 本规则定义 Cursor（IDE / CLI / Cloud agents）在 AreaMatrix 中的适配层边界。`.cursor/` 是投影层，不是第二套规则源、第二套任务系统，也不是第二套 runner。

## 基线结论

- 协作语义的权威来源仍是 `.ai-governance/**`、根 `AGENTS.md` 与各目录局部 `AGENTS.md`；`.cursor/rules`、`.cursor/skills`、`.cursor/commands`、`.cursor/hooks` 只承载 Cursor 形态的投影与触发器。
- 语义变更先改 `.ai-governance/**` 或对应 `docs/**`，再同步 `.cursor/**` 文本；两处冲突时以源事实为准。
- Cursor 适配层不得接管 live execution 主线（`./dev + ./task-loop + workflow/versions/<version>/execution/**`），不写 execution progress、queue、checkpoint、promotion、runner lock 或 task-loop logs。
- Cursor 适配层与 Codex 适配层（`.codex/**`）互不替代、互不导入；Codex hooks 决策继续以 [hooks guardrail runbook](../../.codex/references/hooks-guardrail-runbook.md) 为准。
- Cursor 已注入根与局部 `AGENTS.md` 作为规则；`.cursor/rules/` 不得复制 `AGENTS.md` 已有内容，只承载 Cursor 专属工作流语义，避免双源漂移。

## 目录职责

| 路径 | 职责 | 是否入库 |
|---|---|---|
| `.cursor/rules/` | Cursor 注入规则，仅承载 `AGENTS.md` 未覆盖的 Cursor 工作流语义 | 是 |
| `.cursor/skills/` | Cursor Agent 静默规程（session-bootstrap / closeout / plan-sync / pre-push-review） | 是 |
| `.cursor/commands/` | 斜杠兼容镜像，指向对应 skill；不要求用户手打斜杠 | 是 |
| `.cursor/hooks/` | sessionStart / stop / beforeShellExecution 兜底钩子脚本 | 是 |
| `.cursor/plans/` | Cursor 会话级进行中计划 | 否（本地状态） |
| Cursor 工作区级 `canvases/` | 可视化投影面板（residual ledger、产品能力图） | 否（工作区数据，不在仓库内） |

## 静默 Skill 触发表

Cursor Agent 到点直接执行对应 skill，禁止要求用户手打 `/closeout` 等斜杠命令。

| 时机 | 静默执行 |
|---|---|
| 新对话、续做未完成工作 | `areamatrix-session-bootstrap` |
| 功能或修复合完、宣称完成前 | `areamatrix-closeout` |
| 任务不少于 3 步、Plan 确认后、步骤完成时 | `areamatrix-plan-sync` |
| 用户要求 push、开 PR、准备合并前 | `areamatrix-pre-push-review` |

- 同会话新任务重判上表；上下文压缩后重读 `AGENTS.md` 与命中的 skill，不凭记忆沿用。
- Cursor skills 是操作规程；业务语义命中根 `AGENTS.md` Skill 路由表时，仍按该表读取 `.agents/skills/areamatrix-*` 对应 SKILL.md。

## .cursor/plans/ 边界

- `.cursor/plans/` 只追踪 Cursor 会话级进行中计划：目标、步骤清单、每项完成标准、当前状态。
- 它不是 `tasks/active/**`、`tasks/backlog/**`、`workflow/versions/<version>/execution/**` 的替代品，不写 execution progress、queue、checkpoint，也不进入 `./dev tasks` 或 `./task-loop` 索引。
- 计划全部步骤完成后删除对应 plan 文件，不留存已完成计划。
- 需要长期追踪的工作仍按既有边界进入 `tasks/active/**` 或 `workflow/` 规划生命周期。

## Canvas 投影纪律

- Canvas 面板保存在 Cursor 工作区级 `canvases/` 目录，是只读投影，不是第二套事实。
- residual 面板的源事实是 `workflow/residuals/**` 与各版本 residuals；能力面板的源事实是 `docs/product/capabilities.md`。
- 冲突时以仓库内源事实为准；源状态变化时同轮更新对应 canvas 快照，并在 canvas 顶部标注快照日期。
- Canvas 不承载新的产品、架构或任务语义；新增语义先落到 `docs/**` 或对应账本。

## Hooks 边界

Cursor hooks 与 Codex hooks 分属两个工具层。`.codex/hooks.json` 维持既有决策（默认不新增）；`.cursor/hooks/` 遵守以下边界：

| 类型 | 结论 | 说明 |
|---|---|---|
| sessionStart 注入上下文 | 允许 | 只读列出未完成 plans、dirty worktree 归属提示；不写文件 |
| stop 一次性提醒 | 允许 | 仓库关键目录脏且会话完成时提醒执行 closeout；`loop_limit` 为 1，不循环催促 |
| beforeShellExecution 高风险确认 | 允许 | 命中 live 主线命令时返回 ask，把决策交还用户交互；不自动 allow / deny |
| 自动改文件、控制 runner、Git 写操作 | 禁止 | hook 脚本不写仓库文件，不调用 runner 控制命令，不提交、推送或改分支 |
| 静默阻断 | 禁止 | 不无提示拦截命令；需要人工决策时只用 ask |

- 所有 hook 脚本 fail-open：脚本自身出错时输出空结果放行，不阻塞会话。
- beforeShellExecution 守卫命令清单：`./task-loop` 真实运行子命令、`./dev workflow promote` 的 approve / apply、`./dev tasks complete --write`、`git push --force`。清单变更先改本文件，再同步脚本。
- stop 提醒存在已知误报面：对非本会话遗留的 dirty worktree 也会提示。closeout skill 必须先确认改动归属，非本次会话产生的改动不纳入收口。

## 验证

Cursor 适配层文本或 hooks 变更后至少运行：

```bash
./dev check governance
./dev check docs
bash -n .cursor/hooks/*.sh
```

涉及根 `AGENTS.md`、`.ai-governance/**` 或其他长期源事实文本时，追加 `./dev check wording`。
