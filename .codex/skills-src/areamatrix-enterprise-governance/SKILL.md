---
name: areamatrix-enterprise-governance
description: "Use when Codex needs to review or update AreaMatrix enterprise governance rules for code review, security, dependency policy, CI, CODEOWNERS, PR templates, or governance drift."
---

# AreaMatrix Enterprise Governance

Use this skill when the change touches enterprise governance surfaces or when a review needs governance-level gates beyond a single task.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [CODE_REVIEW.md](../../../CODE_REVIEW.md)
3. [SECURITY.md](../../../SECURITY.md)
4. [docs/development/dependency-policy.md](../../../docs/development/dependency-policy.md)
5. [docs/development/ci-governance.md](../../../docs/development/ci-governance.md)

## References

- [references/governance-map.md](references/governance-map.md): source-of-truth map for enterprise governance files.
- [references/review-security-ci.md](references/review-security-ci.md): review, security, dependency, and CI gates.

## Workflow

1. Identify whether the change affects review, security, dependencies, CI, ownership, release, or task-loop evidence.
2. Load the governance map before editing adapters, templates, skills, or prompt rules.
3. Apply the review/security/CI checklist before reporting PASS.
4. Run `bash scripts/check-governance.sh` after governance changes.

## Guardrails

- Do not make `.codex/` the only source of enterprise policy.
- Do not leave placeholder security contacts in `SECURITY.md`.
- Do not weaken CI path coverage without explicit approval.
- Do not approve task-loop PASS commits as merge-ready without review and CI evidence.
- Do not introduce dependencies without license and supply-chain review.
