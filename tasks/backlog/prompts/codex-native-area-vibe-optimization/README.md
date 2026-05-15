# Codex Native / AreaMatrix / Vibe-Skills Prompt Package

本目录保存短期系统优化的可复制提示词。它不是 `tasks/prompts/**` live queue，不由 `./task-loop` 自动执行。

建议在新对话中按顺序执行：

| 顺序 | Copy-ready | Verify-ready | 目的 |
|---|---|---|---|
| 1 | `copy-ready/task-01-p0-mainline-protection.md` | `verify-ready/task-01-p0-mainline-protection.md` | 固化主线保护 |
| 2 | `copy-ready/task-02-p0-admission-gate.md` | `verify-ready/task-02-p0-admission-gate.md` | 建外部能力接入门禁 |
| 3 | `copy-ready/task-03-p1-openai-docs-mcp.md` | `verify-ready/task-03-p1-openai-docs-mcp.md` | 固化 OpenAI 官方文档核对规则 |
| 4 | `copy-ready/task-04-p1-hooks-guardrail.md` | `verify-ready/task-04-p1-hooks-guardrail.md` | 设计 repo-local 只读 hooks guardrail |
| 5 | `copy-ready/task-05-p1-computer-use-ui-smoke.md` | `verify-ready/task-05-p1-computer-use-ui-smoke.md` | 建 macOS UI smoke runbook |
| 6 | `copy-ready/task-06-p1-repo-local-skills-hardening.md` | `verify-ready/task-06-p1-repo-local-skills-hardening.md` | 强化现有 AreaMatrix skills |
| 7 | `copy-ready/task-07-p2-subagent-boundaries.md` | `verify-ready/task-07-p2-subagent-boundaries.md` | 定义 subagent 边界 |
| 8 | `copy-ready/task-08-p2-vibe-skills-screening.md` | `verify-ready/task-08-p2-vibe-skills-screening.md` | 筛选 Vibe-Skills 横向能力 |

每个执行对话先复制对应 copy-ready；完成后在独立验收对话或同一对话的验收阶段复制 verify-ready。

通用边界：

- 不修改 `tasks/prompts/**` live queue。
- 不启动第二个 `./task-loop`。
- 不安装或启用 Vibe-Skills 全量 skill 仓库。
- 不让外部 runtime 替代 AreaMatrix 的 `docs/`、`.ai-governance/`、`workflow/` 和 `tasks/prompts/**`。

