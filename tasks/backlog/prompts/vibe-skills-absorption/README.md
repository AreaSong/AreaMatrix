# Vibe-Skills Absorption Prompt Package

本目录保存第二批“能力吸收类”可复制提示词。它不是 `tasks/prompts/**` live queue，不由 `./task-loop` 自动执行。

本批只吸收方法价值，不安装、不启用、不复制 `/Users/as/Ai-Project/project/Vibe-Skills` 全量仓库，也不让 `vibe` / VCO runtime 接管 AreaMatrix。

建议按顺序执行：

| 顺序 | Copy-ready | Verify-ready | 目的 |
|---|---|---|---|
| 1 | `copy-ready/task-01-systematic-debugging-runbook.md` | `verify-ready/task-01-systematic-debugging-runbook.md` | 吸收 `systematic-debugging` 为 AreaMatrix 调试 / 失败归因 runbook |
| 2 | `copy-ready/task-02-verification-before-completion.md` | `verify-ready/task-02-verification-before-completion.md` | 吸收 `verification-before-completion` 为完成前证据 checklist |
| 3 | `copy-ready/task-03-review-security-threat-model.md` | `verify-ready/task-03-review-security-threat-model.md` | 用 `code-reviewer` + `security-threat-model` 补强 governance / file-safety |
| 4 | `copy-ready/task-04-planning-handoff-writing-plans.md` | `verify-ready/task-04-planning-handoff-writing-plans.md` | 用 `writing-plans` 补强 workflow planning 和 backlog prompt handoff |

通用边界：

- 不修改 `tasks/prompts/**` live queue。
- 不写 `tasks/prompts/_shared/progress.json`、task-loop logs、run summaries、runner lock 或 Git checkpoint 状态。
- 不启动第二个 `./task-loop`。
- 不安装或启用 Vibe-Skills 全量 skill 仓库。
- 不新增重复 repo-local skill；优先补现有 AreaMatrix skill owner。
- 不让 `.codex/` 替代 `docs/**` 或 `.ai-governance/**` 的源事实。

每个 copy-ready prompt 必须写清目标、非目标、精确路径、source of truth、owner / landing、执行顺序、验证命令和 blocked / rollback 口径。每个 verify-ready prompt 必须保持只读验收，并独立核对 copy-ready 的实现结果；两者不得合并。
