# AreaMatrix Codex OS Runbook

## Start

```bash
./dev codex-os start-flow --task-id <task-id> --changed --write
./dev codex-os start-flow --title "<title>" --lane Change --changed --write
```

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
./dev codex-os run-validation --task-id <task-id> --changed --execute --write
```

The first command is dry-run preview only. `--execute` runs allowlisted validation commands and records fresh results. Dry-run output is not completion evidence.

## Repair

```bash
./dev codex-os repair-plan --task-id <task-id> --changed
```

Use this after failed preflight, failed validation, missing evidence / closeout, missing confirmation, or registry drift. It is read-only.

## Finish

```bash
./dev codex-os close-flow --task-id <task-id> --status Done --validation "<fresh result>" --write
./dev codex-os close-flow --task-id <task-id> --status Blocked --next-action "<next action>" --write
```

`Done` requires validation and evidence or closeout. `Blocked` requires next action or handoff. Archive fields are recommendations only.
Use lower-level `evidence`, `closeout`, and `finish` when manual file paths or custom closeout references are needed.

## Operate

```bash
./dev codex-os ops-flow --write
./dev codex-os diagnose --task-id <task-id>
```

`ops-flow` is advisory. It does not modify Codex thread titles, archive state, live workflow execution, or product source files.
