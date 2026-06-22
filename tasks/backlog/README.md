# AreaMatrix Backlog Tasks

本目录是 `tasks/` 轻量任务系统里的候选池，记录尚未进入
`tasks/active/**` 或 `workflow/versions/<version>/execution/**` 的短期规划
任务和治理排期材料。

这些材料用于讨论、评估和治理排期，不代表当前轻量任务进度，也不由
`./task-loop` 自动执行。候选材料可以人工拆成 `tasks/active/<number>.<slug>/`
轻量任务；只有通过 `workflow/` 规划、promotion preview 和人工确认后，才可能
拆成正式 version execution prompt task。

当前 live queue 标准路径是 `workflow/versions/<version>/execution/**`；v1 历史队列已经完成并迁入 `workflow/versions/v1-mvp/execution/**`，进度源事实是 `workflow/versions/v1-mvp/execution/_shared/progress.json`。

## 边界

- `tasks/backlog/**` 不是 live queue，不由 `./task-loop` 扫描、执行、重试或验收。
- `tasks/backlog/**` 不是 `tasks/active/**`，不参与 `./dev tasks status` 的当前任务进度。
- `tasks/backlog/prompts/*` 是脚本可浏览的 backlog prompt package。
- `tasks/backlog/*.md` 是顶层 backlog record / governance record / historical note，不是 prompt package。
- backlog prompt 包只能手工复制或经 `workflow/` planning gate 重新拆分；不得直接 promotion 成 `workflow/versions/<version>/execution/**`。
- 本目录不得引入第二套 runner、progress、queue、checkpoint 或 promotion 机制。
- backlog prompt 不得写 `workflow/versions/<version>/execution/**`、`workflow/versions/<version>/execution/_shared/progress.json`、task-loop logs、run summaries、runner lock 或 Git checkpoint 状态。
- Codex Automations、Cloud、Worktrees、Vibe-Skills、SDK、app-server、remote-control 等外部能力只能作为候选记录；不得接管 AreaMatrix 主线。
- 外部能力候选必须先通过 [外部能力接入门禁](../../.ai-governance/workflows/external-capability-admission.md)，才能从候选记录进入 AreaMatrix 规则、skill、workflow 或 live task 边界。

## Backlog Prompt Handoff

- 每个 prompt 包必须拆成 `copy-ready/` 与 `verify-ready/` 两类材料。
- 每个 prompt 包可以在 README 顶部声明 `- status: open|closed`，供
  `./dev backlog list` 和 `./dev tasks status` 只读展示。
- `open` 表示仍是待处理候选；`closed` 表示已经完成、吸收、拒绝或有明确
  closeout 记录。`closed` 包仍可浏览，用于追溯和人工复制，但不是当前活跃工作。
- `copy-ready` 写实施范围、精确路径、source of truth、owner / landing、执行顺序、验证命令和 blocked / rollback 口径。
- `verify-ready` 写只读验收范围、必须读取路径、证据检查、验证命令和 PASS / FAIL 输出口径。
- 若缺少精确路径、验证命令、owner、source of truth 或 promotion gate 说明，prompt 包保持 `blocked` / `not-ready`，不能进入 live queue。

## Read-only Backlog Tooling

`./dev backlog` 只用于浏览和打印本目录下的 backlog prompt package，并在 `list`
里附带顶层 backlog record 的只读索引：

```bash
./dev backlog list
./dev backlog show <package>
./dev backlog show <package> --task 1 --mode copy
./dev backlog show <package> --task 1 --mode verify
```

该工具不得执行 prompt、不得启动 `./task-loop`、不得调用 `codex exec`、不得写 `workflow/versions/<version>/execution/**`、`workflow/versions/<version>/execution/_shared/progress.json`、logs、run summaries、runner lock 或 Git checkpoint。它只是把 backlog 材料更稳定地展示给人工复制或后续 planning gate 使用。

命令接入边界：

- 根入口 `dev` 先进入 `scripts/task_loop/console.py`；非交互命令由 action registry 决定是否透传到底层开发工具。
- `backlog` 必须作为 `scripts/dev_tools/cli.py` 子命令存在；控制台菜单文案只负责可发现性，不承载读取逻辑。
- `list` 列出 `tasks/backlog/prompts/*/README.md` 对应 package，并展示稳定的 package 索引。
- `list` 还会列出 `tasks/backlog/*.md` 顶层 record；这些 record 不支持 `show <package>`，也不能当 prompt package 执行。
- `show <package>` 打印 package README，并追加简短 `Task Index`；用户可按索引用 `--task N --mode copy|verify` 打印具体 prompt。
- `--task N` 优先按 package README 表格中的 prompt 路径顺序映射；若 package README 没有可解析 prompt 表格，则按 prompt 文件名排序映射，保证稳定。
- `show <package> --task N --mode copy|verify` 只打印对应 `copy-ready` 或 `verify-ready` markdown 文件内容。
- 未知 package、未知 task、指定 `--task` 但缺少 `--mode`、mode 不合法或文件缺失，都必须返回非零并给出可操作错误。

## Prompt Packages

以下条目位于 `tasks/backlog/prompts/*`，可由 `./dev backlog show <package>`
按 package slug 浏览。当前 5 个包均为 `closed`：已完成工作层吸收 / closeout
判断，继续保留为历史候选材料和可复制证据，不代表仍有待执行 backlog。

- [Codex Native / AreaMatrix / Vibe-Skills 基础治理](prompts/codex-native-area-vibe-optimization/)
- [Vibe-Skills 横向能力吸收](prompts/vibe-skills-absorption/)
- [Dev Backlog Tooling](prompts/dev-backlog-tooling/)
- [Codex Operating Layer Closeout](prompts/codex-operating-layer-closeout/)
- [Codex Advanced Non-invasive Layer](prompts/codex-advanced-noninvasive-layer/)

## Backlog Records

以下条目是顶层记录，不是 prompt package。它们只作为治理、盘点或历史判断材料：

- [Codex Operating Layer Inventory](codex-operating-layer-inventory.md)
- [Codex Operating Layer Boundary Regression](codex-operating-layer-boundary-regression.md)
- [Codex Native / AreaMatrix / Vibe-Skills 长期优化任务](codex-native-area-vibe-optimization.md)
