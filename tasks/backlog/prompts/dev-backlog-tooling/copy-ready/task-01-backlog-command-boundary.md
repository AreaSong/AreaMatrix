# Copy-ready: Dev Backlog Command Boundary

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务只设计并固化 `./dev backlog` 的只读边界，不实现完整功能。

## 目标

为 backlog prompt package 增加清晰、可验证的命令设计，后续任务实现：

```bash
./dev backlog list
./dev backlog show <package>
./dev backlog show <package> --task 1 --mode copy
./dev backlog show <package> --task 1 --mode verify
```

命令只能读取和打印 `tasks/backlog/prompts/**` 内容，不执行 prompt，不写 live queue，不写 progress。

## 非目标

- 不实现 task-loop runner。
- 不修改 `tasks/prompts/**`。
- 不写 `tasks/prompts/_shared/progress.json`、logs、run summaries、runner lock 或 checkpoint。
- 不把 backlog prompt package promotion 成 live queue。
- 不改 Vibe-Skills 仓库，不接入外部 runtime。

## Source of Truth

- Backlog boundary: `tasks/backlog/README.md`
- Workflow boundary: `workflow/AGENTS.md`、`workflow/README.md`
- Live queue boundary: `tasks/prompts/README.md`
- Runtime governance: `.ai-governance/workflows/prompt-task-runtime.md`
- Dev console architecture: `dev`、`scripts/task_loop/console.py`、`scripts/task_loop/actions.py`、`scripts/dev_tools/cli.py`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Implementation landing for later tasks: `scripts/dev_tools/**` and, if needed, `scripts/task_loop/**`
- Documentation landing: `tasks/backlog/README.md` and this prompt package

## 先读

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `workflow/AGENTS.md`
4. `workflow/README.md`
5. `tasks/prompts/README.md`
6. `.ai-governance/workflows/prompt-task-runtime.md`
7. `dev`
8. `scripts/task_loop/console.py`
9. `scripts/task_loop/actions.py`
10. `scripts/dev_tools/cli.py`
11. `scripts/dev_tools/common.py`

## 允许修改

- `tasks/backlog/**`
- `scripts/dev_tools/**` only if a tiny helper or design stub is needed
- `scripts/task_loop/**` only if command discoverability requires a registry placeholder

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- `/Users/as/Ai-Project/project/Vibe-Skills/**`
- `.codex/task-loop-logs/**`
- `.codex/task-loop-runs/**`
- task-loop lock/control/checkpoint state

## 执行要求

1. 核对 `./dev` 的真实入口：根 `dev` 是否先进入 `scripts/task_loop/console.py`，以及底层开发工具是否由 `scripts/dev_tools/cli.py` 分发。
2. 决定 `./dev backlog` 应如何接入：底层 `scripts/dev_tools/cli.py` 必须有子命令；若控制台需要可发现性，后续任务再在 `scripts/task_loop/actions.py` 或 help/menu 文案中暴露。
3. 明确命令语义：
   - `list`: 列出 `tasks/backlog/prompts/*/README.md` 对应 package。
   - `show <package>`: 打印 package README 或任务索引。
   - `show <package> --task N --mode copy|verify`: 打印对应 prompt 文件内容。
4. 明确错误语义：未知 package、未知 task、缺少 mode、文件缺失都返回非零并给出可操作错误。
5. 明确只读约束：命令不得调用 `./task-loop`、不得调用 `codex exec`、不得写 progress、不得修改 `tasks/prompts/**`。
6. 若新增设计说明，保持简短；不要生成低价值大报告。

## Rollback / Blocked

- 若现有 `./dev` 结构与预期不一致，先记录实际入口和推荐接入点，不继续实现。
- 若要实现该命令必须修改 live queue 或 runner state，停止并标记 blocked。
- 若发现已有等价命令，优先记录复用方式，不重复实现。

## 验证

```bash
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- tasks/backlog scripts/dev_tools scripts/task_loop
```

汇报时说明命令边界、接入点、后续任务是否可以继续，以及本任务未触碰 `tasks/prompts/**`。
