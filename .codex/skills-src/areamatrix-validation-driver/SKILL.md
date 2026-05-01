---
name: areamatrix-validation-driver
description: "Use when Codex needs to choose, run, or report the smallest sufficient AreaMatrix validation set for prompt tasks, scripts, Rust core, macOS app, docs-only changes, or mixed changes."
---

# AreaMatrix Validation Driver

Use this skill when the question is how to prove a change safely.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [docs/development/testing.md](../../../docs/development/testing.md)
3. [docs/development/coding-standards.md](../../../docs/development/coding-standards.md)
4. [CODE_REVIEW.md](../../../CODE_REVIEW.md)
5. [docs/development/dependency-policy.md](../../../docs/development/dependency-policy.md)
6. [docs/development/ci-governance.md](../../../docs/development/ci-governance.md)
7. [tasks/prompts/README.md](../../../tasks/prompts/README.md)
8. [tasks/prompts/_shared/engineering-quality-rules.md](../../../tasks/prompts/_shared/engineering-quality-rules.md)
9. The nearest path-local `AGENTS.md` for changed files, when present.

## References

- [references/validation-matrix.md](references/validation-matrix.md): path-to-command validation mapping.
- [references/report-format.md](references/report-format.md): required validation report structure.

## Workflow

1. Start from changed paths and task manifest `Validation`, not from a fixed largest command set.
2. Choose the smallest sufficient checks, widening only for cross-layer or high-risk changes.
3. Load the validation matrix before choosing commands.
4. Use the report format when handing off results.

## Guardrails

- Read this repo-local skill from `.codex/skills-src/areamatrix-validation-driver/SKILL.md` or `.agents/skills/areamatrix-validation-driver/SKILL.md`; do not guess `/Users/as/.codex/skills-src/...`.
- Do not claim completion without executed validation or an explicit blocked reason.
- Do not skip `doctor` after prompt, manifest, skill, or automation workflow changes.
- Do not let a passing dry-run replace real execution evidence.
- Do not report PASS when coding-standard or engineering-quality blockers remain.
- Do not report PASS when review, dependency, security, CI, or Git evidence blockers remain.
