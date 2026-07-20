---
name: areamatrix-codex-os
description: "Use when the task operates the AreaMatrix Codex Operating System lifecycle: intake, local task registry, preflight, context, resume, validation recommendation, evidence, closeout, finish, dashboard, health score, weekly review, or archive recommendations. Trigger phrases include codex-os / start-flow / close-flow / 收尾 / 台账 / 健康分 / weekly review."
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
2. Prefer `./dev codex-os go --title "<title>" --apply` for low-friction daily work, or `./dev codex-os flow --task-id <task-id> --changed --profile auto --execute --write` when explicit task IDs are known; use `start-flow` only when the flow needs step-by-step diagnosis.
3. Use `./dev codex-os subagent-plan` to structure code, docs/governance, validation, and risk scans when the user asks for subagents or parallel agent work.
4. Use `./dev codex-os run-validation --task-id <task-id> --changed --profile auto|minimal|standard|full` to preview validation and `--execute --write` only when fresh validation should actually run.
5. Use `./dev codex-os repair-plan --task-id <task-id> --changed` after failed preflight, failed validation, missing evidence, stale fingerprint, unrun checks, profile gaps, or lifecycle drift.
6. Use `./dev codex-os now --task-id <task-id>` to inspect readiness and completion confidence, then `./dev codex-os done --task-id <task-id>` or `close-flow --status Done --from-latest-validation --write` after latest executed PASS validation, a matching validation fingerprint, and usable evidence / closeout.
7. Use `./dev codex-os todo`, `ops-flow --compact`, or `ops-flow --action-items --write` for archive-review, title-suggestions, weekly review, health score, manual review queue, registry audit, advisory action items, and review cards.
8. Fall back to the lower-level commands `context`, `resume`, `preflight`, `recommend-validation`, `evidence`, `closeout`, and `finish` when a flow needs step-by-step diagnosis.

## Guardrails

- Do not create a second runner, queue, progress file, promotion flow, or checkpoint system.
- Do not write `workflow/versions/<version>/execution/**` from Codex OS work.
- Do not write Codex internal SQLite; thread health reads must remain read-only.
- Do not archive threads automatically unless the user explicitly asks to perform an archive operation through the proper thread tool.
- Do not treat `.codex/runtime/codex-os/**` as product source truth or submitted completion evidence.
- Do not let subagent output replace fresh validation run and reviewed by the main agent.
- Do not treat `run-validation` dry-run output as completion evidence; only executed fresh validation can support `Done`.
- Do not use registry recommendations as `close-flow --status Done` validation; pass an explicit fresh PASS / OK result or use the strict same-task `--from-latest-validation` gate.
- Do not close from an older PASS when the same task has a newer dry-run, FAIL, BLOCKED, NOT-READY, or stale-fingerprint validation report.
- Do not treat `ops-flow --action-items` as an execution plan that performs actions; it is an advisory checklist only.
