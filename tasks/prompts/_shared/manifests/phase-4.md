# Phase 4 Manifest

## 4-1/task-01

> source task: `tasks/prompts/phase-4/4-1-stage2-experience/task-01-tags-search-conflicts.md`  
> depends: `3-1/task-03`

### Exact Docs
- `docs/roadmap/milestones.md`
- `docs/ux/search.md`
- `docs/ux/dedup-conflict.md`
- `docs/architecture/data-model.md`

### Existing Code
- `core/src/**`
- `apps/macos/AreaMatrix/**`

### Expected New Paths
- `core/src/**`
- `apps/macos/AreaMatrix/**`
- `docs/adr/**`

### Forbidden Touches
- None

### Risk Level
- Mission-Critical

### Validation
- `./scripts/check-all.sh`

## 4-1/task-02

> source task: `tasks/prompts/phase-4/4-1-stage2-experience/task-02-custom-classification-ux.md`  
> depends: `4-1/task-01`

### Exact Docs
- `docs/roadmap/milestones.md`
- `docs/api/classifier-yaml.md`
- `docs/ux/classifier-calibration.md`
- `docs/ux/settings-panel.md`

### Existing Code
- `core/src/classify/**`
- `apps/macos/AreaMatrix/Views/Settings/**`

### Expected New Paths
- `core/src/classify/**`
- `apps/macos/AreaMatrix/Views/Settings/**`
- `apps/macos/AreaMatrix/Views/**`

### Forbidden Touches
- None

### Risk Level
- High

### Validation
- `./scripts/check-all.sh`

## 4-2/task-01

> source task: `tasks/prompts/phase-4/4-2-stage3-ai/task-01-local-ai-classification.md`  
> depends: `4-1/task-02`

### Exact Docs
- `docs/roadmap/milestones.md`
- `docs/product/prd.md`
- `docs/ux/deep-features.md`
- `docs/development/performance.md`

### Existing Code
- `core/src/classify/**`
- `apps/macos/AreaMatrix/**`

### Expected New Paths
- `core/src/**`
- `apps/macos/AreaMatrix/**`
- `docs/adr/**`

### Forbidden Touches
- None

### Risk Level
- Mission-Critical

### Validation
- `./scripts/check-all.sh`

## 4-2/task-02

> source task: `tasks/prompts/phase-4/4-2-stage3-ai/task-02-ai-summary-search-privacy.md`  
> depends: `4-2/task-01`

### Exact Docs
- `docs/roadmap/milestones.md`
- `docs/product/prd.md`
- `docs/ux/search.md`
- `docs/ux/deep-features.md`

### Existing Code
- `core/src/**`
- `apps/macos/AreaMatrix/**`

### Expected New Paths
- `core/src/**`
- `apps/macos/AreaMatrix/**`
- `docs/adr/**`

### Forbidden Touches
- None

### Risk Level
- Mission-Critical

### Validation
- `./scripts/check-all.sh`

## 4-3/task-01

> source task: `tasks/prompts/phase-4/4-3-stage4-multiplatform/task-01-ios-plan.md`  
> depends: `4-2/task-02`

### Exact Docs
- `docs/roadmap/milestones.md`
- `docs/architecture/overview.md`
- `docs/architecture/ffi-design.md`
- `docs/adr/0001-tech-stack.md`

### Existing Code
- `core/**`

### Expected New Paths
- `apps/ios/**`
- `docs/adr/**`
- `scripts/**`

### Forbidden Touches
- None

### Risk Level
- High

### Validation
- `./scripts/check-all.sh`

## 4-3/task-02

> source task: `tasks/prompts/phase-4/4-3-stage4-multiplatform/task-02-windows-linux-plan.md`  
> depends: `4-3/task-01`

### Exact Docs
- `docs/roadmap/milestones.md`
- `docs/architecture/overview.md`
- `docs/architecture/ffi-design.md`
- `docs/architecture/fs-watcher.md`

### Existing Code
- `core/**`

### Expected New Paths
- `apps/windows/**`
- `apps/linux/**`
- `docs/adr/**`
- `scripts/**`

### Forbidden Touches
- None

### Risk Level
- High

### Validation
- `./scripts/check-all.sh`

