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
| `task-loop`, `dev`, `scripts/task_loop/**`, `scripts/dev_tools/**` | `python3 -m py_compile scripts/task_loop/*.py scripts/dev_tools/*.py`; `./task-loop status`; `./dev preflight`; `./task-loop check` |
| `.codex/skills-src/**` or `.agents/skills/**` | `./dev check skills`; `./dev check prompts` |
| governance docs, PR/issue templates, CODEOWNERS, CI workflows | `./dev check governance`; `./dev check skills`; `./dev check prompts`; YAML parse workflows |

Dry-run examples:

```bash
DRY_RUN=1 DRY_RUN_RESULT=PASS MAX_RETRIES=1 ./task-loop run --phase phase-1 --max-tasks 1
DRY_RUN=1 RISK_GATE=high RISK_POLICY=pause ./task-loop run --phase phase-1 --max-tasks 1
```

## Prompt Task Gates

Phase 4 prompt tasks should not default every atomic task to `./dev check all`.
Use layered gates:

- Atomic Core task: `./dev check task <label>`.
- Core capability integration verify: `./dev check task <label>`.
- Page feature or page integration task: `./dev check task <label>`.
- Stage/foundation closeout or release task: `./dev check all`.

`./dev check task <label>` always runs prompt doctor and diff checks, then chooses
the smallest repo-local implementation gate for that task. It may run targeted
Rust tests, a macOS build, or `./dev check all` for stage closeout. Agents may
run additional targeted tests when the task or observed changes need more
evidence, but the manifest should reserve `./dev check all` for integration or
release boundaries.

Atomic Core tasks without a targeted test mapping must fail with a mapping error
instead of silently falling back to `cargo test --workspace`. Add the missing
mapping in `scripts/dev_tools/checks.py`, run an explicit `./dev check core` or
`./dev check all` for a broad gate, or set `AREAMATRIX_TASK_CHECK_FULL_FALLBACK=1`
only when an emergency full fallback is intentionally chosen.

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
./dev test macos
```

`./dev test macos` is the local macOS unit-test gate. It first runs the
standard `xcodebuild test` command. Only when the failure log explicitly points
to a local `testmanagerd` sandbox restriction may it reuse the built XCTest
bundle through `xcrun xctest`. Non-sandbox failures, assertion failures, build
failures, or link failures still fail the validation.

If Xcode is unavailable, report it as blocked with exact command and error.

## Docs Only

Docs-only changes do not need code tests by default. Still run targeted checks when the docs affect executable surfaces:

- Prompt docs or manifests: run `doctor`.
- API or UDL docs: inspect `docs/api/core-api.md` and `core/area_matrix.udl` alignment.
- UX page specs with control maps: run page audit when prompt coverage can drift.
- Skill docs: run `./dev check skills`.

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
