# Phase 3 Manifest

## 3-1/task-01

> source task: `tasks/prompts/phase-3/3-1-stability-release/task-01-error-handling-recovery.md`  
> depends: `2-1/task-03`, `2-2/task-01`, `2-2/task-02`

### Exact Docs
- `docs/api/error-codes.md`
- `docs/development/troubleshooting.md`
- `docs/ux/error-messages.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/error.rs`
- `core/src/storage/**`
- `apps/macos/AreaMatrix/Bridge/**`
- `apps/macos/AreaMatrix/Views/**`

### Expected New Paths
- `core/tests/recovery_test.rs`
- `apps/macos/AreaMatrix/Views/**`
- `apps/macos/AreaMatrix/Logging/**`

### Forbidden Touches
- `core/src/db/schema.sql`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo test --workspace recovery`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 3-1/task-02

> source task: `tasks/prompts/phase-3/3-1-stability-release/task-02-performance-testing.md`  
> depends: `3-1/task-01`

### Exact Docs
- `docs/development/testing.md`
- `docs/development/performance.md`
- `docs/development/observability.md`
- `docs/roadmap/stage-1-mvp.md`

### Existing Code
- `core/tests/**`
- `apps/macos/AreaMatrixTests/**`
- `scripts/**`

### Expected New Paths
- `core/tests/**`
- `apps/macos/AreaMatrixTests/**`
- `scripts/check-all.sh`

### Forbidden Touches
- `core/src/api.rs`
- `core/area_matrix.udl`

### Risk Level
- High

### Validation
- `cd core && cargo test --workspace`
- `cd core && cargo llvm-cov --workspace --fail-under-lines 70`

## 3-1/task-03

> source task: `tasks/prompts/phase-3/3-1-stability-release/task-03-release-prep.md`  
> depends: `3-1/task-02`

### Exact Docs
- `docs/development/release.md`
- `docs/development/build.md`
- `docs/roadmap/stage-1-mvp.md`
- `CHANGELOG.md`

### Existing Code
- `CHANGELOG.md`
- `README.md`
- `README.zh-CN.md`
- `scripts/**`

### Expected New Paths
- `CHANGELOG.md`
- `docs/development/release.md`
- `scripts/check-all.sh`

### Forbidden Touches
- `core/src/storage/**`
- `core/src/db/**`

### Risk Level
- High

### Validation
- `./scripts/check-all.sh`

