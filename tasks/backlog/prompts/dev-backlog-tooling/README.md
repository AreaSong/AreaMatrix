# Dev Backlog Tooling Prompt Package

本目录保存第三批“backlog 提示词浏览工具”可复制提示词。它不是 `tasks/prompts/**` live queue，不由 `./task-loop` 自动执行。

本批目标是让 `tasks/backlog/prompts/**` 的 copy-ready / verify-ready 材料可以通过 `./dev backlog` 只读浏览，减少手工找文件和复制路径的摩擦；它不是第二套 runner，也不负责执行、验收、promotion、checkpoint 或 progress 写入。

建议按顺序执行：

| 顺序 | Copy-ready | Verify-ready | 目的 |
|---|---|---|---|
| 1 | `copy-ready/task-01-backlog-command-boundary.md` | `verify-ready/task-01-backlog-command-boundary.md` | 核对 `./dev` 入口结构并固化只读命令设计 |
| 2 | `copy-ready/task-02-backlog-list.md` | `verify-ready/task-02-backlog-list.md` | 实现 `./dev backlog list` |
| 3 | `copy-ready/task-03-backlog-show.md` | `verify-ready/task-03-backlog-show.md` | 实现 `./dev backlog show <package> [--task N] [--mode copy\|verify]` |
| 4 | `copy-ready/task-04-backlog-readonly-tests.md` | `verify-ready/task-04-backlog-readonly-tests.md` | 补齐只读回归测试、文档和 dev console 可发现性 |

通用边界：

- 不修改 `tasks/prompts/**` live queue。
- 不写 `tasks/prompts/_shared/progress.json`、task-loop logs、run summaries、runner lock 或 Git checkpoint 状态。
- 不启动第二个 `./task-loop`。
- 不让 backlog prompt package 直接 promotion 成 live queue。
- 不自动执行 copy-ready 或 verify-ready prompt；`./dev backlog` 只负责列出和打印文本。
- 不新增外部 runtime、Vibe-Skills runtime、Codex Automation 或 Cloud/Worktree 依赖。
- 若发现命令实现必须写 live queue 或 progress，立即标记 blocked。

每个 copy-ready prompt 必须保持精确路径、source of truth、owner / landing、执行顺序、验证命令和 blocked / rollback 口径。每个 verify-ready prompt 必须保持只读验收，独立核对实现结果；两者不得合并。
