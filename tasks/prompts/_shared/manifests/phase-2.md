# Phase 2 Manifest

## 2-1/task-01

> source task: `tasks/prompts/phase-2/2-1-macos-shell-ui/task-01-corebridge-stores.md`  
> depends: `1-3/task-01`, `1-3/task-02`

### Exact Docs
- `docs/architecture/layered-design.md`
- `docs/architecture/ffi-design.md`
- `docs/api/uniffi-recipes.md`
- `docs/api/core-api.md`
- `docs/development/coding-standards.md`

### Existing Code
- `apps/macos/AreaMatrix/Bridge/**`
- `apps/macos/AreaMatrix/Models/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Bridge/CoreBridge.swift`
- `apps/macos/AreaMatrix/Bridge/AppError.swift`
- `apps/macos/AreaMatrix/Models/RepoStore.swift`
- `apps/macos/AreaMatrix/Models/SettingsStore.swift`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/storage/**`
- `core/src/db/**`

### Risk Level
- High

### Validation
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-1/task-02

> source task: `tasks/prompts/phase-2/2-1-macos-shell-ui/task-02-onboarding-main-window.md`  
> depends: `2-1/task-01`

### Exact Docs
- `docs/ux/first-launch.md`
- `docs/ux/ui-states.md`
- `docs/architecture/adopt-existing-folders.md`
- `docs/architecture/layered-design.md`

### Existing Code
- `apps/macos/AreaMatrix/App/**`
- `apps/macos/AreaMatrix/Views/**`
- `apps/macos/AreaMatrix/Models/**`

### Expected New Paths
- `apps/macos/AreaMatrix/App/**`
- `apps/macos/AreaMatrix/Views/Main/**`
- `apps/macos/AreaMatrix/Views/Onboarding/**`
- `apps/macos/AreaMatrix/Views/Sidebar/**`
- `apps/macos/AreaMatrix/Views/List/**`
- `apps/macos/AreaMatrix/Views/Detail/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-1/task-03

> source task: `tasks/prompts/phase-2/2-1-macos-shell-ui/task-03-drag-import-list-detail.md`  
> depends: `2-1/task-02`, `1-2/task-02`

### Exact Docs
- `docs/ux/drag-import-flow.md`
- `docs/ux/dedup-conflict.md`
- `docs/ux/ui-states.md`
- `docs/modules/storage.md`
- `docs/modules/change-log.md`

### Existing Code
- `apps/macos/AreaMatrix/Views/**`
- `apps/macos/AreaMatrix/Adapters/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix/Bridge/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Adapters/DragDropAdapter.swift`
- `apps/macos/AreaMatrix/Views/Import/**`
- `apps/macos/AreaMatrix/Views/List/**`
- `apps/macos/AreaMatrix/Views/Detail/**`

### Forbidden Touches
- `core/src/db/**`
- `core/src/storage/**`

### Risk Level
- High

### Validation
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-2/task-01

> source task: `tasks/prompts/phase-2/2-2-watcher-icloud-overview/task-01-fsevents-sync.md`  
> depends: `2-1/task-03`, `1-2/task-03`

### Exact Docs
- `docs/architecture/fs-watcher.md`
- `docs/architecture/concurrency.md`
- `docs/modules/tree-scan.md`
- `docs/api/core-api.md`

### Existing Code
- `apps/macos/AreaMatrix/Watcher/**`
- `apps/macos/AreaMatrix/Bridge/**`
- `core/src/sync/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Watcher/FSWatcher.swift`
- `apps/macos/AreaMatrix/Watcher/Debouncer.swift`
- `apps/macos/AreaMatrix/Watcher/InFlightTracker.swift`
- `core/src/sync/**`
- `core/tests/sync_test.rs`

### Forbidden Touches
- `core/src/storage/**`

### Risk Level
- Mission-Critical

### Validation
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`
- `cd core && cargo test --workspace sync`

## 2-2/task-02

> source task: `tasks/prompts/phase-2/2-2-watcher-icloud-overview/task-02-icloud-coordination.md`  
> depends: `2-2/task-01`

### Exact Docs
- `docs/adr/0006-icloud-support.md`
- `docs/architecture/fs-watcher.md`
- `docs/development/troubleshooting.md`
- `docs/ux/error-messages.md`

### Existing Code
- `apps/macos/AreaMatrix/Watcher/**`
- `apps/macos/AreaMatrix/Bridge/**`

### Expected New Paths
- `apps/macos/AreaMatrix/Watcher/ICloudCoordinator.swift`
- `apps/macos/AreaMatrix/Bridge/AppError.swift`
- `apps/macos/AreaMatrixTests/ICloudCoordinatorTests.swift`

### Forbidden Touches
- `core/src/**`

### Risk Level
- Mission-Critical

### Validation
- `xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 2-2/task-03

> source task: `tasks/prompts/phase-2/2-2-watcher-icloud-overview/task-03-overview-generation.md`  
> depends: `1-2/task-03`, `2-1/task-03`

### Exact Docs
- `docs/modules/overview-gen.md`
- `docs/adr/0007-readme-granularity.md`
- `docs/adr/0010-adopt-existing-folders-and-overviews.md`
- `docs/architecture/source-of-truth.md`

### Existing Code
- `core/src/overview/**`
- `core/src/storage/**`
- `apps/macos/AreaMatrix/Models/**`

### Expected New Paths
- `core/src/overview/**`
- `core/tests/overview_test.rs`

### Forbidden Touches
- `README.md`
- `README.zh-CN.md`
- `docs/**`

### Risk Level
- Mission-Critical

### Validation
- `cd core && cargo test --workspace overview`

