---
name: areamatrix-task-loop
description: "Use when Codex needs to start, monitor, resume, or explain the AreaMatrix silent task loop that runs copy-ready prompts, verify-ready prompts, retry-on-fail repair, progress tracking, and risk gates."
---

# AreaMatrix Task Loop

Use this skill when the work is about the automated prompt task runner rather than a single product feature.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [.ai-governance/workflows/prompt-task-runtime.md](../../../.ai-governance/workflows/prompt-task-runtime.md)
3. [scripts/run_area_matrix_task_pipeline.md](../../../scripts/run_area_matrix_task_pipeline.md)
4. [tasks/prompts/README.md](../../../tasks/prompts/README.md)
5. [tasks/prompts/_shared/engineering-quality-rules.md](../../../tasks/prompts/_shared/engineering-quality-rules.md)

## References

- [references/runbook.md](references/runbook.md): execution modes, start points, logs, and progress state.
- [references/failure-recovery.md](references/failure-recovery.md): failed verify, blocked tasks, stale progress, and legacy state recovery.

## Workflow

1. Check health with `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`.
2. Check task-loop health with `bash scripts/check-task-loop.sh` when runner behavior changed.
3. Check current queue state with `python3 tasks/prompts/_shared/prompt_pipeline.py status`.
4. Check task-loop state with `bash scripts/run_area_matrix_task_pipeline.sh --status`.
5. Load the runbook before recommending a live command.
6. Load failure recovery before changing progress or restarting from a failed task.

## Guardrails

- Do not manually mark a task completed unless verify output proves `VERIFY_RESULT: PASS`.
- Do not skip failed verification by moving to the next task.
- Do not treat a task as done when engineering-quality blockers remain.
- Do not delete progress or logs unless the user explicitly wants a fresh run.
- Do not present dry-run success as real task completion.
