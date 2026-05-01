# Git Checkpoint Review Checklist

Use this checklist when a PASS task reaches the Git checkpoint step or when a checkpoint fails.

## Before Live Execution

- `git status --short` must be empty.
- Current branch is either a task branch or will be auto-created from `main`.
- `GIT_CHECKPOINT=push` has a valid remote and credentials.
- Existing local ahead commits are intentional.

## Before Commit

- Verify log contains `VERIFY_RESULT: PASS`.
- `git diff --check` passes.
- Changed files are task-scoped or task-loop evidence files.
- No unrelated manual edits are mixed into the checkpoint.
- Progress, logs, run summary, and index are included as workflow evidence.
- `CODE_REVIEW.md` blockers are not present.
- Required CI or local equivalent checks are listed.

## Commit Evidence

Expected task commit title:

```text
task-loop: complete <label>
```

Expected evidence commit title:

```text
task-loop: record checkpoint evidence <label>
```

Expected evidence fields:

- `git_checkpoint_status`
- `git_branch`
- `git_commit`
- `git_push_status`
- `git_remote`
- `git_changed_files`

## Failure Handling

- `git_diff_check_failed`: stop, inspect whitespace/conflict markers, do not continue.
- `git_push_failed`: keep local commits, fix remote/credential state, rerun push mode.
- unexpected dirty paths after checkpoint: stop and inspect because a task commit likely missed files.
- dry-run: do not report a real commit or upload.
- missing CI/review evidence: do not describe the checkpoint as merge-ready.
