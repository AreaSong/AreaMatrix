# Copy-ready: P1 repo-local 只读 hooks guardrail

你在 `.` 工作。本任务先设计 hooks guardrail，不默认启用会改变行为的 hook。

## 目标

为 AreaMatrix 设计 repo-local 只读 hooks guardrail，用来提醒或阻断明显风险：

- 已有 live runner 时不要启动第二个 runner。
- dirty worktree 会阻塞 Git checkpoint。
- 高风险用户文件路径、DB migration、UDL/Core API 破坏性变化需要显式确认。
- 任务完成前不要跳过验证。

## 先读

1. `AGENTS.md`
2. `.ai-governance/README.md`
3. `.ai-governance/workflows/prompt-task-runtime.md`
4. `.codex/references/codex-workflow-and-tools.md`
5. `tasks/backlog/codex-native-area-vibe-optimization.md`
6. OpenAI Codex hooks 官方文档，优先用 OpenAI Docs MCP 核对当前 hook schema 和限制

## 允许修改

- `.codex/references/**`
- `.ai-governance/**`
- `tasks/backlog/**`
- 仅当文档明确要求并且保持只读/安全时，才可新增 `.codex/hooks.json` 草案

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- 任何自动修改用户文件的 hook
- 任何会自动启动、停止、提交、推送的 hook

## 执行要求

1. 优先产出 hooks runbook 或设计说明。
2. 明确 hooks 是 guardrail，不是完整验收系统。
3. 如果新增 `.codex/hooks.json`，必须只做只读检查或通知，并说明如何禁用/回滚。
4. 不依赖 plugin hooks；当前只考虑 Codex stable hooks。

## 验证

```bash
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex tasks/backlog
```

如新增 hook 配置，还要说明是否被 Codex 信任、是否需要人工审批，以及没有实际运行破坏性命令。

