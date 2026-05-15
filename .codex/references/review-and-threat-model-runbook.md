# Review and Threat Model Runbook

Use this runbook when AreaMatrix work asks for code review, security review, or threat modeling. It is an execution aid; policy source of truth remains `CODE_REVIEW.md`, `SECURITY.md`, and `.ai-governance/`.

## Code Review Output

Report findings first. Order findings by severity and risk:

1. correctness defects
2. regression risk
3. missing tests or weak evidence
4. security / privacy / user-file risk
5. maintainability issues

Each finding should include severity, file / line evidence, impact, and the smallest useful fix or verification request. If no actionable issue is found, say that explicitly and list remaining risk or checks not run.

## Threat Model Trigger

Threat modeling is not the default route for ordinary review. Trigger it only when:

- the user or task explicitly asks for threat modeling, abuse paths, or AppSec analysis
- a change touches user files, DB / migration, staging recovery, reindex, FSEvents / iCloud, privacy, remote AI calls, or breaking Core API / UDL behavior
- security incident response or major architecture work needs a risk model before changes

General review findings can recommend threat modeling, but they do not automatically become a full threat model.

## Threat Model Shape

Cover these sections:

- assets: user files, `.areamatrix/` metadata, DB, staging, index, logs, config, credentials, AI request / response content
- trust boundaries: user-selected folder vs app state, Core vs Swift platform layer, filesystem vs DB, staging vs final directory, FSEvents / iCloud vs app operations, local machine vs remote AI / network service
- entry points: adoption, import, reindex, staging recovery, watcher events, iCloud placeholders, Core API / UDL, logs, remote AI calls, dependencies, build scripts
- attacker capabilities and non-capabilities
- abuse paths tied to concrete assets and boundaries
- existing mitigations and recommended mitigations
- residual risk, assumptions, unverified items, and follow-up monitoring

## Owner Boundary

- `areamatrix-enterprise-governance` owns review format, security posture, merge readiness, CI, dependency, and external capability gates.
- `areamatrix-file-safety` owns user-file, DB, staging, reindex, FSEvents / iCloud, generated overview, privacy-sensitive local data, and remote-AI file-safety risk.
- `areamatrix-validation-driver` owns the smallest sufficient validation set.
- Threat modeling never replaces code review, file-safety acceptance, validation, or CI evidence.
