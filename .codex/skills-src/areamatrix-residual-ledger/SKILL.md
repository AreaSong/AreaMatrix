---
name: areamatrix-residual-ledger
description: "Use when Codex needs to inspect, explain, update, or cross-check AreaMatrix residual items such as release blockers, accepted exceptions, historical references, template-only blockers, closed backlog packages, or docs terms that look unfinished but are product states."
---

# AreaMatrix Residual Ledger

Use this skill to answer “what remains unresolved?” without confusing product docs, release evidence, historical references, templates, backlog, and live tasks.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [workflow/residuals/README.md](../../../workflow/residuals/README.md)
3. [workflow/residuals/schema.md](../../../workflow/residuals/schema.md)
4. [workflow/residuals/residuals.yaml](../../../workflow/residuals/residuals.yaml)
5. [tasks/indexes/residuals.md](../../../tasks/indexes/residuals.md) when the user asks whether a residual is a task.
6. `workflow/versions/<version>/residuals/README.md` and `residuals.yaml` when a version is named.

## Workflow

1. Classify the question: current task, release evidence, closeout exception, historical reference, template reference, backlog reference, or product-doc marker.
2. Load [references/classification-guide.md](references/classification-guide.md) before deciding whether something can become a task.
3. Start from the residual ledger, then open the linked source file for authoritative details.
4. Report the residual `id`, `status`, `type`, source file, current impact, and close condition.
5. For broad questions such as "what remains unresolved?", report the full residual ID inventory from `workflow/residuals/README.md`, not only the current release blockers. Include `reference-only`, `template-only`, `accepted-exception`, closed backlog references, and product-doc markers as a separate "indexed but not current tasks" group.
6. Treat the machine-readable full inventory as global `items` plus every `version_residuals[].source` `items`; do not read only top-level YAML items.
7. Phrase the conclusion as two scopes: current blockers / executable task state, and full residual ledger state. Do not say or imply that release blockers are the only residual items.
8. If a user wants implementation work, check `executable_task` before suggesting `tasks/active/**` or workflow promotion.
9. Keep discussion-period open questions in `workflow/versions/<version>/discussion/decisions.yaml`; create version residuals only for durable blocked, deferred, accepted-exception, reference-only, or template-only states.
10. If updating residuals, update the authoritative source first, then the version residual index, then the global residual ledger; update `tasks/indexes/residuals.md` only when the task-facing answer changes.

## Guardrails

- Residual ledger is index-only; do not make it product source of truth.
- Do not move product docs, release evidence, closeout records, or historical prompt files just to centralize them.
- Do not turn `reference-only`, `template-only`, or `accepted-exception` items into live tasks.
- Do not write `workflow/versions/<version>/execution/**`, `progress.json`, task-loop logs, run summaries, runner locks, checkpoint state, branches, commits, or tags from this skill.
- Do not close release blockers based on local QA, ad-hoc signing, same-machine smoke, dry-run, or self-report; use the linked release evidence source.
- Do not rewrite historical `progress.json`, Git history, copy logs, verify logs, or run summaries to fix accepted exceptions.

## Validation

- For ledger-only changes, run `./dev workflow doctor`, `./dev tasks status`, `./dev check skills`, and `git diff --check`.
- If `.codex/skills-src/**` changed, also run `./dev check prompts`.
- If governance files changed, run `./dev check governance`.
