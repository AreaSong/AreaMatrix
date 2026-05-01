# AreaMatrix Validation Matrix

Choose validation from changed paths, task manifest `Validation`, and risk level. Start small, then widen when behavior crosses layers.

Every validation decision must also apply:

- `tasks/prompts/_shared/engineering-quality-rules.md`
- `docs/development/coding-standards.md`
- `CODE_REVIEW.md`
- `docs/development/dependency-policy.md`
- `docs/development/ci-governance.md`

Validation is not complete when commands pass but the implementation is a placeholder, hardcoded success path, mock-only path, or one-off script.

## Prompt And Task Runtime

| Changed paths | Required checks |
|---|---|
| `tasks/prompts/**` | `python3 tasks/prompts/_shared/prompt_pipeline.py doctor` |
| prompt manifests or shared rules | add `python3 tasks/prompts/_shared/prompt_pipeline.py status` and render one affected task |
| prompt coverage or control maps | add `python3 tasks/prompts/_shared/prompt_pipeline.py audit --pages` |
| `scripts/run_area_matrix_task_pipeline.sh` | `bash -n scripts/run_area_matrix_task_pipeline.sh`; `bash scripts/run_area_matrix_task_pipeline.sh --status`; dry-run one task |
| `.codex/skills-src/**` or `.agents/skills/**` | `bash scripts/check-skills.sh`; `python3 tasks/prompts/_shared/prompt_pipeline.py doctor` |
| governance docs, PR/issue templates, CODEOWNERS, CI workflows | `bash scripts/check-governance.sh`; `bash scripts/check-skills.sh`; `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`; YAML parse workflows |

Dry-run examples:

```bash
DRY_RUN=1 DRY_RUN_RESULT=PASS MAX_RETRIES=1 bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1 --max-tasks 1
DRY_RUN=1 RISK_GATE=high RISK_POLICY=pause bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1 --max-tasks 1
```

## Rust Core

Required for `core/**`:

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --all-targets --all-features -- -D warnings
cd core && cargo test --workspace
```

If a task manifest names narrower tests, run those too. Do not skip the manifest validation command just because broad tests pass.

## macOS App

Required for `apps/macos/**`:

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

If Xcode is unavailable, report it as blocked with exact command and error.

## Docs Only

Docs-only changes do not need code tests by default. Still run targeted checks when the docs affect executable surfaces:

- Prompt docs or manifests: run `doctor`.
- API or UDL docs: inspect `docs/api/core-api.md` and `core/area_matrix.udl` alignment.
- UX page specs with control maps: run page audit when prompt coverage can drift.
- Skill docs: run `bash scripts/check-skills.sh`.

## Mixed Changes

For mixed changes, combine relevant rows. Examples:

- `core/**` + `docs/api/**`: run Rust core checks and doc-sync checks.
- `tasks/prompts/**` + `scripts/**`: run prompt doctor and script syntax/status/dry-run checks.
- file safety behavior + docs: run implementation tests plus file-safety acceptance evidence.
- governance docs + skills + CI: run governance check, skill health, prompt doctor, and YAML parse.

## When To Widen

Widen validation when:

- change crosses Core and macOS boundary
- task is `Mission-Critical`
- behavior touches user files, DB, staging, or external sync
- manifest validation lists broader commands
- engineering-quality review finds unclear flow, missing error handling, missing comments/rustdoc, or insufficient tests
- code review, dependency, license, security, privacy, CI, or Git evidence has unresolved blockers
- prior verify failed for missing evidence
