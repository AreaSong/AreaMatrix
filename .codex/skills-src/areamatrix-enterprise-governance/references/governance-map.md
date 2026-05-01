# Enterprise Governance Map

Use this map to decide where AreaMatrix enterprise governance rules belong.

| Governance area | Source of truth | Adapters / checks |
|---|---|---|
| Code review | `CODE_REVIEW.md` | PR template, `areamatrix-enterprise-governance`, validation driver |
| Security response | `SECURITY.md` | issue template reminder, governance check |
| Dependency and license policy | `docs/development/dependency-policy.md` | PR template, validation driver |
| CI policy | `docs/development/ci-governance.md` | `.github/workflows/*`, governance check |
| Git workflow | `docs/development/git-workflow.md` | git checkpoint skill |
| Prompt task quality | `tasks/prompts/_shared/engineering-quality-rules.md` | copy-ready / verify-ready generated prompts |
| Skill navigation | `.codex/skills-src/README.md` | `.agents/skills` symlinks |

When policy changes:

1. Update the source-of-truth document.
2. Sync PR/issue templates and skills only as adapters.
3. Update `scripts/check-governance.sh` if the policy should be mechanically enforced.
4. Run governance, skill, task-loop, and prompt checks.
