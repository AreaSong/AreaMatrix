# AreaMatrix Source Map

Use this map to decide what file is authoritative before synchronizing docs or generated runtime materials.

## Source Layers

| Layer | Source | Purpose |
|---|---|---|
| Product and architecture | `docs/` | Product behavior, architecture, APIs, UX, testing. |
| AI governance | `.ai-governance/` | Collaboration rules, workflow semantics, project invariants. |
| Prompt tasks | `tasks/prompts/` | Executable task boundaries, manifests, copy-ready and verify-ready prompts. |
| Codex runtime | `.codex/` | Codex-only templates, references, skills, and local run material. |
| Discovery projection | `.agents/skills/` | Symlink entrypoints for repo-local skills. |
| User-facing summaries | `README.md`, `README.zh-CN.md` | Navigation and overview, not detailed behavior SSOT. |

## Core API Order

For public Core API changes:

1. `docs/api/core-api.md`
2. `core/area_matrix.udl`
3. Rust implementation under `core/`
4. Swift bridge under `apps/macos/`
5. Prompt task and manifest updates if execution boundaries changed

## Prompt Task Order

For prompt task changes:

1. task file under `tasks/prompts/phase-*`
2. matching manifest section under `tasks/prompts/_shared/manifests/`
3. shared rules only when the rule applies across many tasks
4. rendered `copy-ready` / `verify-ready` outputs

Do not edit rendered prompt artifacts as the only source of truth.

## Codex Materials

`.codex/` may explain how Codex should work. It must not become the only place where product behavior, API behavior, or safety invariants are defined.

When `.codex/skills-src` changes:

- keep `.agents/skills` symlinks valid
- update `.codex/references/index.md` only if navigation changed
- run `bash scripts/check-skills.sh`
