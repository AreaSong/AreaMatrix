# Codex Automations / Cloud / Worktrees Gate

本文记录 AreaMatrix 对 Codex Automations、Codex Cloud 和 Codex App Worktrees 的当前门禁。它只描述 Codex 运行层，不是 AreaMatrix 产品语义源事实。

截至 2026-05-16 核对的官方来源：

- OpenAI Codex Automations: https://developers.openai.com/codex/app/automations
- OpenAI Codex Cloud / web: https://developers.openai.com/codex/cloud
- OpenAI Codex Cloud environments: https://developers.openai.com/codex/cloud/environments
- OpenAI Codex Cloud internet access: https://developers.openai.com/codex/cloud/internet-access
- OpenAI Codex Worktree support: https://developers.openai.com/codex/app/features#worktree-support
- OpenAI Codex Worktrees: https://developers.openai.com/codex/app/worktrees

## Baseline

AreaMatrix live execution 仍是：

```text
docs/**
-> .ai-governance/**
-> workflow/ planning gate
-> tasks/prompts/** live queue
-> ./dev / ./task-loop
-> repo-local skills
```

Automations、Cloud 和 Worktrees 都不得写入或替代这条主线。三者必须先通过 [External Capability Admission Gate](../../.ai-governance/workflows/external-capability-admission.md)，再按具体任务另行确认。

## Decision Table

| Capability | Decision | Trigger condition | Forbidden writes / substitutions | Owner | Validation |
|---|---|---|---|---|---|
| Current AreaMatrix mainline | Recommended | live queue implementation, verify-ready acceptance, progress, checkpoint, recovery | 不适用；继续由主线自己写 state | `areamatrix-task-loop` + `areamatrix-git-checkpoint` | task / phase 要求的验证、`VERIFY_RESULT: PASS`、Git checkpoint、review / CI evidence |
| Automations | Trigger-based only | reminders, periodic read-only checks, status briefings, non-writing triage candidates; creation or update requires explicit separate confirmation | `tasks/prompts/**`; `tasks/prompts/_shared/progress.json`; `.codex/task-loop-logs/**`; `.codex/task-loop-runs/**`; `.codex/task-loop-lock/**`; checkpoint state; branch / commit / push; starting, stopping, resuming, draining, or replacing `./task-loop` | `areamatrix-workflow-planning`; support: `areamatrix-task-loop`, `areamatrix-git-checkpoint`, `areamatrix-file-safety` | manual prompt test before scheduling; `./dev check skills`; `./dev check governance`; prompt doctor; path-level diff check |
| Cloud | Defer | future isolated execution, remote review, PR experiment, or cloud-only collaboration after an admission record closes environment and privacy risks | same live queue and task-loop state paths; no direct `codex apply` into the canonical checkout without review, local validation, and checkpoint plan; no canonical runtime replacement | `areamatrix-workflow-planning`; support: `areamatrix-file-safety`, `areamatrix-git-checkpoint`, `areamatrix-task-loop` | local environment plan; credential / secret plan; privacy and network review; diff apply plan; local validation plan; checkpoint / rollback plan; standard governance checks |
| Worktrees | Defer | isolated spike, parallel independent task, future version planning, or risky experiment where the current checkout must stay untouched | same live queue and task-loop state paths; no default live queue execution; no bypass of `workflow/**` planning / promotion gate; no reuse of live task labels outside promotion | `areamatrix-workflow-planning`; support: `areamatrix-git-checkpoint`, `areamatrix-task-loop`, `areamatrix-file-safety` | worktree owner; base branch; sync / handoff plan; ignored-file caveat; cleanup plan; conflict plan; local validation and checkpoint plan |
| Any second runner / state surface | Reject | any design that would turn Automations, Cloud, or Worktrees into another `./task-loop` | runner, progress, queue, logs, run summaries, checkpoint, promotion, task labels, or canonical runtime state | `areamatrix-workflow-planning` | reject during admission; design fails before implementation |

## Risk Notes

Automations run in the background and are unattended. Official docs say they use default sandbox settings; with read-only, modifying files or using network / apps can fail, while with broader access background runs carry elevated risk. For Git repos, automations can run in local mode or a worktree; local mode can modify files that are actively being edited. AreaMatrix therefore does not allow repo-state-writing automations by default.

Cloud changes the execution environment. Codex Cloud creates a container, checks out the selected repo branch or commit, runs setup, applies environment internet settings, then runs commands and returns a diff or PR path. Before AreaMatrix can use it, the admission record must cover local environment setup, credentials and secrets, privacy, network access, diff apply, local validation, checkpoint, and rollback.

Worktrees isolate file changes but do not define task semantics. Codex App worktrees use Git worktrees under the hood, are stored under `$CODEX_HOME/worktrees`, can be detached HEAD checkouts, and can have branch / handoff limits. AreaMatrix can use that isolation only for experiments or independent work; it cannot replace `workflow/**` gates, promotion mapping, live task labels, or task-loop progress.

## Blocked / Rollback

- If a request asks to actually create an automation, enable a Cloud task, create a worktree, or apply a Cloud diff, stop and ask for separate confirmation.
- If an automation, Cloud run, or worktree would write `tasks/prompts/**`, progress, task-loop logs, run summaries, lock, checkpoint, branch, commit, push, or promotion state, reject the design.
- If user files, privacy, remote AI calls, credentials, secrets, DB, staging, FSEvents, iCloud, or destructive file operations are involved, route through `areamatrix-file-safety` and Mission-Critical review before implementation.

