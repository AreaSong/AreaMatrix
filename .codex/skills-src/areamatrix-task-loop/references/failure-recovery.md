# AreaMatrix Task Loop Failure Recovery

Use this reference when the task loop stops, retries, or reports stale state.

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
bash scripts/run_area_matrix_task_pipeline.sh --status
bash scripts/run_area_matrix_task_pipeline.sh --resume-failed
```

If the failure is conceptual rather than transient, inspect the task file, manifest section, copy log, and verify log before resuming.

## Risk Gate Blocked

Symptoms:

- task status becomes `blocked`
- note says `风险门禁暂停` or `风险门禁跳过`

Action options:

- Continue with explicit approval: `RISK_POLICY=allow START_FROM=<label> bash scripts/run_area_matrix_task_pipeline.sh`
- Keep blocked and report: use when the user has not authorized Mission-Critical execution.
- Skip only if the user requested skip semantics: `RISK_POLICY=skip`.

Do not silently convert `blocked` to `completed`.

## Stale Progress

Symptoms:

- `prompt_pipeline.py status` and expected queue position disagree
- a task is recorded `in_progress` after an interrupted process
- `bash scripts/run_area_matrix_task_pipeline.sh --status` reports `stale_in_progress`

Action:

1. Run `bash scripts/run_area_matrix_task_pipeline.sh --status`.
2. Check whether `lock_alive` is `yes`; if so, do not start a second runner.
3. Inspect `progress.json` entry and the latest copy/verify logs for the affected task.
4. Prefer `bash scripts/run_area_matrix_task_pipeline.sh --resume-stale` over manual JSON edits.
5. If the user wants a clean restart, use `bash scripts/run_area_matrix_task_pipeline.sh --reset-progress`; it backs up progress and preserves logs.

Manual progress edits are allowed only when the user explicitly asks for state repair.

If the stale entry is only an interrupted `in_progress` record and the user does not want to resume it, use:

```bash
bash scripts/run_area_matrix_task_pipeline.sh --clear-stale
```

This removes only stale `in_progress` entries and must not touch `completed`, `failed`, or `blocked`.

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
