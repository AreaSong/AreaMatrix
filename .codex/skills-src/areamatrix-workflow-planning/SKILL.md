---
name: areamatrix-workflow-planning
description: "Use when Codex needs to plan AreaMatrix v* workflow versions, discuss docs scope, define middle-layer handoff, or gate prompt draft generation before changes/plans/drafts/queue/promotion."
---

# AreaMatrix Workflow Planning

Use this skill before turning a large feature, version, refactor, or optimization into executable prompts.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [workflow/AGENTS.md](../../../workflow/AGENTS.md)
3. [workflow/README.md](../../../workflow/README.md)
4. [workflow/templates/README.md](../../../workflow/templates/README.md)
5. [tasks/prompts/README.md](../../../tasks/prompts/README.md) when prompt drafts or live queue boundaries are involved.

## References

- [references/discussion-gate.md](references/discussion-gate.md): required discussion files and approval checks.
- [references/version-lifecycle.md](references/version-lifecycle.md): v* lifecycle from docs to promotion preview.

## Workflow

1. Start from `docs/` as source of truth, then identify the v* version and feature intent.
2. Use `./dev workflow init --version <version>` to create or preview a new version skeleton.
3. Ensure `workflow/versions/<version>/discussion/` exists for new versions.
4. Review `docs-discussion.md` for Exact Docs, user paths, non-goals, contention points, and acceptance boundary.
5. Review `middle-layer-discussion.md` for how changes, plans, drafts, queue, and promotion preview will carry the feature.
6. Review `decisions.yaml`; do not enter `changes/` until `allow_changes: true` and blockers/open questions are resolved or explicitly deferred.
7. Run `./dev workflow discuss --version <version> doctor`, then `./dev workflow doctor`.

## Guardrails

- Do not write `tasks/prompts/**` from discussion, plan, queue, or promotion preview work.
- Do not treat promotion preview as live promote/apply.
- Do not use workflow docs as the product source of truth; product behavior remains in `docs/`.
- Do not bypass the discussion gate for new versions just because a change YAML can be written.
- Keep this skill focused on planning and gates; use `areamatrix-doc-sync` for drift checks.
