# Phase 2 Manifest

## 2-1/task-01

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-01-first-launch-real-core.md`  
> depends: `1-1/task-03`, `1-1/task-04`, `1-4/task-01`, `1-4/task-06`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-01-welcome.md`
- `docs/ux/page-specs/stage-1-mvp/S1-02-choose-path.md`
- `docs/ux/page-specs/stage-1-mvp/S1-03-validate-path.md`
- `docs/ux/page-specs/stage-1-mvp/S1-04-confirm-init.md`
- `docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md`
- `docs/ux/page-specs/stage-1-mvp/S1-06-init-failed.md`
- `docs/ux/page-specs/stage-1-mvp/S1-07-init-done.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/api/core-api.md`
- `docs/architecture/ffi-design.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`
- `scripts/build-core.sh`

### Expected New Paths
- `apps/macos/AreaMatrix/App/**`
- `apps/macos/AreaMatrix/Bridge/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Views/Onboarding/**`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/storage/**`
- `core/src/db/**`

### Risk Level
- High

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-1/task-02

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-02-main-window-real-data.md`  
> depends: `2-1/task-01`, `1-3/task-01`, `1-3/task-02`, `1-3/task-05`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md`
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/ux/ui-states.md`
- `docs/api/core-api.md`

### Existing Code
- `apps/macos/AreaMatrix/App/**`
- `apps/macos/AreaMatrix/Bridge/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Views/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Models/RepoStore.swift`
- `apps/macos/AreaMatrix/Views/Main/**`
- `apps/macos/AreaMatrix/Views/Sidebar/**`
- `apps/macos/AreaMatrix/Views/List/**`
- `apps/macos/AreaMatrix/Views/Detail/**`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-2/task-01

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-01-single-copy-import.md`  
> depends: `2-1/task-02`, `1-2/task-02`, `1-3/task-03`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-16-drag-hover.md`
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/ux/drag-import-flow.md`
- `docs/api/core-api.md`

### Existing Code
- `apps/macos/AreaMatrix/Bridge/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Views/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Adapters/DragDropAdapter.swift`
- `apps/macos/AreaMatrix/Views/Import/**`
- `apps/macos/AreaMatrix/Models/ImportStore.swift`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-2/task-02

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-02-batch-folder-progress.md`  
> depends: `2-2/task-01`, `1-2/task-04`, `1-2/task-05`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-18-import-batch-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-19-import-folder-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/ux/drag-import-flow.md`
- `docs/api/core-api.md`

### Existing Code
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Views/Import/**`
- `apps/macos/AreaMatrix/Bridge/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Views/Import/**`
- `apps/macos/AreaMatrix/Models/ImportQueue.swift`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-2/task-03

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-03-conflict-resolution-ui.md`  
> depends: `2-2/task-01`, `1-2/task-05`, `1-2/task-06`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-22-conflict-duplicate.md`
- `docs/ux/page-specs/stage-1-mvp/S1-23-conflict-name.md`
- `docs/ux/page-specs/stage-1-mvp/S1-24-replace-confirm.md`
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/ux/dedup-conflict.md`
- `docs/api/core-api.md`

### Existing Code
- `apps/macos/AreaMatrix/Views/Import/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Bridge/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Views/Import/**`
- `apps/macos/AreaMatrix/Views/Conflict/**`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-3/task-01

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-01-detail-log-note.md`  
> depends: `2-1/task-02`, `1-3/task-04`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-12-detail-meta.md`
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`
- `docs/ux/page-specs/stage-1-mvp/S1-14-detail-note.md`
- `docs/ux/page-specs/stage-1-mvp/S1-15-detail-multi.md`
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md`
- `docs/api/core-api.md`
- `docs/modules/change-log.md`

### Existing Code
- `apps/macos/AreaMatrix/Views/Detail/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Bridge/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Views/Detail/**`
- `apps/macos/AreaMatrix/Models/DetailStore.swift`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-3/task-02

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-02-settings-error-recovery.md`  
> depends: `2-1/task-02`, `1-1/task-04`, `1-4/task-01`, `1-4/task-05`, `1-4/task-06`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md`
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`
- `docs/ux/page-specs/stage-1-mvp/S1-28-settings-classifier.md`
- `docs/ux/page-specs/stage-1-mvp/S1-29-settings-integrations.md`
- `docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md`
- `docs/ux/page-specs/stage-1-mvp/S1-31-settings-about.md`
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/ux/settings-panel.md`
- `docs/ux/error-messages.md`

### Existing Code
- `apps/macos/AreaMatrix/Views/Settings/**`
- `apps/macos/AreaMatrix/Bridge/**`
- `apps/macos/AreaMatrix/Models/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Views/Settings/**`
- `apps/macos/AreaMatrix/Views/ErrorRecovery/**`
- `apps/macos/AreaMatrix/Models/SettingsStore.swift`
- `apps/macos/AreaMatrix/Bridge/AppError.swift`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-3/task-03

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-03-file-actions.md`  
> depends: `2-1/task-02`, `1-5/task-01`, `1-5/task-02`, `1-5/task-03`, `1-4/task-06`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-33-file-rename-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-34-file-delete-confirm.md`
- `docs/ux/page-specs/stage-1-mvp/S1-35-change-category-sheet.md`
- `docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md`
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`
- `docs/api/core-api.md`

### Existing Code
- `apps/macos/AreaMatrix/Views/Detail/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Bridge/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Features/FileActions/**`
- `apps/macos/AreaMatrix/Views/Detail/**`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- Mission-Critical

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-4/task-01

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-01-fsevents-icloud-min.md`  
> depends: `2-1/task-02`, `1-4/task-02`, `1-4/task-03`, `1-4/task-04`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-25-icloud-conflict-min.md`
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/architecture/fs-watcher.md`
- `docs/adr/0005-fsevents-listener.md`
- `docs/adr/0006-icloud-support.md`
- `docs/api/core-api.md`

### Existing Code
- `apps/macos/AreaMatrix/Watcher/**`
- `apps/macos/AreaMatrix/Bridge/**`
- `apps/macos/AreaMatrix/Models/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Watcher/FSWatcher.swift`
- `apps/macos/AreaMatrix/Watcher/Debouncer.swift`
- `apps/macos/AreaMatrix/Watcher/InFlightTracker.swift`
- `apps/macos/AreaMatrix/Watcher/ICloudCoordinator.swift`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- Mission-Critical

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `cd core && cargo test --workspace sync`

## 2-4/task-02

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-02-overview-ui-contract.md`  
> depends: `2-2/task-01`, `2-3/task-02`, `1-4/task-05`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`
- `docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md`
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/modules/overview-gen.md`
- `docs/adr/0007-readme-granularity.md`
- `docs/adr/0010-adopt-existing-folders-and-overviews.md`

### Existing Code
- `apps/macos/AreaMatrix/Views/Settings/**`
- `apps/macos/AreaMatrix/Views/Import/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Bridge/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Views/Settings/**`
- `apps/macos/AreaMatrix/Views/Import/**`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `README.md`
- `README.zh-CN.md`
- `docs/**`

### Risk Level
- Mission-Critical

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `cd core && cargo test --workspace overview`

## 2-4/task-03

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-03-conflict-repair-ui.md`  
> depends: `2-4/task-01`, `2-3/task-02`, `1-5/task-04`, `1-5/task-05`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/ux/page-specs/stage-1-mvp/S1-36-icloud-conflict-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-37-db-repair-confirm.md`
- `docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md`
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`
- `docs/ux/error-messages.md`
- `docs/ux/dedup-conflict.md`

### Existing Code
- `apps/macos/AreaMatrix/Views/ErrorRecovery/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Bridge/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Features/Conflicts/**`
- `apps/macos/AreaMatrix/Features/ErrorRecovery/**`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- Mission-Critical

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `cd core && cargo test --workspace icloud_conflicts metadata_repair`
