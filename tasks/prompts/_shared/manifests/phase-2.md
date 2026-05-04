# Phase 2 Manifest

## 2-1/task-01

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-01-s1-01-c1-04-load-update-config.md`
> depends: `1-1/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-01-welcome.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-02

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-02-s1-02-c1-01-validate-repo-path.md`
> depends: `2-1/task-01`, `1-1/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-02-choose-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-03

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-03-s1-03-c1-01-validate-repo-path.md`
> depends: `2-1/task-02`, `1-1/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-03-validate-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-04

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-04-s1-03-c1-03-adopt-existing-repo.md`
> depends: `2-1/task-03`, `1-1/task-14`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-03-validate-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-05

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-05-s1-03-c1-21-error-mapping.md`
> depends: `2-1/task-04`, `1-4/task-30`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-03-validate-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-06

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-06-s1-03-page-integration-verify.md`
> depends: `2-1/task-03`, `2-1/task-04`, `2-1/task-05`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-03-validate-path.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-07

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-07-s1-04-c1-02-init-empty-repo.md`
> depends: `2-1/task-06`, `1-1/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-04-confirm-init.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-08

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-08-s1-04-c1-03-adopt-existing-repo.md`
> depends: `2-1/task-07`, `1-1/task-14`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-04-confirm-init.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-09

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-09-s1-04-page-integration-verify.md`
> depends: `2-1/task-07`, `2-1/task-08`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-04-confirm-init.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-10

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-10-s1-05-c1-02-init-empty-repo.md`
> depends: `2-1/task-09`, `1-1/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-11

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-11-s1-05-c1-03-adopt-existing-repo.md`
> depends: `2-1/task-10`, `1-1/task-14`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`

### Existing Code
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-12

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-12-s1-05-c1-16-recover-on-startup.md`
> depends: `2-1/task-11`, `1-4/task-05`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-13

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-13-s1-05-page-integration-verify.md`
> depends: `2-1/task-10`, `2-1/task-11`, `2-1/task-12`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-14

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-14-s1-06-c1-21-error-mapping.md`
> depends: `2-1/task-13`, `1-4/task-30`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-06-init-failed.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-15

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-15-s1-07-c1-02-init-empty-repo.md`
> depends: `2-1/task-14`, `1-1/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-07-init-done.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-16

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-16-s1-07-c1-03-adopt-existing-repo.md`
> depends: `2-1/task-15`, `1-1/task-14`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-07-init-done.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-17

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-17-s1-07-page-integration-verify.md`
> depends: `2-1/task-15`, `2-1/task-16`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-07-init-done.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-18

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-18-first-launch-integration-verify.md`
> depends: `2-1/task-17`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-01-welcome.md`
- `docs/ux/page-specs/stage-1-mvp/S1-02-choose-path.md`
- `docs/ux/page-specs/stage-1-mvp/S1-03-validate-path.md`
- `docs/ux/page-specs/stage-1-mvp/S1-04-confirm-init.md`
- `docs/ux/page-specs/stage-1-mvp/S1-05-initializing.md`
- `docs/ux/page-specs/stage-1-mvp/S1-06-init-failed.md`
- `docs/ux/page-specs/stage-1-mvp/S1-07-init-done.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/core/capability-specs/stage-1-mvp/C1-02-init-empty-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-19

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-19-s1-08-c1-11-list-files.md`
> depends: `2-1/task-18`, `1-3/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-20

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-20-s1-08-c1-15-build-tree.md`
> depends: `2-1/task-19`, `1-3/task-21`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-21

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-21-s1-08-page-integration-verify.md`
> depends: `2-1/task-19`, `2-1/task-20`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-22

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-22-s1-09-c1-11-list-files.md`
> depends: `2-1/task-21`, `1-3/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-23

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-23-s1-09-c1-12-get-file-detail.md`
> depends: `2-1/task-22`, `1-3/task-08`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-24

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-24-s1-09-c1-15-build-tree.md`
> depends: `2-1/task-23`, `1-3/task-21`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-25

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-25-s1-09-page-integration-verify.md`
> depends: `2-1/task-22`, `2-1/task-23`, `2-1/task-24`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-26

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-26-s1-10-c1-03-adopt-existing-repo.md`
> depends: `2-1/task-25`, `1-1/task-14`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-27

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-27-s1-10-c1-15-build-tree.md`
> depends: `2-1/task-26`, `1-3/task-21`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-28

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-28-s1-10-c1-16-recover-on-startup.md`
> depends: `2-1/task-27`, `1-4/task-05`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-29

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-29-s1-10-page-integration-verify.md`
> depends: `2-1/task-26`, `2-1/task-27`, `2-1/task-28`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-30

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-30-s1-11-c1-01-validate-repo-path.md`
> depends: `2-1/task-29`, `1-1/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-31

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-31-s1-11-c1-19-sync-external-removed.md`
> depends: `2-1/task-30`, `1-4/task-20`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-32

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-32-s1-11-c1-21-error-mapping.md`
> depends: `2-1/task-31`, `1-4/task-30`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-33

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-33-s1-11-page-integration-verify.md`
> depends: `2-1/task-30`, `2-1/task-31`, `2-1/task-32`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-1/task-34

> source task: `tasks/prompts/phase-2/2-1-first-launch-main/task-34-main-window-integration-verify.md`
> depends: `2-1/task-33`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-08-main-empty.md`
- `docs/ux/page-specs/stage-1-mvp/S1-09-main-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-10-main-loading.md`
- `docs/ux/page-specs/stage-1-mvp/S1-11-main-repo-error.md`
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/core/capability-specs/stage-1-mvp/C1-15-build-tree.md`
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/core/capability-specs/stage-1-mvp/C1-03-adopt-existing-repo.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-01

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-01-s1-16-c1-05-classify-preview.md`
> depends: `2-1/task-34`, `1-2/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-16-drag-hover.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-02

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-02-s1-17-c1-05-classify-preview.md`
> depends: `2-2/task-01`, `1-2/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-03

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-03-s1-17-c1-06-import-copy-file.md`
> depends: `2-2/task-02`, `1-2/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-04

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-04-s1-17-c1-07-import-move-file.md`
> depends: `2-2/task-03`, `1-2/task-14`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-05

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-05-s1-17-c1-08-import-index-file.md`
> depends: `2-2/task-04`, `1-2/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-06

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-06-s1-17-page-integration-verify.md`
> depends: `2-2/task-02`, `2-2/task-03`, `2-2/task-04`, `2-2/task-05`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-07

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-07-s1-18-c1-05-classify-preview.md`
> depends: `2-2/task-06`, `1-2/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-18-import-batch-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-08

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-08-s1-18-c1-06-import-copy-file.md`
> depends: `2-2/task-07`, `1-2/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-18-import-batch-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-09

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-09-s1-18-c1-09-detect-duplicate.md`
> depends: `2-2/task-08`, `1-2/task-24`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-18-import-batch-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-10

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-10-s1-18-page-integration-verify.md`
> depends: `2-2/task-07`, `2-2/task-08`, `2-2/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-18-import-batch-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-11

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-11-s1-19-c1-05-classify-preview.md`
> depends: `2-2/task-10`, `1-2/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-19-import-folder-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-12

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-12-s1-19-c1-06-import-copy-file.md`
> depends: `2-2/task-11`, `1-2/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-19-import-folder-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-13

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-13-s1-19-c1-08-import-index-file.md`
> depends: `2-2/task-12`, `1-2/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-19-import-folder-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-14

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-14-s1-19-page-integration-verify.md`
> depends: `2-2/task-11`, `2-2/task-12`, `2-2/task-13`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-19-import-folder-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-15

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-15-s1-20-c1-06-import-copy-file.md`
> depends: `2-2/task-14`, `1-2/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-16

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-16-s1-20-c1-07-import-move-file.md`
> depends: `2-2/task-15`, `1-2/task-14`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-17

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-17-s1-20-c1-08-import-index-file.md`
> depends: `2-2/task-16`, `1-2/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-18

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-18-s1-20-page-integration-verify.md`
> depends: `2-2/task-15`, `2-2/task-16`, `2-2/task-17`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-19

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-19-s1-21-c1-06-import-copy-file.md`
> depends: `2-2/task-18`, `1-2/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-20

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-20-s1-21-c1-13-list-change-log.md`
> depends: `2-2/task-19`, `1-3/task-12`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-21

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-21-s1-21-page-integration-verify.md`
> depends: `2-2/task-19`, `2-2/task-20`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-22

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-22-s1-22-c1-09-detect-duplicate.md`
> depends: `2-2/task-21`, `1-2/task-24`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-22-conflict-duplicate.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-23

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-23-s1-23-c1-10-resolve-name-conflict.md`
> depends: `2-2/task-22`, `1-2/task-29`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-23-conflict-name.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-24

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-24-s1-24-c1-09-detect-duplicate.md`
> depends: `2-2/task-23`, `1-2/task-24`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-24-replace-confirm.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-25

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-25-s1-24-c1-10-resolve-name-conflict.md`
> depends: `2-2/task-24`, `1-2/task-29`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-24-replace-confirm.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-26

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-26-s1-24-page-integration-verify.md`
> depends: `2-2/task-24`, `2-2/task-25`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-24-replace-confirm.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-2/task-27

> source task: `tasks/prompts/phase-2/2-2-import-conflict/task-27-import-conflict-integration-verify.md`
> depends: `2-2/task-26`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-16-drag-hover.md`
- `docs/ux/page-specs/stage-1-mvp/S1-17-import-single-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-18-import-batch-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-19-import-folder-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-20-import-progress.md`
- `docs/ux/page-specs/stage-1-mvp/S1-21-import-result.md`
- `docs/ux/page-specs/stage-1-mvp/S1-22-conflict-duplicate.md`
- `docs/ux/page-specs/stage-1-mvp/S1-23-conflict-name.md`
- `docs/ux/page-specs/stage-1-mvp/S1-24-replace-confirm.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/core/capability-specs/stage-1-mvp/C1-06-import-copy-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-09-detect-duplicate.md`
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-01

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-01-s1-12-c1-12-get-file-detail.md`
> depends: `2-2/task-27`, `1-3/task-08`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-12-detail-meta.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-02

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-02-s1-13-c1-13-list-change-log.md`
> depends: `2-3/task-01`, `1-3/task-12`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-03

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-03-s1-13-c1-17-sync-external-created.md`
> depends: `2-3/task-02`, `1-4/task-10`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-04

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-04-s1-13-c1-18-sync-external-renamed.md`
> depends: `2-3/task-03`, `1-4/task-15`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-05

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-05-s1-13-c1-19-sync-external-removed.md`
> depends: `2-3/task-04`, `1-4/task-20`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-06

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-06-s1-13-page-integration-verify.md`
> depends: `2-3/task-02`, `2-3/task-03`, `2-3/task-04`, `2-3/task-05`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-07

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-07-s1-14-c1-14-read-write-note.md`
> depends: `2-3/task-06`, `1-3/task-17`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-14-detail-note.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-08

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-08-s1-15-c1-11-list-files.md`
> depends: `2-3/task-07`, `1-3/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-15-detail-multi.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-09

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-09-s1-15-c1-12-get-file-detail.md`
> depends: `2-3/task-08`, `1-3/task-08`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-15-detail-multi.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-10

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-10-s1-15-page-integration-verify.md`
> depends: `2-3/task-08`, `2-3/task-09`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-15-detail-multi.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-11

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-11-detail-integration-verify.md`
> depends: `2-3/task-10`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-12-detail-meta.md`
- `docs/ux/page-specs/stage-1-mvp/S1-13-detail-log.md`
- `docs/ux/page-specs/stage-1-mvp/S1-14-detail-note.md`
- `docs/ux/page-specs/stage-1-mvp/S1-15-detail-multi.md`
- `docs/core/capability-specs/stage-1-mvp/C1-12-get-file-detail.md`
- `docs/core/capability-specs/stage-1-mvp/C1-13-list-change-log.md`
- `docs/core/capability-specs/stage-1-mvp/C1-17-sync-external-created.md`
- `docs/core/capability-specs/stage-1-mvp/C1-18-sync-external-renamed.md`
- `docs/core/capability-specs/stage-1-mvp/C1-19-sync-external-removed.md`
- `docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md`
- `docs/core/capability-specs/stage-1-mvp/C1-11-list-files.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-12

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-12-s1-26-c1-04-load-update-config.md`
> depends: `2-3/task-11`, `1-1/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-13

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-13-s1-26-c1-07-import-move-file.md`
> depends: `2-3/task-12`, `1-2/task-14`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-14

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-14-s1-26-page-integration-verify.md`
> depends: `2-3/task-12`, `2-3/task-13`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-15

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-15-s1-27-c1-04-load-update-config.md`
> depends: `2-3/task-14`, `1-1/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-16

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-16-s1-27-c1-08-import-index-file.md`
> depends: `2-3/task-15`, `1-2/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-17

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-17-s1-27-c1-20-overview-generated.md`
> depends: `2-3/task-16`, `1-4/task-25`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-18

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-18-s1-27-page-integration-verify.md`
> depends: `2-3/task-15`, `2-3/task-16`, `2-3/task-17`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-19

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-19-s1-28-c1-04-load-update-config.md`
> depends: `2-3/task-18`, `1-1/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-28-settings-classifier.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-20

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-20-s1-28-c1-05-classify-preview.md`
> depends: `2-3/task-19`, `1-2/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-28-settings-classifier.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-21

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-21-s1-28-page-integration-verify.md`
> depends: `2-3/task-19`, `2-3/task-20`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-28-settings-classifier.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-22

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-22-s1-29-c1-04-load-update-config.md`
> depends: `2-3/task-21`, `1-1/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-29-settings-integrations.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-23

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-23-s1-30-c1-04-load-update-config.md`
> depends: `2-3/task-22`, `1-1/task-19`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-24

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-24-s1-30-c1-16-recover-on-startup.md`
> depends: `2-3/task-23`, `1-4/task-05`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-25

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-25-s1-30-c1-20-overview-generated.md`
> depends: `2-3/task-24`, `1-4/task-25`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-26

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-26-s1-30-page-integration-verify.md`
> depends: `2-3/task-23`, `2-3/task-24`, `2-3/task-25`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-27

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-27-s1-31-ui-only.md`
> depends: `2-3/task-26`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-31-settings-about.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-28

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-28-s1-32-c1-16-recover-on-startup.md`
> depends: `2-3/task-27`, `1-4/task-05`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-29

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-29-s1-32-c1-21-error-mapping.md`
> depends: `2-3/task-28`, `1-4/task-30`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-30

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-30-s1-32-page-integration-verify.md`
> depends: `2-3/task-28`, `2-3/task-29`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-31

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-31-settings-error-recovery-integration-verify.md`
> depends: `2-3/task-30`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-26-settings-general.md`
- `docs/ux/page-specs/stage-1-mvp/S1-27-settings-repository.md`
- `docs/ux/page-specs/stage-1-mvp/S1-28-settings-classifier.md`
- `docs/ux/page-specs/stage-1-mvp/S1-29-settings-integrations.md`
- `docs/ux/page-specs/stage-1-mvp/S1-30-settings-advanced.md`
- `docs/ux/page-specs/stage-1-mvp/S1-31-settings-about.md`
- `docs/ux/page-specs/stage-1-mvp/S1-32-error-recovery.md`
- `docs/core/capability-specs/stage-1-mvp/C1-04-load-update-config.md`
- `docs/core/capability-specs/stage-1-mvp/C1-07-import-move-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-08-import-index-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-20-overview-generated.md`
- `docs/core/capability-specs/stage-1-mvp/C1-05-classify-preview.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-32

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-32-s1-33-c1-22-rename-file.md`
> depends: `2-3/task-31`, `1-5/task-05`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-33-file-rename-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-33

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-33-s1-34-c1-23-delete-remove-index.md`
> depends: `2-3/task-32`, `1-5/task-10`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-34-file-delete-confirm.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-34

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-34-s1-35-c1-24-move-to-category.md`
> depends: `2-3/task-33`, `1-5/task-15`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-35-change-category-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-35

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-35-s1-35-c1-10-resolve-name-conflict.md`
> depends: `2-3/task-34`, `1-2/task-29`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-35-change-category-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-36

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-36-s1-35-page-integration-verify.md`
> depends: `2-3/task-34`, `2-3/task-35`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-35-change-category-sheet.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-3/task-37

> source task: `tasks/prompts/phase-2/2-3-detail-settings/task-37-file-actions-integration-verify.md`
> depends: `2-3/task-36`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-33-file-rename-sheet.md`
- `docs/ux/page-specs/stage-1-mvp/S1-34-file-delete-confirm.md`
- `docs/ux/page-specs/stage-1-mvp/S1-35-change-category-sheet.md`
- `docs/core/capability-specs/stage-1-mvp/C1-22-rename-file.md`
- `docs/core/capability-specs/stage-1-mvp/C1-23-delete-remove-index.md`
- `docs/core/capability-specs/stage-1-mvp/C1-24-move-to-category.md`
- `docs/core/capability-specs/stage-1-mvp/C1-10-resolve-name-conflict.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-4/task-01

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-01-s1-25-c1-01-validate-repo-path.md`
> depends: `2-3/task-37`, `1-1/task-04`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-25-icloud-conflict-min.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-4/task-02

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-02-s1-25-c1-21-error-mapping.md`
> depends: `2-4/task-01`, `1-4/task-30`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-25-icloud-conflict-min.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-4/task-03

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-03-s1-25-page-integration-verify.md`
> depends: `2-4/task-01`, `2-4/task-02`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-25-icloud-conflict-min.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-4/task-04

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-04-s1-36-c1-25-list-icloud-conflicts.md`
> depends: `2-4/task-03`, `1-5/task-20`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-36-icloud-conflict-list.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-4/task-05

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-05-s1-37-c1-26-repair-reindex-metadata.md`
> depends: `2-4/task-04`, `1-5/task-25`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-37-db-repair-confirm.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-4/task-06

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-06-s1-37-c1-16-recover-on-startup.md`
> depends: `2-4/task-05`, `1-4/task-05`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-37-db-repair-confirm.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild build -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-4/task-07

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-07-s1-37-page-integration-verify.md`
> depends: `2-4/task-05`, `2-4/task-06`

### Exact Docs
- `docs/ux/page-specs/stage-1-mvp/S1-37-db-repair-confirm.md`
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO

## 2-4/task-08

> source task: `tasks/prompts/phase-2/2-4-sync-overview/task-08-sync-overview-repair-integration-verify.md`
> depends: `2-4/task-07`

### Exact Docs
- `docs/architecture/mvp-control-map.md`
- `docs/api/core-api.md`
- `docs/ux/page-specs/stage-1-mvp/S1-25-icloud-conflict-min.md`
- `docs/ux/page-specs/stage-1-mvp/S1-36-icloud-conflict-list.md`
- `docs/ux/page-specs/stage-1-mvp/S1-37-db-repair-confirm.md`
- `docs/core/capability-specs/stage-1-mvp/C1-01-validate-repo-path.md`
- `docs/core/capability-specs/stage-1-mvp/C1-21-error-mapping.md`
- `docs/core/capability-specs/stage-1-mvp/C1-25-list-icloud-conflicts.md`
- `docs/core/capability-specs/stage-1-mvp/C1-26-repair-reindex-metadata.md`
- `docs/core/capability-specs/stage-1-mvp/C1-16-recover-on-startup.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
