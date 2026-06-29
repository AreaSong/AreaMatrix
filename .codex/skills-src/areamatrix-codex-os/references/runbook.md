# AreaMatrix Codex OS Runbook

## Start

```bash
./dev codex-os go --title "<title>" --apply
./dev codex-os now --task-id <task-id>
./dev codex-os flow --task-id <task-id> --changed --profile standard --execute --write
./dev codex-os start-flow --task-id <task-id> --changed --write
./dev codex-os start-flow --title "<title>" --lane Change --changed --write
```

Use `go` as the low-friction daily entry and `flow` as the explicit aggregate entry. They run start, validation, repair-plan on failure, optional close, and optional ops through the existing Codex OS data paths. They do not create a second runner or touch live workflow execution.
Use `now` for a one-page readiness view before closeout.
Use `./dev codex-os new --lane <lane> --title "<title>" --write` only for a local Codex OS task registry entry. This does not create a live task-loop task.
Use lower-level `context`, `resume`, and `preflight` when start-flow needs step-by-step diagnosis.

## Work

- Quick: small change, minimum validation, evidence, closeout.
- Change: read-only exploration, plan, execute, validate, finish.
- Mission-Critical: explain impact, risk, validation, and rollback; wait for explicit confirmation before writes.
- Explore / Review / Ops: prefer read-only scans and recommendations.

When the user asks for subagents, split read-heavy work into code paths, docs/governance, validation, and risk review. The main agent owns writes, validation interpretation, and final status.

```bash
./dev codex-os subagent-plan --task-id <task-id>
```

`subagent-plan` only recommends read-only delegation prompts and owner boundaries. It does not spawn agents or grant write access.

## Validate

```bash
./dev codex-os run-validation --task-id <task-id> --changed
./dev codex-os run-validation --task-id <task-id> --changed --profile auto --execute --write
./dev codex-os run-validation --task-id <task-id> --changed --profile minimal --execute --write
./dev codex-os run-validation --task-id <task-id> --changed --profile standard --execute --write
./dev codex-os run-validation --task-id <task-id> --changed --profile full --execute --write
```

The first command is dry-run preview only. `--execute` runs allowlisted validation commands and records fresh results. `auto` resolves the profile from changed paths; reports store both requested and resolved profiles. `minimal` is the smallest sufficient set, `standard` is the default, and `full` widens Codex OS / skill / governance gates when the surface requires it. Validation reports include a fingerprint, not-run explanations, and advisory residual prompts. Failed or blocked written reports update local failure knowledge. Dry-run output is not completion evidence.

## Repair

```bash
./dev codex-os repair-plan --task-id <task-id> --changed
```

Use this after failed preflight, failed validation, missing evidence / closeout, stale validation, unrun checks, profile gaps, missing confirmation, or registry drift. It is read-only and can cite local failure knowledge.

## Finish

```bash
./dev codex-os done --task-id <task-id>
./dev codex-os close-flow --task-id <task-id> --status Done --from-latest-validation --write
./dev codex-os close-flow --task-id <task-id> --status Done --validation "<fresh PASS/OK result>" --write
./dev codex-os close-flow --task-id <task-id> --status Blocked --next-action "<next action>" --write
```

`Done` requires an explicit fresh PASS / OK validation string or `--from-latest-validation`. The latest-validation gate accepts only the same task's latest executed `PASS` report where every command passed with exit code 0 and the stored fingerprint still matches current Git / path / command / profile / task-validation state. Registry recommendations, dry-run validation summaries, older PASS after newer failure, and stale fingerprints are rejected. `done` is a safe wrapper for this same close-flow path. `now` and `close-flow` report completion confidence. Written close-flow creates structured evidence / closeout and a short handoff summary. `Blocked` requires next action or handoff. Archive fields are recommendations only.
Use lower-level `evidence`, `closeout`, and `finish` when manual file paths or custom closeout references are needed.

## Operate

```bash
./dev codex-os todo
./dev codex-os ops-flow --write
./dev codex-os ops-flow --compact --write
./dev codex-os ops-flow --action-items --write
./dev codex-os diagnose --task-id <task-id>
```

`todo` is the low-friction action-item view. `ops-flow` is advisory. `--compact` and `--action-items` change rendering only; persisted JSON still contains the full advisory data plus derived action items, review cards, health-score improvement hints, and weekly manual review queue. It does not modify Codex thread titles, archive state, live workflow execution, Codex SQLite, or product source files.
