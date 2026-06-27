# AreaMatrix Drift Checklist

Use this checklist before declaring docs, API, UDL, prompts, and Codex materials aligned.

## Product Or Architecture Drift

- Does the changed behavior have an authoritative doc under `docs/`?
- Do README files only summarize or navigate to the authoritative doc?
- Are ADRs historical records rather than the only current rule?
- If behavior changed, did tests or prompt tasks reference the updated source?
- Do long-lived source files avoid current `stage` / `phase` / `MVP` / `local-qa` / `unnotarized` / `prerelease` / `release gate` / `alpha` / `beta` / `milestone` / `iteration` / `sprint` / `C1-C4` / `S1-S4` naming unless the hit is policy inventory, concentrated archived evidence, fixture data, or a legitimate technical term?
- Do Chinese source docs avoid execution-period wording such as `本任务`, `对应版本任务`, `任务补齐`, `implementation 任务`, `后续 apply 行为`, `临时 mock`, `静态占位`, `假数据`, `交付期`, `临时版本`, `进入对应阶段`, `核心交付`, `计划交付`, `时间预算`, `第一刀`, and `GL-*` route labels?
- Do docs and README route historical details through neutral archive entrypoints instead of scattering deep historical paths or old distribution names?
- After edits, did the agent run `./dev check wording` or `./dev wording audit --show-allowed` and classify remaining hits as policy inventory, archived evidence, legal technical semantics, fixture data, or cleanup work?

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
- If residual wording changed, do `workflow/residuals/README.md`, `workflow/residuals/schema.md`, `workflow/residuals/residuals.yaml`, version residual indexes, `tasks/indexes/residuals.md`, and README navigation still agree?

## Final Evidence

Report:

- files checked
- drift found or not found
- commands run
- remaining alignment risk
- remaining stage / delivery-track wording hits and why each is acceptable or still needs cleanup
- `./dev check wording` result when long-term sources, Core API / UDL, README, governance, or repo-local skill text changed
