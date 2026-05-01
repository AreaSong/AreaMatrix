# Git Checkpoint Policy

AreaMatrix task-loop Git checkpoints run only after verify-ready reports `VERIFY_RESULT: PASS`.

## Modes

| Mode | Meaning |
|---|---|
| `GIT_CHECKPOINT=off` | Do not touch Git. Use only while repairing runner infrastructure or doing diagnostics. |
| `GIT_CHECKPOINT=commit` | Default. Commit each PASS task locally and keep the worktree clean. |
| `GIT_CHECKPOINT=push` | Commit each PASS task and push the task-loop branch. Use only when remote credentials and branch policy are ready. |

Dry-run never creates real commits or pushes, regardless of mode.

## Branch Policy

Default:

```bash
GIT_BRANCH_POLICY=auto
```

Behavior:

- If the current branch is `main`, the runner creates `codex/areamatrix-task-loop-<run_id>` before writing progress, logs, or summaries.
- If the current branch is not `main`, the runner keeps the current branch.
- `GIT_BRANCH_POLICY=require-task-branch` refuses to run on `main`.
- `GIT_BRANCH_POLICY=current` allows the current branch as-is.

## Dirty Worktree Policy

Live checkpoint mode requires a clean worktree before execution starts.

If pre-existing changes are present:

1. Commit the infrastructure changes first, or
2. run with `GIT_CHECKPOINT=off` only for diagnostics or temporary infrastructure work.

Do not let a task checkpoint mix old manual changes with a newly verified task.

## Evidence Commits

The final commit hash cannot be written into the same commit that defines it. The runner therefore creates:

1. a task completion commit, `task-loop: complete <label>`;
2. a small evidence commit, `task-loop: record checkpoint evidence <label>`, which records the completion commit hash in progress and summary files.

At the end of a successful run, the runner may create `task-loop: finalize run <run_id>` for final summary/index state.

## Push Recovery

When `GIT_CHECKPOINT=push` fails:

- the local task completion commit is preserved;
- progress and summary record `git_push_failed`;
- the runner stops before the next task.

After fixing credentials or remote state, rerun with `GIT_CHECKPOINT=push`. Preflight will push existing ahead commits before continuing.
