# Phase 3 Manifest

## 3-1/task-01

> source task: `tasks/prompts/phase-3/3-1-stability-release/task-01-error-recovery-matrix.md`  
> depends: `2-4/task-08`

### Exact Docs
- `docs/api/error-codes.md`
- `docs/development/troubleshooting.md`
- `docs/ux/error-messages.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/**`
- `apps/macos/**`
- `scripts/**`

### Expected New Paths
- `core/tests/**`
- `apps/macos/AreaMatrixTests/**`
- `scripts/**`
- `docs/development/**`

### Forbidden Touches
- None

### Risk Level
- Mission-Critical

### Validation
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- `cargo test --workspace recovery`
- `cargo test --workspace error_mapping`

## 3-1/task-02

> source task: `tasks/prompts/phase-3/3-1-stability-release/task-02-recovery-scenarios.md`  
> depends: `3-1/task-01`

### Exact Docs
- `docs/api/error-codes.md`
- `docs/development/testing.md`
- `docs/development/troubleshooting.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/**`
- `apps/macos/**`
- `scripts/**`

### Expected New Paths
- `core/tests/**`
- `apps/macos/AreaMatrixTests/**`
- `scripts/**`
- `docs/development/**`

### Forbidden Touches
- None

### Risk Level
- Mission-Critical

### Validation
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- `cargo test --workspace recovery`
- `cargo test --workspace transactional_import`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 3-1/task-03

> source task: `tasks/prompts/phase-3/3-1-stability-release/task-03-performance-benchmarks.md`  
> depends: `3-1/task-02`

### Exact Docs
- `docs/development/testing.md`
- `docs/development/performance.md`
- `docs/development/observability.md`
- `docs/roadmap/stage-1-mvp.md`

### Existing Code
- `core/**`
- `apps/macos/**`
- `scripts/**`

### Expected New Paths
- `core/benches/**`
- `core/tests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`
- `apps/macos/AreaMatrixTests/**`
- `scripts/**`
- `docs/development/**`

### Forbidden Touches
- None

### Risk Level
- High

### Validation
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- `cargo bench --manifest-path core/Cargo.toml --workspace --no-run`
- `./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests`

## 3-1/task-04

> source task: `tasks/prompts/phase-3/3-1-stability-release/task-04-release-checklist.md`  
> depends: `3-1/task-03`

### Exact Docs
- `docs/development/release.md`
- `docs/development/build.md`
- `docs/roadmap/stage-1-mvp.md`
- `CHANGELOG.md`

### Existing Code
- `core/**`
- `apps/macos/**`
- `scripts/**`

### Expected New Paths
- `core/tests/**`
- `apps/macos/AreaMatrixTests/**`
- `scripts/**`
- `docs/development/**`

### Forbidden Touches
- None

### Risk Level
- High

### Validation
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- `./dev check all`
- `cargo update --dry-run`
- `git diff --check`

## 3-1/task-05

> source task: `tasks/prompts/phase-3/3-1-stability-release/task-05-stage1-integration-verify.md`  
> depends: `3-1/task-04`

### Exact Docs
- `docs/roadmap/stage-1-mvp.md`
- `docs/development/release.md`
- `docs/development/testing.md`
- `docs/architecture/mvp-control-map.md`
- `docs/core/capability-specs/stage-1-mvp.md`
- `docs/ux/page-specs/stage-1-mvp.md`

### Existing Code
- `core/**`
- `apps/macos/**`
- `scripts/**`

### Expected New Paths
- `core/tests/**`
- `apps/macos/AreaMatrixTests/**`
- `scripts/**`
- `docs/development/**`

### Forbidden Touches
- `core/src/**`
- `core/area_matrix.udl`
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrix.xcodeproj/**`

### Risk Level
- Mission-Critical

### Validation
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- `./dev check all`
- `git diff --check`
