# Phase 1 Manifest

## 1-1/task-01

> source task: `tasks/prompts/phase-1/1-1-core-db-repo/task-01-domain-error-api.md`  
> depends: `0-2/task-01`

### Exact Docs
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/ffi-design.md`
- `docs/architecture/layered-design.md`
- `docs/development/coding-standards.md`

### Existing Code
- `core/Cargo.toml`
- `core/src/lib.rs`
- `core/src/api.rs`
- `core/src/domain.rs`
- `core/src/error.rs`

### Expected New Paths
- `core/src/api.rs`
- `core/src/domain.rs`
- `core/src/error.rs`
- `core/area_matrix.udl`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace`

## 1-1/task-02

> source task: `tasks/prompts/phase-1/1-1-core-db-repo/task-02-db-schema-migrations.md`  
> depends: `1-1/task-01`

### Exact Docs
- `docs/architecture/data-model.md`
- `docs/architecture/migration.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/db/**`
- `core/src/error.rs`

### Expected New Paths
- `core/src/db/**`
- `core/tests/db_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo test --workspace db`

## 1-1/task-03

> source task: `tasks/prompts/phase-1/1-1-core-db-repo/task-03-repo-init-adopt-scan.md`  
> depends: `1-1/task-02`

### Exact Docs
- `docs/architecture/adopt-existing-folders.md`
- `docs/architecture/source-of-truth.md`
- `docs/architecture/transactional-import.md`
- `docs/modules/tree-scan.md`
- `docs/api/classifier-yaml.md`

### Existing Code
- `core/src/api.rs`
- `core/src/config.rs`
- `core/src/db/**`
- `core/src/tree/**`

### Expected New Paths
- `core/src/config.rs`
- `core/src/tree/**`
- `core/resources/classifier.yaml`
- `core/tests/repo_test.rs`
- `core/tests/scan_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo test --workspace repo`
- `cd core && cargo test --workspace scan`

## 1-2/task-01

> source task: `tasks/prompts/phase-1/1-2-classify-storage/task-01-classifier-rules.md`  
> depends: `1-1/task-03`

### Exact Docs
- `docs/modules/classify.md`
- `docs/api/classifier-yaml.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/classify/**`
- `core/resources/classifier.yaml`

### Expected New Paths
- `core/src/classify/**`
- `core/tests/classify_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo test --workspace classify`

## 1-2/task-02

> source task: `tasks/prompts/phase-1/1-2-classify-storage/task-02-storage-import.md`  
> depends: `1-2/task-01`

### Exact Docs
- `docs/modules/storage.md`
- `docs/architecture/transactional-import.md`
- `docs/ux/dedup-conflict.md`
- `docs/ux/drag-import-flow.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/storage/**`
- `core/tests/storage_test.rs`
- `core/tests/recovery_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo test --workspace storage`

## 1-2/task-03

> source task: `tasks/prompts/phase-1/1-2-classify-storage/task-03-change-log.md`  
> depends: `1-2/task-02`

### Exact Docs
- `docs/modules/change-log.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`

### Existing Code
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/db/**`
- `core/tests/change_log_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo test --workspace change_log`

## 1-3/task-01

> source task: `tasks/prompts/phase-1/1-3-ffi-integration/task-01-udl-bindings.md`  
> depends: `1-1/task-01`, `1-2/task-03`

### Exact Docs
- `docs/api/core-api.md`
- `docs/api/uniffi-recipes.md`
- `docs/architecture/ffi-design.md`
- `docs/development/build.md`

### Existing Code
- `core/area_matrix.udl`
- `core/build.rs`
- `scripts/build-core.sh`

### Expected New Paths
- `core/area_matrix.udl`
- `core/build.rs`
- `apps/macos/AreaMatrix/Bridge/Generated/**`

### Forbidden Touches
- `apps/macos/AreaMatrix/Views/**`

### Risk Level
- High

### Validation
- `./scripts/build-core.sh`

## 1-3/task-02

> source task: `tasks/prompts/phase-1/1-3-ffi-integration/task-02-core-api-tests.md`  
> depends: `1-3/task-01`

### Exact Docs
- `docs/api/core-api.md`
- `docs/development/testing.md`
- `docs/roadmap/stage-1-mvp.md`

### Existing Code
- `core/src/**`
- `core/tests/**`

### Expected New Paths
- `core/tests/api_flow_test.rs`
- `core/tests/common/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo test --workspace`

