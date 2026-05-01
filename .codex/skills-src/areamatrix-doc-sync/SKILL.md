---
name: areamatrix-doc-sync
description: "Use when Codex needs to keep AreaMatrix docs, Core API, UDL, prompt manifests, README files, and generated prompt materials aligned without drifting from the documented source of truth."
---

# AreaMatrix Doc Sync

Use this skill when a change may create drift between product docs, architecture docs, APIs, prompts, or user-facing README files.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [.ai-governance/README.md](../../../.ai-governance/README.md)
3. [docs/README.md](../../../docs/README.md)
4. [tasks/prompts/README.md](../../../tasks/prompts/README.md) when prompts or manifests are involved.

## References

- [references/source-map.md](references/source-map.md): source-of-truth layering and update targets.
- [references/drift-checklist.md](references/drift-checklist.md): drift checks for docs, API, UDL, manifest, README, and `.codex`.

## Workflow

1. Identify the source document for the changed behavior before editing adapters or summaries.
2. Load the source map to decide which files are authoritative.
3. Load the drift checklist before declaring docs and generated prompt surfaces aligned.

## Guardrails

- Do not resolve drift by editing only generated or adapter text.
- Do not make `.codex/` the authority for product behavior.
- Do not broaden task scope while syncing docs.
