# Phase 1 Manifest

## 1-1/task-01

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-01-validate-repo-path.md`  
> depends: `0-2/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/architecture/adopt-existing-folders.md`

### Existing Code
- `core/src/api.rs`
- `core/src/error.rs`
- `core/src/config.rs`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/api.rs`
- `core/src/error.rs`
- `core/src/config.rs`
- `core/area_matrix.udl`
- `core/tests/validate_repo_path_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace validate_repo_path`

## 1-1/task-02

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-02-init-empty-repo.md`  
> depends: `1-1/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`
- `docs/architecture/migration.md`
- `docs/modules/overview-gen.md`

### Existing Code
- `core/src/api.rs`
- `core/src/config.rs`
- `core/src/db/**`
- `core/src/overview/**`
- `core/resources/classifier.yaml`

### Expected New Paths
- `core/src/api.rs`
- `core/src/config.rs`
- `core/src/db/**`
- `core/src/overview/**`
- `core/resources/classifier.yaml`
- `core/tests/init_empty_repo_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace init_empty_repo`

## 1-1/task-03

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-03-adopt-existing-repo.md`  
> depends: `1-1/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/architecture/mvp-control-map.md`
- `docs/architecture/adopt-existing-folders.md`
- `docs/architecture/source-of-truth.md`
- `docs/modules/tree-scan.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/api.rs`
- `core/src/config.rs`
- `core/src/db/**`
- `core/src/tree/**`

### Expected New Paths
- `core/src/api.rs`
- `core/src/config.rs`
- `core/src/db/**`
- `core/src/tree/**`
- `core/tests/adopt_existing_repo_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace adopt_existing_repo`

## 1-1/task-04

> source task: `tasks/prompts/phase-1/1-1-repo-config/task-04-load-update-config.md`  
> depends: `1-1/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`
- `docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md`
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`

### Existing Code
- `core/src/api.rs`
- `core/src/config.rs`
- `core/src/db/**`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/api.rs`
- `core/src/config.rs`
- `core/src/db/**`
- `core/area_matrix.udl`
- `core/tests/config_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace config`

## 1-2/task-01

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-01-classify-preview.md`  
> depends: `1-1/task-04`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/classify.md`
- `docs/api/classifier-yaml.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/classify/**`
- `core/resources/classifier.yaml`
- `core/src/api.rs`

### Expected New Paths
- `core/src/classify/**`
- `core/resources/classifier.yaml`
- `core/src/api.rs`
- `core/tests/classify_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace classify`

## 1-2/task-02

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-02-import-copy-file.md`  
> depends: `1-2/task-01`, `1-1/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/storage.md`
- `docs/architecture/transactional-import.md`
- `docs/modules/change-log.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/src/overview/**`

### Expected New Paths
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/import_copy_file_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_copy_file`

## 1-2/task-03

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-03-import-move-file.md`  
> depends: `1-2/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/storage.md`
- `docs/architecture/transactional-import.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/import_move_file_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_move_file`

## 1-2/task-04

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-04-import-index-file.md`  
> depends: `1-2/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/storage.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`

### Existing Code
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/import_index_file_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace import_index_file`

## 1-2/task-05

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-05-detect-duplicate.md`  
> depends: `1-2/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/storage.md`
- `docs/ux/dedup-conflict.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/duplicate_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace duplicate`

## 1-2/task-06

> source task: `tasks/prompts/phase-1/1-2-import-classify/task-06-resolve-name-conflict.md`  
> depends: `1-2/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/storage.md`
- `docs/ux/dedup-conflict.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/name_conflict_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace name_conflict`

## 1-3/task-01

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-01-list-files.md`  
> depends: `1-2/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`

### Existing Code
- `core/src/api.rs`
- `core/src/db/**`

### Expected New Paths
- `core/src/api.rs`
- `core/src/db/**`
- `core/tests/list_files_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace list_files`

## 1-3/task-02

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-02-get-file-detail.md`  
> depends: `1-3/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`

### Existing Code
- `core/src/api.rs`
- `core/src/db/**`

### Expected New Paths
- `core/src/api.rs`
- `core/src/db/**`
- `core/tests/get_file_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace get_file`

## 1-3/task-03

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-03-list-change-log.md`  
> depends: `1-2/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/change-log.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`

### Existing Code
- `core/src/api.rs`
- `core/src/db/**`

### Expected New Paths
- `core/src/api.rs`
- `core/src/db/**`
- `core/tests/change_log_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace change_log`

## 1-3/task-04

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-04-read-write-note.md`  
> depends: `1-3/task-02`, `1-3/task-03`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/architecture/data-model.md`
- `docs/architecture/fs-watcher.md`

### Existing Code
- `core/src/api.rs`
- `core/src/db/**`
- `core/src/storage/**`

### Expected New Paths
- `core/src/api.rs`
- `core/src/db/**`
- `core/tests/note_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace note`

## 1-3/task-05

> source task: `tasks/prompts/phase-1/1-3-query-detail/task-05-build-tree.md`  
> depends: `1-3/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/tree-scan.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/api.rs`
- `core/src/tree/**`
- `core/src/db/**`

### Expected New Paths
- `core/src/api.rs`
- `core/src/tree/**`
- `core/tests/tree_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace tree`

## 1-4/task-01

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-01-recover-on-startup.md`  
> depends: `1-2/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/storage.md`
- `docs/architecture/transactional-import.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/recovery_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace recovery`

## 1-4/task-02

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-02-sync-external-created.md`  
> depends: `1-3/task-01`, `1-3/task-03`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`
- `docs/architecture/mvp-control-map.md`
- `docs/architecture/fs-watcher.md`
- `docs/architecture/source-of-truth.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/sync/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/sync/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/sync_created_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_created`

## 1-4/task-03

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-03-sync-external-renamed.md`  
> depends: `1-4/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/architecture/fs-watcher.md`
- `docs/architecture/source-of-truth.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/sync/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/sync/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/sync_renamed_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_renamed`

## 1-4/task-04

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-04-sync-external-removed.md`  
> depends: `1-4/task-02`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/architecture/fs-watcher.md`
- `docs/architecture/source-of-truth.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/sync/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/sync/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/sync_removed_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace sync_removed`

## 1-4/task-05

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-05-overview-generated.md`  
> depends: `1-2/task-02`, `1-1/task-04`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`
- `docs/architecture/mvp-control-map.md`
- `docs/modules/overview-gen.md`
- `docs/adr/0007-readme-granularity.md`
- `docs/adr/0010-adopt-existing-folders-and-overviews.md`
- `docs/architecture/source-of-truth.md`

### Existing Code
- `core/src/overview/**`
- `core/src/storage/**`
- `core/src/config.rs`

### Expected New Paths
- `core/src/overview/**`
- `core/src/config.rs`
- `core/tests/overview_test.rs`

### Forbidden Touches
- `README.md`
- `README.zh-CN.md`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace overview`

## 1-4/task-06

> source task: `tasks/prompts/phase-1/1-4-recovery-sync-overview/task-06-error-mapping.md`  
> depends: `1-1/task-01`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/error-codes.md`
- `docs/api/core-api.md`
- `docs/ux/error-messages.md`

### Existing Code
- `core/src/error.rs`
- `core/src/api.rs`
- `core/area_matrix.udl`

### Expected New Paths
- `core/src/error.rs`
- `core/area_matrix.udl`
- `apps/macos/AreaMatrix/Bridge/AppError.swift`
- `core/tests/error_test.rs`

### Forbidden Touches
- `core/src/storage/**`
- `core/src/db/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace error`

## 1-5/task-01

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-01-rename-file.md`  
> depends: `1-3/task-02`, `1-3/task-03`, `1-2/task-06`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md`
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-33-file-rename-sheet.md`
- `docs/api/core-api.md`
- `docs/modules/change-log.md`

### Existing Code
- `core/src/api.rs`
- `core/src/storage/**`
- `core/src/db/**`

### Expected New Paths
- `core/src/api.rs`
- `core/src/storage/**`
- `core/src/db/**`
- `core/tests/rename_file_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace rename_file`

## 1-5/task-02

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-02-delete-remove-index.md`  
> depends: `1-3/task-02`, `1-3/task-03`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md`
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-34-file-delete-confirm.md`
- `docs/api/core-api.md`
- `docs/modules/storage.md`

### Existing Code
- `core/src/api.rs`
- `core/src/storage/**`
- `core/src/db/**`

### Expected New Paths
- `core/src/api.rs`
- `core/src/storage/**`
- `core/src/db/**`
- `core/tests/delete_remove_index_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace delete_remove_index`

## 1-5/task-03

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-03-move-to-category.md`  
> depends: `1-3/task-02`, `1-2/task-06`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-35-change-category-sheet.md`
- `docs/api/core-api.md`
- `docs/modules/storage.md`

### Existing Code
- `core/src/api.rs`
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/classify/**`

### Expected New Paths
- `core/src/api.rs`
- `core/src/storage/**`
- `core/src/db/**`
- `core/tests/move_to_category_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace move_to_category`

## 1-5/task-04

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-04-list-icloud-conflicts.md`  
> depends: `1-4/task-04`, `1-4/task-06`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md`
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-36-icloud-conflict-list.md`
- `docs/adr/0006-icloud-support.md`
- `docs/ux/dedup-conflict.md`

### Existing Code
- `core/src/sync/**`
- `core/src/api.rs`
- `core/src/db/**`

### Expected New Paths
- `core/src/sync/**`
- `core/src/api.rs`
- `core/tests/icloud_conflicts_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace icloud_conflicts`

## 1-5/task-05

> source task: `tasks/prompts/phase-1/1-5-file-actions-repair/task-05-repair-reindex-metadata.md`  
> depends: `1-4/task-01`, `1-4/task-02`, `1-4/task-06`

### Exact Docs
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-37-db-repair-confirm.md`
- `docs/architecture/transactional-import.md`
- `docs/modules/tree-scan.md`
- `docs/api/core-api.md`

### Existing Code
- `core/src/storage/**`
- `core/src/tree/**`
- `core/src/db/**`
- `core/src/api.rs`

### Expected New Paths
- `core/src/storage/**`
- `core/src/tree/**`
- `core/src/db/**`
- `core/src/api.rs`
- `core/tests/metadata_repair_test.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo clippy --all-targets --all-features -- -D warnings`
- `cd core && cargo test --workspace metadata_repair`
