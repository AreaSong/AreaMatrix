---
name: areamatrix-codex-os
description: "Use when Codex needs to run, explain, validate, recover, or improve the AreaMatrix Codex Operating System task lifecycle, including intake, local task registry, preflight, context, resume, validation recommendation, evidence, closeout, finish, dashboard, health score, weekly review, and archive recommendations."
---

# AreaMatrix Codex OS

Use this skill for the Codex operating layer. This is not the AreaMatrix product source of truth and not the live task-loop queue.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [.codex/README.md](../../README.md)
3. [.codex/references/codex-operating-system.md](../../references/codex-operating-system.md)
4. [.codex/references/codex-operating-layer-playbook.md](../../references/codex-operating-layer-playbook.md)
5. [.ai-governance/README.md](../../../.ai-governance/README.md)

## References

- [references/runbook.md](references/runbook.md): command lifecycle, automation scope, and closeout rules.
- [../../references/completion-evidence-checklist.md](../../references/completion-evidence-checklist.md): evidence required before done / fixed / deliverable claims.
- [../../references/planning-handoff-runbook.md](../../references/planning-handoff-runbook.md): handoff-safe planning fields.
- [../../references/subagent-boundaries-runbook.md](../../references/subagent-boundaries-runbook.md): subagent owner and write-boundary rules.
- [../areamatrix-validation-driver/SKILL.md](../areamatrix-validation-driver/SKILL.md): choose the smallest sufficient validation set.
- [../areamatrix-task-loop/SKILL.md](../areamatrix-task-loop/SKILL.md): use only when live task-loop state is involved.

## Workflow

1. Classify the lane: Quick, Change, Mission-Critical, Explore, Review, or Ops.
2. Prefer `./dev codex-os start-flow --task-id <task-id> --changed --write` before continuing registered work; use `--title` and `--lane` when creating a local registry entry.
3. Use `./dev codex-os subagent-plan` to structure code, docs/governance, validation, and risk scans when the user asks for subagents or parallel agent work.
4. Use `./dev codex-os run-validation --task-id <task-id> --changed` to preview validation and `--execute --write` only when fresh validation should actually run.
5. Use `./dev codex-os repair-plan --task-id <task-id> --changed` after failed preflight, failed validation, missing evidence, or lifecycle drift.
6. Use `./dev codex-os close-flow --task-id <task-id> --status Done --validation "<fresh result>" --write` to write evidence / closeout and update finish fields.
7. Use `./dev codex-os ops-flow --write` for archive-review, title-suggestions, weekly review, health score, and registry audit recommendations.
8. Fall back to the lower-level commands `context`, `resume`, `preflight`, `recommend-validation`, `evidence`, `closeout`, and `finish` when a flow needs step-by-step diagnosis.

## Guardrails

- Do not create a second runner, queue, progress file, promotion flow, or checkpoint system.
- Do not write `workflow/versions/<version>/execution/**` from Codex OS work.
- Do not write Codex internal SQLite; thread health reads must remain read-only.
- Do not archive threads automatically unless the user explicitly asks to perform an archive operation through the proper thread tool.
- Do not treat `.codex/runtime/codex-os/**` as product source truth or submitted completion evidence.
- Do not let subagent output replace fresh validation run and reviewed by the main agent.
- Do not treat `run-validation` dry-run output as completion evidence; only executed fresh validation can support `Done`.
