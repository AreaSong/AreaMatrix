---
name: areamatrix-git-checkpoint
description: "Use when Codex needs to review, commit, push, or recover AreaMatrix task-loop Git checkpoints after verify-ready PASS results."
---

# AreaMatrix Git Checkpoint

Use this skill when a task-loop run needs Git checkpoint policy, commit review, push handling, or recovery from Git checkpoint failures.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [CODE_REVIEW.md](../../../CODE_REVIEW.md)
3. [docs/development/ci-governance.md](../../../docs/development/ci-governance.md)
4. [scripts/task_loop.md](../../../scripts/task_loop.md)
5. [areamatrix-task-loop](../areamatrix-task-loop/SKILL.md)
6. [references/checkpoint-policy.md](references/checkpoint-policy.md)

## References

- [references/checkpoint-policy.md](references/checkpoint-policy.md): branch, commit, push, dirty worktree, and recovery policy.
- [references/review-checklist.md](references/review-checklist.md): PASS-time diff review and commit evidence checklist.

## Workflow

1. Confirm the task has a verify log with `VERIFY_RESULT: PASS`.
2. Check Git mode: `GIT_CHECKPOINT=off|commit|push`.
3. Check branch policy before live execution.
4. Review changed files before checkpointing when a failure or unexpected dirty state appears.
5. Use the task-loop summary and progress JSON as the primary evidence trail.

## Guardrails

- Do not checkpoint failed, blocked, or unverified tasks.
- Do not mix pre-existing dirty worktree changes into task commits.
- Do not push by default; push requires `GIT_CHECKPOINT=push`.
- Do not continue to the next task after a Git checkpoint failure.
- Do not treat dry-run Git output as a real commit or upload.
- Do not treat a PASS checkpoint as merge-ready without CI and review evidence.
