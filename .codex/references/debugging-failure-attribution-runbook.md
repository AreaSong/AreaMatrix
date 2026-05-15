# AreaMatrix Debugging And Failure Attribution Runbook

Use this runbook when a failure, bug, broken validation, task-loop stop, or drift signal needs root-cause investigation.

This file absorbs the method value of Vibe-Skills `systematic-debugging` without installing it, copying its repository, or creating a same-name repo-local skill.

## Core Rule

原因不明时先复现、收证、提出单一假设、缩小范围，再修复。

Do not patch from a guess. A symptom-level fix is not enough when the failing layer is still unknown.

## Investigation Flow

1. Reproduce the failure.
   Record the exact command, task label, phase, environment flags, and whether the failure is deterministic.

2. Collect evidence before changing files.
   Read the full error, stack trace, verify report, task-loop summary, and relevant logs. For multi-layer failures, inspect each boundary instead of jumping to the deepest symptom.

3. Classify the failing layer.
   Decide whether the failure belongs to copy, verify, validation command, runner, Git checkpoint, docs/API/UDL/prompt drift, or file-safety risk.

4. Form one hypothesis.
   State it as: "I think `<root cause>` because `<evidence>`." Keep it specific enough to falsify.

5. Test the smallest useful boundary.
   Use the narrowest command, diff check, log excerpt, or reproduction that can confirm or reject the hypothesis.

6. Fix the root cause.
   Make one scoped fix. Do not bundle unrelated cleanup or refactors into the same debugging pass.

7. Verify the original failure and nearby risk.
   Re-run the command that failed first, then add the smallest sufficient validation set from `areamatrix-validation-driver`.

If three fix attempts fail or each fix reveals a different shared-state problem, stop treating it as a local bug. Reopen the architecture, workflow, or owner boundary before making another change.

## Failure Layers

| Layer | Primary signal | First evidence to inspect | Owner skill |
|---|---|---|---|
| copy stage | copy log exits non-zero, no useful implementation diff, task remains `in_progress` or `failed` before verify can prove anything | `copy_log`, copy prompt, task file, manifest section, newest diff | `areamatrix-task-loop`; add `areamatrix-validation-driver` after a fix |
| verify stage | verify log lacks `VERIFY_RESULT: PASS`, or reports `VERIFY_RESULT: FAIL` with functional / validation / engineering blockers | `verify_log`, failure summary before final result line, next repair context | `areamatrix-task-loop` |
| validation command | a lint, build, test, doctor, check, xcodebuild, or cargo command fails | exact command output, manifest `Validation`, changed paths, environment | `areamatrix-validation-driver` |
| task-loop runner | status, lock, progress, stale state, dry-run, retry, or summary behavior is wrong | `./task-loop status`, `./dev status --verbose`, `progress.json`, run summary, runner logs | `areamatrix-task-loop` |
| Git checkpoint / dirty worktree | verify passed but runner stops before next task; checkpoint fields show Git failure; worktree is dirty unexpectedly | `git status --short`, `git diff --check`, progress Git fields, summary, checkpoint log lines | `areamatrix-git-checkpoint` |
| docs / API / UDL / manifest drift | docs, `core-api.md`, UDL, generated prompt materials, README, or manifest disagree | authoritative `docs/**` / `.ai-governance/**`, affected generated or adapter text, prompt doctor output | `areamatrix-doc-sync` |
| user file / DB / staging / iCloud / FSEvents risk | failure can delete, move, overwrite, rename, migrate, reindex, recover, or download user-controlled data | file-safety docs, acceptance checklist, rollback notes, dry fixture evidence | `areamatrix-file-safety` |

## Task-Loop Attribution Order

When `./task-loop` or `./dev` reports a failed, blocked, stale, or stopped run, inspect in this order:

1. `./dev status --verbose`
   Use this for the operator-facing current state, latest task, latest verify excerpt, runner lock, process snapshot, and recovery hints.

2. `./task-loop status`
   Use this to cross-check progress counts, `lock_alive`, stale detection, latest log directory, and live runner status.

3. `tasks/prompts/_shared/progress.json`
   Treat this as the primary progress source. For the affected task, inspect `status`, `note`, `attempts`, `risk`, `run_id`, `copy_log`, `verify_log`, `git_checkpoint_status`, `git_push_status`, `git_branch`, `git_commit`, and `git_changed_files`.

4. `.codex/task-loop-runs/index.json`
   Find the latest `run_id`, `status`, `summary_file`, `completed`, `retries`, `exit_code`, `started_at`, and `finished_at`.

5. `.codex/task-loop-runs/<run_id>/summary.json`
   Inspect run-level `status`, `exit_code`, `note`, `totals`, phase / start filters, risk policy, Git mode, and per-task `copy_log` / `verify_log` paths.

6. `.codex/task-loop-logs/<timestamp>/<phase>/`
   Open the affected `*-copy-attempt-<n>.log` first when copy failed or no verify evidence exists. Open `*-verify-attempt-<n>.log` first when verify ran and produced blockers.

7. Git evidence.
   If verify passed but the run stopped, inspect `git status --short`, `git diff --check`, and the progress Git fields before deciding the task itself failed.

Do not edit `progress.json`, summaries, or logs during attribution unless the user explicitly requested state repair.

## Layer-Specific Notes

### Copy Stage

Copy failure means the implementation step itself did not produce a usable task attempt. Check whether:

- `copy_log` exists and contains an execution error.
- the task's `Allowed` and `Forbidden` paths were followed.
- the copy prompt received a previous verify failure summary on retry.
- the resulting diff matches the task manifest and did not touch live runtime state.

Only after this should you edit implementation files.

### Verify Stage

Verify failure means the read-only acceptance step did not prove the task complete. Check whether:

- the verify log includes a concrete blocker before `VERIFY_RESULT: FAIL`.
- the blocker is functional, validation-related, or engineering-quality-related.
- the failure is caused by missing evidence rather than broken implementation.
- the retry prompt will receive enough failure detail to repair the task.

Do not mark completed without `VERIFY_RESULT: PASS`.

### Validation Command

Validation failure belongs to the command that failed, not automatically to the feature. Use `areamatrix-validation-driver` to decide whether the correct next step is:

- rerun the same command after reading the full output,
- narrow to a failing test / lint / doctor subcheck,
- widen because the change crosses Core, macOS, prompt runtime, governance, or file-safety boundaries,
- report `BLOCKED` because the environment cannot run a required command.

### Runner Failure

Runner failure means the automation machinery, not the task content, may be broken. Suspect this when:

- `./task-loop check` fails.
- stale detection, lock state, run summaries, dry-run behavior, or resume behavior is inconsistent.
- copy and verify logs are missing despite the runner recording attempts.
- `progress.json` and run summaries disagree about a current task.

Use temporary state and dry-run checks for runner diagnostics before touching live progress.

### Git Checkpoint Or Dirty Worktree

Checkpoint failure is a separate gate after verify. A task can have `VERIFY_RESULT: PASS` and still fail the overall loop because Git evidence cannot be written safely.

Use `areamatrix-git-checkpoint` when you see:

- `git_checkpoint_status=git_diff_check_failed`
- `git_checkpoint_status=git_push_failed` or `git_push_status` failure
- an unexpected dirty worktree before start or after PASS
- local-ahead commits, branch-policy questions, or push credentials failures

Do not clear completed progress to bypass checkpoint evidence.

### Docs / API / UDL / Prompt Drift

Use `areamatrix-doc-sync` when the failure is caused by disagreement between source facts and adapter surfaces:

- `docs/api/core-api.md` vs `core/area_matrix.udl`
- product / architecture docs vs implementation
- prompt manifest vs task files
- `.ai-governance/**` vs `.codex/**` references or repo-local skills
- README navigation vs actual paths

Fix the source-of-truth layer first when semantics changed. Do not resolve drift only by editing generated or adapter text.

### File-Safety Boundary

Use `areamatrix-file-safety` before changing or recovering behavior near:

- user file deletion, movement, overwrite, or rename
- non-empty folder adoption
- DB schema, migration, rollback, or data repair
- staging recovery and transactional import
- reindex, FSEvents, iCloud placeholder handling
- generated overview output such as `.areamatrix/generated/`

For these failures, pause for impact, risk, validation, and rollback unless the user already authorized silent Mission-Critical execution through the task-loop risk policy.

## Reporting Format

When reporting a debugging result, include:

```text
归因层:
- <copy / verify / validation / runner / checkpoint / drift / file-safety>

证据:
- <commands, files, logs, fields>

根因假设:
- <single falsifiable hypothesis>

已验证:
- <what confirmed or rejected the hypothesis>

修复:
- <scoped change or not yet changed>

复验:
- <commands actually run>

结论:
- PASS / FAIL / BLOCKED
```

Avoid phrases such as `应该是`, `看起来像`, or `先试试`. If evidence is incomplete, report the exact missing evidence and keep the result `FAIL` or `BLOCKED`.
