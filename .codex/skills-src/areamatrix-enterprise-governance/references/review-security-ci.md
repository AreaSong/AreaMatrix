# Review, Security, Dependency, and CI Gates

Use these gates when reviewing enterprise governance impact.

## Review Gate

- `CODE_REVIEW.md` applies to all PRs.
- Review output is findings first. List actionable bugs, regressions, missing tests, security / privacy / user-file risks before summary.
- Findings should include severity, file / line evidence, impact, and the smallest useful fix or validation request.
- High and Mission-Critical changes need explicit risk, validation, and rollback notes.
- Task-loop PASS commits need verify log, progress, summary, Git checkpoint, review, and CI evidence.

## Security Gate

- Private vulnerability reports must use GitHub Security Advisory.
- Public issues must not contain exploit details or sensitive local data.
- User files, paths, logs, DB, staging, iCloud, and AI/network boundaries require privacy review.
- Threat modeling is explicit-only or high-risk-boundary triggered. It does not replace normal code review, tests, CI, or file-safety acceptance.
- Threat models must cover assets, trust boundaries, entry points, attacker capabilities, abuse paths, mitigations, and residual risk.

## Dependency Gate

- New dependencies require purpose, version, source, license, alternatives, supply-chain risk, tests, and rollback.
- GPL/AGPL, unknown license, untrusted binaries, and unknown-origin code are blockers by default.

## CI Gate

- Core, macOS, governance, prompt, skill, and task-loop checks should run on every PR.
- Environment skips must be explicit in workflow output and PR notes.
- CI failure blocks merge unless a maintainer records a clear exception and follow-up.

## Required Local Checks

```bash
./dev check governance
./dev check skills
./dev check task-loop
./dev check prompts
./dev check diff
```
