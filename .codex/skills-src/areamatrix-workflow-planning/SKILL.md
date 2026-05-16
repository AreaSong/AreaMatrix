---
name: areamatrix-workflow-planning
description: "Use when Codex needs to plan AreaMatrix v* workflow versions, discuss docs scope, define middle-layer handoff, or gate prompt draft generation before changes/plans/drafts/queue/promotion."
---

# AreaMatrix Workflow Planning

Use this skill before turning a large feature, version, refactor, or optimization into executable prompts.

Trigger it for new `v*` versions, discussion gate decisions, workflow templates, Exact Docs scope, middle-layer handoff, `changes/`, `plans/`, `drafts/`, queue candidates, promotion preview, or any request to create future prompt tasks before they enter the live queue.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [.ai-governance/workflows/external-capability-admission.md](../../../.ai-governance/workflows/external-capability-admission.md) when external Codex capabilities, Vibe-Skills, plugins, MCP, Cloud, Automations, Worktrees, or new runtimes are involved.
3. [workflow/AGENTS.md](../../../workflow/AGENTS.md)
4. [workflow/README.md](../../../workflow/README.md)
5. [workflow/templates/README.md](../../../workflow/templates/README.md)
6. [tasks/backlog/README.md](../../../tasks/backlog/README.md) when backlog prompt packages are involved.
7. [tasks/prompts/README.md](../../../tasks/prompts/README.md) when prompt drafts or live queue boundaries are involved.

## References

- [references/discussion-gate.md](references/discussion-gate.md): required discussion files and approval checks.
- [references/version-lifecycle.md](references/version-lifecycle.md): v* lifecycle from docs to promotion preview.
- [../../references/planning-handoff-runbook.md](../../references/planning-handoff-runbook.md): handoff-safe planning fields, copy-ready / verify-ready split, and backlog boundary.
- [../../references/codex-automations-cloud-worktrees-gate.md](../../references/codex-automations-cloud-worktrees-gate.md): Automations / Cloud / Worktrees trigger conditions, forbidden writes, owners, and validation.
- [../areamatrix-doc-sync/SKILL.md](../areamatrix-doc-sync/SKILL.md): source-of-truth alignment for docs and planning artifacts.
- [../areamatrix-task-loop/SKILL.md](../areamatrix-task-loop/SKILL.md): live execution begins only after approved promotion into `tasks/prompts/**`.

## Workflow

1. Start from `docs/` as source of truth, then identify the v* version and feature intent.
2. Use `./dev workflow init --version <version>` to create or preview a new version skeleton.
3. Ensure `workflow/versions/<version>/discussion/` exists for new versions.
4. Review `docs-discussion.md` for Exact Docs, user paths, non-goals, contention points, and acceptance boundary.
5. Review `middle-layer-discussion.md` for how changes, plans, drafts, queue, and promotion preview will carry the feature.
6. Review `decisions.yaml`; do not enter `changes/` until `allow_changes: true` and blockers/open questions are resolved or explicitly deferred.
7. For every plan, draft, queue candidate, or backlog prompt package, require goal, non-goals, source of truth, owner / landing, exact file paths, ordered steps, validation commands, and blocked / rollback wording.
8. Keep copy-ready implementation prompts and verify-ready read-only acceptance prompts as separate artifacts.
9. Run `./dev workflow discuss --version <version> doctor`, then `./dev workflow doctor`.

## Guardrails

- Do not write `tasks/prompts/**` from discussion, plan, queue, or promotion preview work.
- Do not treat promotion preview as live promote/apply.
- Do not use workflow docs as the product source of truth; product behavior remains in `docs/`.
- Do not let backlog prompt packages write live progress, checkpoint state, run summaries, or `tasks/prompts/_shared/progress.json`.
- Do not collapse copy-ready and verify-ready into one prompt; implementation and acceptance evidence must remain separable.
- Do not bypass the discussion gate for new versions just because a change YAML can be written.
- Keep this skill focused on planning and gates; use `areamatrix-doc-sync` for drift checks.
- Do not reuse global live task labels for future versions; keep version-local numbering until an explicit promotion mapping exists.
