# Copy-ready: Hooks Warn-only / Read-only Gate

你在 `.` 工作。本任务只判断并补齐 hooks 的 warn-only / read-only 启用预案，不默认启用会改变行为的 hook。

## 目标

把 hooks 从“暂缓”推进到“可按需启用，但有严格门禁”：

- 明确 hooks 只做 guardrail，不替代验收。
- 明确 AreaMatrix 只允许 warn-only / read-only hooks。
- 明确禁止自动改文件、启动/停止 runner、提交、推送、reset、clean、stash。
- 明确 plugin hooks 不进入 AreaMatrix 当前默认工作层。
- 如需要，补一个 repo-local `.codex/hooks.json` 草案或 runbook 里的启用步骤，但不要默认要求用户信任/启用。

## 非目标

- 不启用 destructive hook。
- 不写会自动修改文件的 hook 脚本。
- 不启动或停止 task-loop。
- 不修改 `tasks/prompts/**`。
- 不接入 plugin-bundled hooks。

## Source of Truth

- OpenAI Codex Hooks: `https://developers.openai.com/codex/hooks`
- OpenAI Codex config feature maturity: `https://developers.openai.com/codex/config-basic#supported-features`
- AreaMatrix hooks runbook: `.codex/references/hooks-guardrail-runbook.md`
- Runtime boundary: `.ai-governance/workflows/prompt-task-runtime.md`
- Mainline boundary: `tasks/backlog/README.md`

## Owner / Landing

- Owner: `areamatrix-workflow-planning`
- Supporting owner: `areamatrix-validation-driver`
- Landing: `.codex/references/hooks-guardrail-runbook.md` and `tasks/backlog/**`
- Optional draft landing: `.codex/hooks.json` only if it is explicitly marked as warn-only / read-only and does not invoke mutating commands

## 先读

1. `AGENTS.md`
2. `.codex/references/hooks-guardrail-runbook.md`
3. `.ai-governance/workflows/prompt-task-runtime.md`
4. `tasks/backlog/README.md`
5. OpenAI Codex Hooks 官方文档
6. OpenAI Codex config feature maturity 官方文档

## 允许修改

- `.codex/references/**`
- `tasks/backlog/**`
- `.codex/hooks.json` only if it remains a non-enabled draft / read-only guardrail and is documented with rollback

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- task-loop runtime state directories
- `../Vibe-Skills/**`

## 执行要求

1. 核对官方 hooks 文档：hooks 默认 enabled、plugin_hooks 非默认、hook 事件和拦截限制。
2. 给出 AreaMatrix hooks 决策：
   - allow: warning / additional context / read-only checks
   - deny: mutating hooks, runner-control hooks, Git-control hooks, plugin hooks
3. 若补 `.codex/hooks.json`，只能调用只读脚本或输出 additionalContext / systemMessage，不得写文件。
4. 明确启用前必须人工 `/hooks` review / trust。
5. 明确 rollback：删除或禁用 `.codex/hooks.json`，或在 config 中关闭 hooks。
6. 不让 hooks 成为完成门禁；完成仍以 verify-ready、验证命令、Git checkpoint、review / CI 为准。

## Rollback / Blocked

- 若需要写 mutating hook 才能满足目标，停止并标记 blocked。
- 若官方文档与本地 runbook 不一致，更新 runbook 或记录冲突，不启用 hook。
- 若新增 hooks 会影响 `./task-loop check` 或 prompt doctor，回退该草案。

## 验证

```bash
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references .codex/hooks.json tasks/backlog
```

汇报时说明 hooks 决策、是否新增草案、验证结果和未触碰 `tasks/prompts/**`。
