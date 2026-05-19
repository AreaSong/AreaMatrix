# Codex Advanced Non-invasive Layer Prompt Package

本目录保存第五批“高级但非侵入式 Codex 能力”可复制提示词。它不是 `tasks/prompts/**` live queue，不由 `./task-loop` 自动执行。

本批用于把此前暂缓项补成“有判断、有门禁、有触发条件”的状态，而不是默认启用或接管主线：

- hooks：只允许 warn-only / read-only 方案或预案，不自动修改文件、提交、启动/停止 runner。
- Browser / Chrome / Computer Use：只做 UI / web / macOS smoke 验收模板，不替代命令门禁。
- Automations / Cloud / Worktrees：只做禁写主线门禁和触发条件，不创建 automation，不启用 cloud runtime。
- Vibe professional skills：只做专业 skill 白名单 / 触发矩阵，不安装全量 Vibe-Skills，不启用 Vibe runtime。

建议按顺序执行：

| 顺序 | Copy-ready | Verify-ready | 目的 |
|---|---|---|---|
| 1 | `copy-ready/task-01-hooks-warn-only.md` | `verify-ready/task-01-hooks-warn-only.md` | 判断并补齐 hooks warn-only / read-only 启用预案 |
| 2 | `copy-ready/task-02-browser-computer-use-templates.md` | `verify-ready/task-02-browser-computer-use-templates.md` | 补 Browser / Chrome / Computer Use 场景模板 |
| 3 | `copy-ready/task-03-automations-cloud-worktrees-gate.md` | `verify-ready/task-03-automations-cloud-worktrees-gate.md` | 补 Automations / Cloud / Worktrees 禁写主线门禁 |
| 4 | `copy-ready/task-04-vibe-professional-trigger-matrix.md` | `verify-ready/task-04-vibe-professional-trigger-matrix.md` | 补 Vibe 专业 skill 白名单与触发矩阵 |

通用边界：

- 不修改 `tasks/prompts/**` live queue。
- 不写 `tasks/prompts/_shared/progress.json`、task-loop logs、run summaries、runner lock 或 Git checkpoint 状态。
- 不启动第二个 `./task-loop`。
- 不安装或启用 Vibe-Skills 全量仓库。
- 不创建 Codex Automation，不启用 Cloud / Worktree 作为 AreaMatrix canonical runtime。
- 不启用 plugin-bundled hooks。
- 不把 `.codex/**`、`tasks/backlog/**` 或 workflow preview 当作产品语义源事实。
