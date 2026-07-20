---
name: areamatrix-task-loop
description: "Use when the task involves the AreaMatrix silent task loop: starting, monitoring, resuming, or explaining `./task-loop` runs, copy-ready / verify-ready prompts, retry-on-fail repair, progress tracking, run summaries, or risk gates. Trigger phrases include 跑任务循环 / 继续执行队列 / 任务卡住了 / stale progress / failed verify / blocked task."
---

# AreaMatrix Task Loop

Use this skill when the work is about the automated prompt task runner rather than a single product feature.

Trigger it for questions about `./task-loop`, `./dev` runner actions, copy-ready / verify-ready execution, progress labels, stale / failed / blocked recovery, logs, run summaries, risk policy, start / stop / resume semantics, or silent execution.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [.ai-governance/workflows/prompt-task-runtime.md](../../../.ai-governance/workflows/prompt-task-runtime.md)
3. [scripts/task_loop.md](../../../scripts/task_loop.md)
4. [workflow/versions/v1-mvp/execution/README.md](../../../workflow/versions/v1-mvp/execution/README.md)
5. [workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md](../../../workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md)

## References

- [references/runbook.md](references/runbook.md): execution modes, start points, logs, and progress state.
- [references/failure-recovery.md](references/failure-recovery.md): failed verify, blocked tasks, stale progress, and legacy state recovery.
- [../../references/debugging-failure-attribution-runbook.md](../../references/debugging-failure-attribution-runbook.md): shared copy / verify / validation / runner / checkpoint failure attribution order.
- [../../references/codex-automations-cloud-worktrees-gate.md](../../references/codex-automations-cloud-worktrees-gate.md): why Automations / Cloud / Worktrees must not become a second task-loop runner or state surface.
- [../areamatrix-git-checkpoint/SKILL.md](../areamatrix-git-checkpoint/SKILL.md): Git checkpoint policy for PASS tasks.
- [../areamatrix-validation-driver/SKILL.md](../areamatrix-validation-driver/SKILL.md): choose checks when runner or prompt infrastructure changed.
- [../areamatrix-workflow-planning/SKILL.md](../areamatrix-workflow-planning/SKILL.md): keep future v* planning outside version execution until promoted.
- [../areamatrix-residual-ledger/SKILL.md](../areamatrix-residual-ledger/SKILL.md): residual ledger entries are not live queue inputs unless explicitly converted or promoted.

## Workflow

1. Check prompt health with `./dev check prompts`.
2. Check task-loop health with `./task-loop check` when runner behavior changed.
3. For v1 historical audit/recovery only, check archived queue state with `python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py status`.
4. Check task-loop state with `./task-loop status`.
5. Load the Git checkpoint skill before changing commit or push behavior.
6. Load the runbook before recommending a live command.
7. Load failure recovery before changing progress or restarting from a failed task.
8. Load the debugging / failure attribution runbook before deciding whether a stop belongs to copy, verify, validation, runner, checkpoint, docs drift, or file safety.

## Guardrails

- Do not manually mark a task completed unless verify output proves `VERIFY_RESULT: PASS`.
- Do not skip failed verification by moving to the next task.
- Do not treat a task as done when engineering-quality blockers remain.
- Do not delete progress or logs unless the user explicitly wants a fresh run.
- Do not present dry-run success as real task completion.
- Do not continue after a Git checkpoint failure; fix or recover Git state first.
- Do not treat backlog prompts, Codex Automations, Cloud, Worktrees, or Vibe-Skills as live queue inputs unless they have been explicitly promoted into `workflow/versions/<version>/execution/**`.
- Do not treat `workflow/residuals/**`, `workflow/versions/<version>/residuals/**`, or `tasks/indexes/**` as live queue inputs.
