# AreaMatrix Drift Checklist

Use this checklist before declaring docs, API, UDL, prompts, and Codex materials aligned.

## Product Or Architecture Drift

- Does the changed behavior have an authoritative doc under `docs/`?
- Do README files only summarize or navigate to the authoritative doc?
- Are ADRs historical records rather than the only current rule?
- If behavior changed, did tests or prompt tasks reference the updated source?

## Core API And UDL Drift

- If `docs/api/core-api.md` changed, does `core/area_matrix.udl` need matching updates?
- If UDL changed, do Rust types and Swift bridge expectations match?
- Are error codes documented where user-visible behavior depends on them?
- Did validation cover the affected Core command or task-specific test?

## Prompt Boundary Drift

- Does the task file match the manifest `source task`?
- Do `Exact Docs`, `Existing Code`, `Expected New Paths`, `Forbidden Touches`, `Risk Level`, and `Validation` still match the task scope?
- Does `copy-ready` allow edits only in the expected scope?
- Does `verify-ready` remain read-only and strict?
- After prompt or manifest changes, did `doctor` pass?

## README And Codex Drift

- README files should not become deeper than `docs/`.
- `.codex/` should not define business behavior absent from `docs/` or `.ai-governance/`.
- Skill changes should point to source docs instead of duplicating long specs.
- `.agents/skills` must remain a projection, not a second source.

## Final Evidence

Report:

- files checked
- drift found or not found
- commands run
- remaining alignment risk
