# Phase 1 Manifest

## 1-1/task-01

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-01-c1-01-contract-api.md`  
> depends: `0-2/task-13`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace validate_repo_path`

## 1-1/task-02

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-02-c1-01-implementation.md`  
> depends: `1-1/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/adopt-existing-folders.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace validate_repo_path`

## 1-1/task-03

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-03-c1-01-validation.md`  
> depends: `1-1/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace validate_repo_path`

## 1-1/task-04

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-04-c1-01-integration-verify.md`  
> depends: `1-1/task-03`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-02-choose-path.md`
- `docs/ux/page-specs/stage-1-mvp/S1-03-validate-path.md`
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace validate_repo_path`

## 1-1/task-05

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-05-c1-02-contract-api.md`  
> depends: `1-1/task-04`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace init_empty_repo`

## 1-1/task-06

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-06-c1-02-implementation.md`  
> depends: `1-1/task-05`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`
- `docs/architecture/migration.md`
- `docs/modules/overview-gen.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace init_empty_repo`

## 1-1/task-07

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-07-c1-02-failure-recovery.md`  
> depends: `1-1/task-06`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace init_empty_repo`

## 1-1/task-08

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-08-c1-02-validation.md`  
> depends: `1-1/task-07`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace init_empty_repo`

## 1-1/task-09

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-09-c1-02-integration-verify.md`  
> depends: `1-1/task-08`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-04-confirm-init.md`
- `docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md`
- `docs/ux/page-specs/stage-1-mvp/S1-07-init-done.md`
- `docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace init_empty_repo`

## 1-1/task-10

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-10-c1-03-contract-api.md`  
> depends: `1-1/task-09`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace adopt_existing_repo`

## 1-1/task-11

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-11-c1-03-implementation.md`  
> depends: `1-1/task-10`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/adopt-existing-folders.md`
- `docs/architecture/source-of-truth.md`
- `docs/modules/tree-scan.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace adopt_existing_repo`

## 1-1/task-12

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-12-c1-03-failure-recovery.md`  
> depends: `1-1/task-11`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace adopt_existing_repo`

## 1-1/task-13

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-13-c1-03-validation.md`  
> depends: `1-1/task-12`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace adopt_existing_repo`

## 1-1/task-14

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-14-c1-03-integration-verify.md`  
> depends: `1-1/task-13`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-03-validate-path.md`
- `docs/ux/page-specs/stage-1-mvp/S1-04-confirm-init.md`
- `docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md`
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace adopt_existing_repo`

## 1-1/task-15

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-15-c1-04-contract-api.md`  
> depends: `1-1/task-14`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace load_update_config`

## 1-1/task-16

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-16-c1-04-implementation.md`  
> depends: `1-1/task-15`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace load_update_config`

## 1-1/task-17

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-17-c1-04-failure-recovery.md`  
> depends: `1-1/task-16`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace load_update_config`

## 1-1/task-18

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-18-c1-04-validation.md`  
> depends: `1-1/task-17`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace load_update_config`

## 1-1/task-19

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-19-c1-04-integration-verify.md`  
> depends: `1-1/task-18`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md`
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`
- `docs/ux/page-specs/stage-1-mvp/S1-28-settings-classifier.md`
- `docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace load_update_config`

## 1-2/task-01

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-01-c1-05-contract-api.md`  
> depends: `1-1/task-19`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace classify_preview`

## 1-2/task-02

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-02-c1-05-implementation.md`  
> depends: `1-2/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/classify.md`
- `docs/api/classifier-yaml.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace classify_preview`

## 1-2/task-03

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-03-c1-05-validation.md`  
> depends: `1-2/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace classify_preview`

## 1-2/task-04

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-04-c1-05-integration-verify.md`  
> depends: `1-2/task-03`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-16-drag-hover.md`
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-18-import-batch-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-19-import-folder-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-28-settings-classifier.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace classify_preview`

## 1-2/task-05

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-05-c1-06-contract-api.md`  
> depends: `1-2/task-04`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_copy_file`

## 1-2/task-06

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-06-c1-06-implementation.md`  
> depends: `1-2/task-05`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/storage.md`
- `docs/architecture/transactional-import.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_copy_file`

## 1-2/task-07

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-07-c1-06-failure-recovery.md`  
> depends: `1-2/task-06`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_copy_file`

## 1-2/task-08

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-08-c1-06-validation.md`  
> depends: `1-2/task-07`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_copy_file`

## 1-2/task-09

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-09-c1-06-integration-verify.md`  
> depends: `1-2/task-08`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_copy_file`

## 1-2/task-10

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-10-c1-07-contract-api.md`  
> depends: `1-2/task-09`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_move_file`

## 1-2/task-11

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-11-c1-07-implementation.md`  
> depends: `1-2/task-10`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/storage.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_move_file`

## 1-2/task-12

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-12-c1-07-failure-recovery.md`  
> depends: `1-2/task-11`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_move_file`

## 1-2/task-13

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-13-c1-07-validation.md`  
> depends: `1-2/task-12`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_move_file`

## 1-2/task-14

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-14-c1-07-integration-verify.md`  
> depends: `1-2/task-13`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_move_file`

## 1-2/task-15

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-15-c1-08-contract-api.md`  
> depends: `1-2/task-14`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_index_file`

## 1-2/task-16

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-16-c1-08-implementation.md`  
> depends: `1-2/task-15`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/storage.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_index_file`

## 1-2/task-17

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-17-c1-08-failure-recovery.md`  
> depends: `1-2/task-16`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_index_file`

## 1-2/task-18

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-18-c1-08-validation.md`  
> depends: `1-2/task-17`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_index_file`

## 1-2/task-19

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-19-c1-08-integration-verify.md`  
> depends: `1-2/task-18`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_index_file`

## 1-2/task-20

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-20-c1-09-contract-api.md`  
> depends: `1-2/task-19`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace detect_duplicate`

## 1-2/task-21

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-21-c1-09-implementation.md`  
> depends: `1-2/task-20`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/storage.md`
- `docs/ux/dedup-conflict.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace detect_duplicate`

## 1-2/task-22

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-22-c1-09-failure-recovery.md`  
> depends: `1-2/task-21`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace detect_duplicate`

## 1-2/task-23

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-23-c1-09-validation.md`  
> depends: `1-2/task-22`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace detect_duplicate`

## 1-2/task-24

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-24-c1-09-integration-verify.md`  
> depends: `1-2/task-23`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-22-conflict-duplicate.md`
- `docs/ux/page-specs/stage-1-mvp/S1-24-replace-confirm.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace detect_duplicate`

## 1-2/task-25

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-25-c1-10-contract-api.md`  
> depends: `1-2/task-24`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace resolve_name_conflict`

## 1-2/task-26

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-26-c1-10-implementation.md`  
> depends: `1-2/task-25`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/storage.md`
- `docs/ux/dedup-conflict.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace resolve_name_conflict`

## 1-2/task-27

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-27-c1-10-failure-recovery.md`  
> depends: `1-2/task-26`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace resolve_name_conflict`

## 1-2/task-28

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-28-c1-10-validation.md`  
> depends: `1-2/task-27`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace resolve_name_conflict`

## 1-2/task-29

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-29-c1-10-integration-verify.md`  
> depends: `1-2/task-28`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-23-conflict-name.md`
- `docs/ux/page-specs/stage-1-mvp/S1-24-replace-confirm.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace resolve_name_conflict`

## 1-3/task-01

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-01-c1-11-contract-api.md`  
> depends: `1-2/task-29`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_files`

## 1-3/task-02

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-02-c1-11-implementation.md`  
> depends: `1-3/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_files`

## 1-3/task-03

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-03-c1-11-validation.md`  
> depends: `1-3/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_files`

## 1-3/task-04

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-04-c1-11-integration-verify.md`  
> depends: `1-3/task-03`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md`
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`
- `docs/ux/page-specs/stage-1-mvp/S1-15-detail-multi.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_files`

## 1-3/task-05

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-05-c1-12-contract-api.md`  
> depends: `1-3/task-04`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace get_file_detail`

## 1-3/task-06

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-06-c1-12-implementation.md`  
> depends: `1-3/task-05`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace get_file_detail`

## 1-3/task-07

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-07-c1-12-validation.md`  
> depends: `1-3/task-06`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace get_file_detail`

## 1-3/task-08

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-08-c1-12-integration-verify.md`  
> depends: `1-3/task-07`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-12-detail-meta.md`
- `docs/ux/page-specs/stage-1-mvp/S1-15-detail-multi.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace get_file_detail`

## 1-3/task-09

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-09-c1-13-contract-api.md`  
> depends: `1-3/task-08`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_change_log`

## 1-3/task-10

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-10-c1-13-implementation.md`  
> depends: `1-3/task-09`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_change_log`

## 1-3/task-11

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-11-c1-13-validation.md`  
> depends: `1-3/task-10`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_change_log`

## 1-3/task-12

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-12-c1-13-integration-verify.md`  
> depends: `1-3/task-11`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_change_log`

## 1-3/task-13

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-13-c1-14-contract-api.md`  
> depends: `1-3/task-12`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace read_write_note`

## 1-3/task-14

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-14-c1-14-implementation.md`  
> depends: `1-3/task-13`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace read_write_note`

## 1-3/task-15

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-15-c1-14-failure-recovery.md`  
> depends: `1-3/task-14`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace read_write_note`

## 1-3/task-16

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-16-c1-14-validation.md`  
> depends: `1-3/task-15`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace read_write_note`

## 1-3/task-17

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-17-c1-14-integration-verify.md`  
> depends: `1-3/task-16`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-14-detail-note.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace read_write_note`

## 1-3/task-18

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-18-c1-15-contract-api.md`  
> depends: `1-3/task-17`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace build_tree`

## 1-3/task-19

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-19-c1-15-implementation.md`  
> depends: `1-3/task-18`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/tree-scan.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace build_tree`

## 1-3/task-20

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-20-c1-15-validation.md`  
> depends: `1-3/task-19`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace build_tree`

## 1-3/task-21

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-21-c1-15-integration-verify.md`  
> depends: `1-3/task-20`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md`
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace build_tree`

## 1-4/task-01

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-01-c1-16-contract-api.md`  
> depends: `1-3/task-21`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace recover_on_startup`

## 1-4/task-02

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-02-c1-16-implementation.md`  
> depends: `1-4/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/transactional-import.md`
- `docs/development/troubleshooting.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace recover_on_startup`

## 1-4/task-03

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-03-c1-16-failure-recovery.md`  
> depends: `1-4/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace recover_on_startup`

## 1-4/task-04

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-04-c1-16-validation.md`  
> depends: `1-4/task-03`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace recover_on_startup`

## 1-4/task-05

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-05-c1-16-integration-verify.md`  
> depends: `1-4/task-04`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md`
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace recover_on_startup`

## 1-4/task-06

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-06-c1-17-contract-api.md`  
> depends: `1-4/task-05`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_created`

## 1-4/task-07

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-07-c1-17-implementation.md`  
> depends: `1-4/task-06`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/fs-watcher.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_created`

## 1-4/task-08

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-08-c1-17-failure-recovery.md`  
> depends: `1-4/task-07`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_created`

## 1-4/task-09

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-09-c1-17-validation.md`  
> depends: `1-4/task-08`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_created`

## 1-4/task-10

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-10-c1-17-integration-verify.md`  
> depends: `1-4/task-09`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_created`

## 1-4/task-11

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-11-c1-18-contract-api.md`  
> depends: `1-4/task-10`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_renamed`

## 1-4/task-12

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-12-c1-18-implementation.md`  
> depends: `1-4/task-11`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/fs-watcher.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_renamed`

## 1-4/task-13

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-13-c1-18-failure-recovery.md`  
> depends: `1-4/task-12`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_renamed`

## 1-4/task-14

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-14-c1-18-validation.md`  
> depends: `1-4/task-13`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_renamed`

## 1-4/task-15

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-15-c1-18-integration-verify.md`  
> depends: `1-4/task-14`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_renamed`

## 1-4/task-16

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-16-c1-19-contract-api.md`  
> depends: `1-4/task-15`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_removed`

## 1-4/task-17

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-17-c1-19-implementation.md`  
> depends: `1-4/task-16`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/fs-watcher.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_removed`

## 1-4/task-18

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-18-c1-19-failure-recovery.md`  
> depends: `1-4/task-17`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_removed`

## 1-4/task-19

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-19-c1-19-validation.md`  
> depends: `1-4/task-18`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_removed`

## 1-4/task-20

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-20-c1-19-integration-verify.md`  
> depends: `1-4/task-19`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_external_removed`

## 1-4/task-21

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-21-c1-20-contract-api.md`  
> depends: `1-4/task-20`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace overview_generated`

## 1-4/task-22

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-22-c1-20-implementation.md`  
> depends: `1-4/task-21`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/overview.md`
- `docs/modules/overview-gen.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace overview_generated`

## 1-4/task-23

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-23-c1-20-failure-recovery.md`  
> depends: `1-4/task-22`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace overview_generated`

## 1-4/task-24

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-24-c1-20-validation.md`  
> depends: `1-4/task-23`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace overview_generated`

## 1-4/task-25

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-25-c1-20-integration-verify.md`  
> depends: `1-4/task-24`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`
- `docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace overview_generated`

## 1-4/task-26

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-26-c1-21-contract-api.md`  
> depends: `1-4/task-25`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace error_mapping`

## 1-4/task-27

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-27-c1-21-implementation.md`  
> depends: `1-4/task-26`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/ux/error-messages.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace error_mapping`

## 1-4/task-28

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-28-c1-21-failure-recovery.md`  
> depends: `1-4/task-27`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace error_mapping`

## 1-4/task-29

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-29-c1-21-validation.md`  
> depends: `1-4/task-28`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace error_mapping`

## 1-4/task-30

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-30-c1-21-integration-verify.md`  
> depends: `1-4/task-29`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-03-validate-path.md`
- `docs/ux/page-specs/stage-1-mvp/S1-06-init-failed.md`
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/ux/page-specs/stage-1-mvp/S1-25-icloud-conflict-min.md`
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace error_mapping`

## 1-5/task-01

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-01-c1-22-contract-api.md`  
> depends: `1-4/task-30`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace rename_file`

## 1-5/task-02

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-02-c1-22-implementation.md`  
> depends: `1-5/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace rename_file`

## 1-5/task-03

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-03-c1-22-failure-recovery.md`  
> depends: `1-5/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace rename_file`

## 1-5/task-04

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-04-c1-22-validation.md`  
> depends: `1-5/task-03`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace rename_file`

## 1-5/task-05

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-05-c1-22-integration-verify.md`  
> depends: `1-5/task-04`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-33-file-rename-sheet.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace rename_file`

## 1-5/task-06

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-06-c1-23-contract-api.md`  
> depends: `1-5/task-05`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace delete_remove_index`

## 1-5/task-07

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-07-c1-23-implementation.md`  
> depends: `1-5/task-06`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace delete_remove_index`

## 1-5/task-08

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-08-c1-23-failure-recovery.md`  
> depends: `1-5/task-07`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace delete_remove_index`

## 1-5/task-09

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-09-c1-23-validation.md`  
> depends: `1-5/task-08`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace delete_remove_index`

## 1-5/task-10

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-10-c1-23-integration-verify.md`  
> depends: `1-5/task-09`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-34-file-delete-confirm.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace delete_remove_index`

## 1-5/task-11

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-11-c1-24-contract-api.md`  
> depends: `1-5/task-10`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace move_to_category`

## 1-5/task-12

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-12-c1-24-implementation.md`  
> depends: `1-5/task-11`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/modules/classify.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace move_to_category`

## 1-5/task-13

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-13-c1-24-failure-recovery.md`  
> depends: `1-5/task-12`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace move_to_category`

## 1-5/task-14

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-14-c1-24-validation.md`  
> depends: `1-5/task-13`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace move_to_category`

## 1-5/task-15

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-15-c1-24-integration-verify.md`  
> depends: `1-5/task-14`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-35-change-category-sheet.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace move_to_category`

## 1-5/task-16

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-16-c1-25-contract-api.md`  
> depends: `1-5/task-15`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_icloud_conflicts`

## 1-5/task-17

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-17-c1-25-implementation.md`  
> depends: `1-5/task-16`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/fs-watcher.md`
- `docs/ux/dedup-conflict.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_icloud_conflicts`

## 1-5/task-18

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-18-c1-25-failure-recovery.md`  
> depends: `1-5/task-17`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_icloud_conflicts`

## 1-5/task-19

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-19-c1-25-validation.md`  
> depends: `1-5/task-18`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_icloud_conflicts`

## 1-5/task-20

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-20-c1-25-integration-verify.md`  
> depends: `1-5/task-19`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-36-icloud-conflict-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-25-icloud-conflict-min.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_icloud_conflicts`

## 1-5/task-21

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-21-c1-26-contract-api.md`  
> depends: `1-5/task-20`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace repair_reindex_metadata`

## 1-5/task-22

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-22-c1-26-implementation.md`  
> depends: `1-5/task-21`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/migration.md`
- `docs/development/troubleshooting.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace repair_reindex_metadata`

## 1-5/task-23

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-23-c1-26-failure-recovery.md`  
> depends: `1-5/task-22`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/transactional-import.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace repair_reindex_metadata`

## 1-5/task-24

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-24-c1-26-validation.md`  
> depends: `1-5/task-23`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/development/testing.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace repair_reindex_metadata`

## 1-5/task-25

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-25-c1-26-integration-verify.md`  
> depends: `1-5/task-24`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-37-db-repair-confirm.md`
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`

### Existing Code
- `core/src/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/**`
- `core/area_matrix.udl`
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace repair_reindex_metadata`
