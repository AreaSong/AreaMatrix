# Phase 0 Manifest

## 0-1/task-01

> source task: `tasks/prompts/phase-0/0-1-执行体系/task-01-治理入口.md`  
> depends: None

### Exact Docs
- `README.zh-CN.md`
- `docs/README.md`
- `docs/roadmap/stage-1-mvp.md`
- `docs/development/coding-standards.md`

### Existing Code
- None

### Expected New Paths
- `AGENTS.md`
- `.ai-governance/README.md`
- `.ai-governance/core/agent-principles.md`
- `.ai-governance/project/areamatrix-rules.md`
- `.ai-governance/workflows/prompt-task-runtime.md`
- `.codex/README.md`
- `.codex/references/index.md`
- `.codex/templates/prompt-task-template.md`

### Forbidden Touches
- `core/**`
- `apps/**`
- `.cursor/**`
- `.agent/**`
- `.agents/**`

### Risk Level
- Medium

### Validation
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`

## 0-1/task-02

> source task: `tasks/prompts/phase-0/0-1-执行体系/task-02-prompt-runner.md`  
> depends: `0-1/task-01`

### Exact Docs
- `README.zh-CN.md`
- `docs/README.md`
- `docs/roadmap/milestones.md`
- `docs/roadmap/stage-1-mvp.md`

### Existing Code
- None

### Expected New Paths
- `tasks/prompts/README.md`
- `tasks/prompts/_shared/audit-rules.md`
- `tasks/prompts/_shared/dependency-graph.md`
- `tasks/prompts/_shared/manifests/README.md`
- `tasks/prompts/_shared/manifests/phase-0.md`
- `tasks/prompts/_shared/manifests/phase-1.md`
- `tasks/prompts/_shared/manifests/phase-2.md`
- `tasks/prompts/_shared/manifests/phase-3.md`
- `tasks/prompts/_shared/manifests/phase-4.md`
- `tasks/prompts/_shared/prompt_pipeline.py`
- `tasks/prompts/phase-*/**`

### Forbidden Touches
- `core/**`
- `apps/**`

### Risk Level
- Medium

### Validation
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- `python3 tasks/prompts/_shared/prompt_pipeline.py plan --all`
- `python3 tasks/prompts/_shared/prompt_pipeline.py render --task 0-1/task-01`
- `python3 tasks/prompts/_shared/prompt_pipeline.py status`

## 0-2/task-01

> source task: `tasks/prompts/phase-0/0-2-工程骨架/task-01-rust-core-crate.md`  
> depends: `0-1/task-02`

### Exact Docs
- `docs/architecture/overview.md`
- `docs/architecture/tech-stack.md`
- `docs/architecture/layered-design.md`
- `docs/architecture/data-model.md`
- `docs/architecture/ffi-design.md`
- `docs/api/core-api.md`
- `docs/development/build.md`
- `docs/development/coding-standards.md`

### Existing Code
- None

### Expected New Paths
- `core/Cargo.toml`
- `core/build.rs`
- `core/area_matrix.udl`
- `core/src/**`
- `core/resources/classifier.yaml`
- `core/tests/**`
- `core/AGENTS.md`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo fmt --all -- --check`
- `cd core && cargo test --workspace`

## 0-2/task-02

> source task: `tasks/prompts/phase-0/0-2-工程骨架/task-02-build-scripts-ci.md`  
> depends: `0-2/task-01`

### Exact Docs
- `docs/development/build.md`
- `docs/development/setup.md`
- `docs/development/testing.md`
- `docs/development/release.md`

### Existing Code
- `.github/workflows/core-ci.yml`
- `.github/workflows/macos-ci.yml`

### Expected New Paths
- `scripts/build-core.sh`
- `scripts/update-bindings.sh`
- `scripts/check-all.sh`
- `.github/workflows/core-ci.yml`
- `.github/workflows/macos-ci.yml`

### Forbidden Touches
- `core/src/**`
- `apps/macos/AreaMatrix/**`

### Risk Level
- Medium

### Validation
- `bash -n scripts/build-core.sh`
- `bash -n scripts/update-bindings.sh`
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`

## 0-2/task-03

> source task: `tasks/prompts/phase-0/0-2-工程骨架/task-03-macos-app-shell.md`  
> depends: `0-2/task-01`, `0-2/task-02`

### Exact Docs
- `docs/architecture/overview.md`
- `docs/architecture/layered-design.md`
- `docs/architecture/ffi-design.md`
- `docs/development/build.md`
- `docs/development/coding-standards.md`
- `docs/ux/README.md`

### Existing Code
- None

### Expected New Paths
- `apps/macos/AreaMatrix.xcodeproj/**`
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrixTests/**`
- `apps/macos/AGENTS.md`

### Forbidden Touches
- `core/src/storage/**`
- `core/src/classify/**`
- `core/src/db/**`

### Risk Level
- High

### Validation
- `xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO`
