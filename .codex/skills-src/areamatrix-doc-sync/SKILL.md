---
name: areamatrix-doc-sync
description: "Use when Codex needs to keep AreaMatrix docs, Core API, UDL, prompt manifests, README files, and generated prompt materials aligned without drifting from the documented source of truth."
---

# AreaMatrix Doc Sync

Use this skill when a change may create drift between product docs, architecture docs, APIs, prompts, or user-facing README files.

Trigger it for changes to `docs/**`, Core API, `core/area_matrix.udl`, prompt manifests, task source docs, README navigation, `.codex` references, repo-local skill navigation, or any generated / adapter text that may drift from the source of truth.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [.ai-governance/README.md](../../../.ai-governance/README.md)
3. [docs/README.md](../../../docs/README.md)
4. [workflow/versions/v1-mvp/execution/README.md](../../../workflow/versions/v1-mvp/execution/README.md) when prompts or manifests are involved.
5. [workflow/residuals/README.md](../../../workflow/residuals/README.md) when a change affects blocker/reference/template/task residual status.

## References

- [references/source-map.md](references/source-map.md): source-of-truth layering and update targets.
- [references/drift-checklist.md](references/drift-checklist.md): drift checks for docs, API, UDL, manifest, README, and `.codex`.
- [../areamatrix-file-safety/SKILL.md](../areamatrix-file-safety/SKILL.md): file-safety invariants when docs or prompts mention user files, metadata, import, recovery, reindex, FSEvents, or iCloud.
- [../areamatrix-workflow-planning/SKILL.md](../areamatrix-workflow-planning/SKILL.md): v* workflow docs are planning artifacts until promoted.
- [../areamatrix-validation-driver/SKILL.md](../areamatrix-validation-driver/SKILL.md): choose checks after drift fixes.
- [../areamatrix-residual-ledger/SKILL.md](../areamatrix-residual-ledger/SKILL.md): residual ledger is an index layer and must point back to authoritative docs, evidence, or closeout sources.

## Workflow

1. Identify the source document for the changed behavior before editing adapters or summaries.
2. Load the source map to decide which files are authoritative.
3. Load the drift checklist before declaring docs and generated prompt surfaces aligned.
4. For long-lived `docs/**`, `core/**`, README, Core API / UDL, ADR, development, roadmap, or governance text, enforce the long-term source wording rules in `.ai-governance/project/areamatrix-rules.md`: do not introduce current-stage, temporary-delivery, historical-task, mock/placeholder, or old release-track wording into source-of-truth material.
5. Before reporting completion for those surfaces, run a focused `rg` sweep for phase/stage/MVP/local QA/prerelease/milestone/sprint/C*-S*, route-style labels such as `GL-*`, and Chinese execution-period wording such as `核心交付`, `计划交付`, `时间预算`, and `第一刀`; then classify every remaining hit as historical evidence, technical terminology, fixture data, or an item that still needs cleanup.

## Guardrails

- Do not resolve drift by editing only generated or adapter text.
- Do not make `.codex/` the authority for product behavior.
- Do not broaden task scope while syncing docs.
- Do not change product semantics in `.codex/skills-src/**`, `.agents/skills/**`, `.codex/references/**`, or `tasks/backlog/**`; update `docs/**` or `.ai-governance/**` first when the source rule itself changes.
- Do not make `workflow/residuals/**` the only place where product behavior, release evidence, or task state is defined.
- Do not treat `preview`, transactional `staging` / `staged`, Xcode `Build Phase`, macOS beta testing, DB/API/schema/dependency versions, UUID v4, or alpha/beta fixture values as stage pollution unless the surrounding context describes a current release track, current delivery phase, or current task status.
- Do not remove historical evidence references such as `workflow/versions/v1-mvp/**` when the surrounding text clearly marks them as archived evidence and not a current template or current execution state.
