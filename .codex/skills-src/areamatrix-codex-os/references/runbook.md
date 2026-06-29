# AreaMatrix Codex OS Runbook

## Start

```bash
./dev codex-os status
./dev codex-os context
./dev codex-os resume
./dev codex-os preflight --task-id <task-id> --strict
```

Use `./dev codex-os new --lane <lane> --title "<title>" --write` only for a local Codex OS task registry entry. This does not create a live task-loop task.

## Work

- Quick: small change, minimum validation, evidence, closeout.
- Change: read-only exploration, plan, execute, validate, finish.
- Mission-Critical: explain impact, risk, validation, and rollback; wait for explicit confirmation before writes.
- Explore / Review / Ops: prefer read-only scans and recommendations.

When the user asks for subagents, split read-heavy work into code paths, docs/governance, validation, and risk review. The main agent owns writes, validation interpretation, and final status.

## Validate

```bash
./dev codex-os recommend-validation
```

This command recommends checks only. Run chosen commands explicitly, then record fresh results in evidence or finish fields.

## Finish

```bash
./dev codex-os evidence --task-id <task-id> --write
./dev codex-os closeout --task-id <task-id> --write
./dev codex-os finish --task-id <task-id> --status Done --validation "<fresh result>" --evidence-file <path> --closeout-file <path> --write
```

`Done` requires validation and evidence or closeout. `Blocked` requires next action or handoff. Archive fields are recommendations only.

## Operate

```bash
./dev codex-os archive-review --write
./dev codex-os title-suggestions --write
./dev codex-os weekly --write
./dev codex-os health-score --write
./dev codex-os diagnose --task-id <task-id>
```

These commands are advisory. They do not modify Codex thread titles, archive state, live workflow execution, or product source files.
