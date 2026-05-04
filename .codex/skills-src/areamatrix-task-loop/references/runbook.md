# AreaMatrix Task Loop Runbook

Use this runbook when starting, monitoring, or explaining the automated copy-ready / verify-ready task loop.

## Preflight

Run these before live execution:

```bash
bash scripts/check-task-loop.sh
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
python3 tasks/prompts/_shared/prompt_pipeline.py status
bash scripts/run_area_matrix_task_pipeline.sh --status
```

Check that:

- `doctor` is `OK`.
- `check-task-loop` is `OK`; it uses temporary state and must not change real progress.
- `status` shows the expected first pending task.
- live Git checkpoint mode has a clean worktree before execution.
- copy-ready / verify-ready prompts have been regenerated after shared rule changes.
- `progress_file` is `tasks/prompts/_shared/progress.json`.
- `lock_alive` is not `yes` unless the operator intentionally has a runner active.
- `latest_log_dir` is understood; `None` is fine before the first run.

## Execution Modes

For day-to-day operation, prefer the root console:

```bash
./dev.sh
```

It shows task-loop status, runner and `codex exec` process counts, and menu actions for resume, drain, checks, and logs without requiring long command recall.
Before starting or resuming, the console blocks duplicate live runners and asks for foreground/background execution, Git mode, task count, and optional stop targets.

| Mode | Command | Use when |
|---|---|---|
| Cautious default | `MAX_RETRIES=0 bash scripts/run_area_matrix_task_pipeline.sh` | The run should pause at `Mission-Critical` tasks. |
| Full silent | `RISK_POLICY=allow MAX_RETRIES=0 bash scripts/run_area_matrix_task_pipeline.sh` | The user explicitly authorized unattended execution through all risk levels. |
| No Git checkpoint | `GIT_CHECKPOINT=off MAX_RETRIES=0 bash scripts/run_area_matrix_task_pipeline.sh` | Temporary infrastructure diagnostics only. |
| Push checkpoints | `GIT_CHECKPOINT=push RISK_POLICY=allow MAX_RETRIES=0 bash scripts/run_area_matrix_task_pipeline.sh` | Commit and upload each PASS task after remote credentials are ready. |
| One phase | `MAX_RETRIES=0 bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1` | Validate a phase-sized slice. |
| Stop after task | `MAX_RETRIES=0 bash scripts/run_area_matrix_task_pipeline.sh --stop-after 2-1/task-18` | Stop after the target task passes and checkpoints. |
| Small trial | `MAX_RETRIES=1 bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1 --max-tasks 1` | Prove live behavior on one task. |
| Dry run | `DRY_RUN=1 DRY_RUN_RESULT=PASS bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1 --max-tasks 1` | Prove runner wiring without executing Codex. |
| Graceful drain | `bash scripts/run_area_matrix_task_pipeline.sh --request-drain` | Ask the live runner to finish the current task, checkpoint it, and stop before the next task. |

Dry-run proves only runner flow. It does not prove implementation, verification, engineering quality, or task completion.

`RISK_POLICY=allow` injects an explicit silent-approval context into copy-ready runs. The agent should still record risk, validation, and rollback notes, but should not pause for High / Mission-Critical confirmation unless the task would delete, move, overwrite, or otherwise destructively modify real user files.

## Graceful Drain

Use drain when the machine needs to shut down, token budget is nearly exhausted, or the operator wants a clean pause without leaving a half-finished `in_progress` task:

```bash
bash scripts/run_area_matrix_task_pipeline.sh --request-drain
bash scripts/run_area_matrix_task_pipeline.sh --status
```

The same operation is available from `./dev.sh` as menu item `5`, or non-interactively:

```bash
./dev.sh drain
```

`--request-drain` requires a live runner lock. It writes a local control request under `.codex/task-loop-control/`; that directory is not workflow evidence and stays ignored by git.

The active runner checks the request only after the current task reaches `VERIFY_RESULT: PASS`, writes progress, runs the configured Git checkpoint or push, records run summary/index, and then exits with status `drained`. It does not skip verify, bypass repair retries, or advance into the next task.

## Skill Paths

Repo-local skills live in this repository:

```text
.codex/skills-src/<skill>/SKILL.md
.agents/skills/<skill>/SKILL.md
```

Do not use `/Users/as/.codex/skills-src/<skill>/SKILL.md`; that is not the AreaMatrix repo-local source.

## Start Points

Use no `START_FROM` for the first eligible task in phase order.

Use either format for explicit start:

```bash
START_FROM=phase-1/1-1-task-01 bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1
START_FROM=1-1/task-01 bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1
```

The canonical progress label is `1-1/task-01`. The `phase-1/1-1-task-01` form is accepted for operator convenience.

## Progress State

Primary progress:

```text
tasks/prompts/_shared/progress.json
```

Expected statuses:

- `pending`: no completed, failed, blocked, or in-progress record.
- `in_progress`: a live run started this task.
- `completed`: verify log contained `VERIFY_RESULT: PASS`.
- `failed`: retry limit or dry-run fail limit was reached.
- `blocked`: risk gate paused or skipped the task.
- `stale_in_progress`: status output only; an `in_progress` record has no active matching lock and no PASS verify log.

State operations:

```bash
bash scripts/run_area_matrix_task_pipeline.sh --reset-progress
bash scripts/run_area_matrix_task_pipeline.sh --clear-stale
bash scripts/run_area_matrix_task_pipeline.sh --resume-stale
```

`--reset-progress` backs up `progress.json` under `.codex/task-loop-progress-backups/` before writing an empty progress file. It does not delete task-loop logs.

`--clear-stale` removes only stale `in_progress` records. It must not alter `completed`, `failed`, or `blocked`.

`--resume-stale` starts from the first stale task label.

## Lock And Run Summary

Runner lock:

```text
.codex/task-loop-lock/
```

The lock records `pid`, `run_id`, operation, command, and start time. It is local coordination state and should stay ignored by git.

Run summaries:

```text
.codex/task-loop-runs/<run_id>/summary.json
.codex/task-loop-runs/index.json
```

The summary records model, reasoning effort, phase filter, start/max settings, risk policy, progress file, log root, task attempts, copy/verify logs, final status, and exit code. Treat it as resumable workflow evidence.

`index.json` records the latest run summaries and should stay tracked with other task-loop evidence.

State helper:

```text
scripts/task_loop_state.py
```

The shell runner delegates progress, stale, status fragments, summary, and index writes to this helper. Keep it standard-library only.

Git helper:

```text
scripts/task_loop_git.py
```

Live runs default to `GIT_CHECKPOINT=commit`. A PASS task creates a task completion commit and a small evidence commit that records the completion commit hash in progress and summary. A successful run may also create a final run-summary commit so the worktree stays clean.

If the current branch is `main`, `GIT_BRANCH_POLICY=auto` creates `codex/areamatrix-task-loop-<run_id>` before task output is written.

Legacy state:

```text
.codex/task-loop-state.txt
```

Treat it as compatibility input only. Do not write new progress there.

## Logs

Logs live under:

```text
.codex/task-loop-logs/<timestamp>/<phase>/
```

Per attempt:

- `*-copy-attempt-<n>.log`
- `*-verify-attempt-<n>.log`

When reporting a task-loop result, include the task label, attempt count, copy log path, verify log path, and final status.
Verify logs should keep a concise report before the final `VERIFY_RESULT` line so retry prompts can repair functional, validation, and engineering-quality failures.

## Operator Output

For live runs, summarize:

- command used
- start task or phase
- risk mode
- completed count
- failed or blocked task, if any
- latest log directory
