# AreaMatrix Task Loop Failure Recovery

Use this reference when the task loop stops, retries, or reports stale state.

For unknown failures, start with the shared [debugging and failure attribution runbook](../../../references/debugging-failure-attribution-runbook.md). Do not collapse copy, verify, validation, runner, checkpoint, docs drift, and file-safety failures into one bucket.

## Attribution Fields

Inspect these fields before choosing a recovery command:

1. `./dev status --verbose`: current operator view, latest task, latest verify excerpt, runner process and recovery hint.
2. `./task-loop status`: progress counts, lock state, stale detection, latest log directory.
3. `tasks/prompts/_shared/progress.json`: `status`, `note`, `attempts`, `risk`, `run_id`, `copy_log`, `verify_log`, `git_checkpoint_status`, `git_push_status`, `git_branch`, `git_commit`, `git_changed_files`.
4. `.codex/task-loop-runs/index.json`: latest `run_id`, `status`, `summary_file`, `completed`, `retries`, `exit_code`.
5. `.codex/task-loop-runs/<run_id>/summary.json`: run-level `status`, `exit_code`, `note`, `totals`, risk policy, Git mode, and per-task logs.
6. `*-copy-attempt-<n>.log` and `*-verify-attempt-<n>.log`: stage-specific evidence.
7. `git status --short` and `git diff --check`: dirty worktree evidence when verify passed but checkpoint failed.

## Verify Failed

Symptoms:

- verify log does not contain `VERIFY_RESULT: PASS`
- task retries the same copy-ready prompt with injected failure context

Action:

1. Open the latest `*-verify-attempt-<n>.log`.
2. Extract the first concrete blocker, not just the final FAIL.
3. Check whether the blocker is functional, validation-related, or engineering-quality-related.
4. Confirm the next copy attempt includes the failure summary.
5. Let the loop retry unless `MAX_RETRIES` stopped it.

Do not mark completed unless the verify log has `VERIFY_RESULT: PASS`.
Do not treat a final-line-only `VERIFY_RESULT: FAIL` as sufficient feedback; rerun or inspect with enough context to produce a repairable failure summary.

## Max Retries Reached

Symptoms:

- task status becomes `failed`
- script exits non-zero

Action:

```bash
./task-loop status
./task-loop resume-failed
```

If the failure is conceptual rather than transient, inspect the task file, manifest section, copy log, and verify log before resuming.

Use `./task-loop check` if the failure looks like runner state corruption rather than task implementation failure.

## Risk Gate Blocked

Symptoms:

- task status becomes `blocked`
- note says `风险门禁暂停` or `风险门禁跳过`

Action options:

- Continue with explicit approval: `RISK_POLICY=allow START_FROM=<label> ./task-loop run`
- Keep blocked and report: use when the user has not authorized Mission-Critical execution.
- Skip only if the user requested skip semantics: `RISK_POLICY=skip`.

Do not silently convert `blocked` to `completed`.

## Stale Progress

Symptoms:

- `prompt_pipeline.py status` and expected queue position disagree
- a task is recorded `in_progress` after an interrupted process
- `./task-loop status` reports `stale_in_progress`

Action:

1. Run `./task-loop status`.
2. Check whether `lock_alive` is `yes`; if so, do not start a second runner.
3. Inspect `progress.json` entry and the latest copy/verify logs for the affected task.
4. Prefer `./task-loop resume-stale` over manual JSON edits.
5. If the user wants a clean restart, use `./task-loop reset-progress`; it backs up progress and preserves logs.

Manual progress edits are allowed only when the user explicitly asks for state repair.

If the stale entry is only an interrupted `in_progress` record and the user does not want to resume it, use:

```bash
./task-loop clear-stale
```

This removes only stale `in_progress` entries and must not touch `completed`, `failed`, or `blocked`.

If stale behavior itself looks wrong, run `./task-loop check`; it validates stale detection and resume behavior against temporary progress files.

## Git Checkpoint Failure

Symptoms:

- verify passed but the runner stops before the next task
- progress or summary records `git_checkpoint_status=git_diff_check_failed` or `git_push_failed`
- output references `scripts/task_loop/git.py`

Action:

1. Read `$areamatrix-git-checkpoint`.
2. For `git_push_failed`, fix credentials or remote state and rerun with `GIT_CHECKPOINT=push`; preflight will push local ahead commits before continuing.
3. For `git_diff_check_failed`, inspect `git diff --check`, fix the dirty worktree, and rerun from the same task or use `GIT_CHECKPOINT=off` only for diagnostics.
4. Do not clear completed progress just to bypass Git evidence.

## Legacy State File

If `.codex/task-loop-state.txt` exists:

- Treat it as historical completion hints.
- Do not use it as the source of truth.
- Do not delete it unless the user asks for a fresh run.
- If it conflicts with `progress.json`, prefer `progress.json`.

## Cleanup

Allowed cleanup:

- empty dry-run log folders created during validation
- temporary progress files outside the repo

Do not delete real task-loop logs until the user confirms they are no longer needed.
