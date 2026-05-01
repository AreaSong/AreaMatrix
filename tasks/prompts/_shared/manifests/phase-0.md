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
- `tasks/prompts/_shared/prompt_pipeline_lib/**`
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

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-01-core-crate-metadata.md`  
> depends: `0-1/task-02`

### Exact Docs
- `docs/architecture/tech-stack.md`
- `docs/development/build.md`
- `docs/development/coding-standards.md`

### Existing Code
- None

### Expected New Paths
- `core/Cargo.toml`
- `core/AGENTS.md`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo metadata --no-deps`

## 0-2/task-02

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-02-core-module-boundaries.md`  
> depends: `0-2/task-01`

### Exact Docs
- `docs/architecture/layered-design.md`
- `docs/architecture/overview.md`
- `docs/development/coding-standards.md`

### Existing Code
- `core/Cargo.toml`

### Expected New Paths
- `core/src/lib.rs`
- `core/src/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo test --workspace`

## 0-2/task-03

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-03-core-udl-baseline.md`  
> depends: `0-2/task-02`

### Exact Docs
- `docs/architecture/ffi-design.md`
- `docs/api/core-api.md`
- `docs/api/uniffi-recipes.md`

### Existing Code
- `core/src/**`

### Expected New Paths
- `core/area_matrix.udl`
- `core/build.rs`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo test --workspace`

## 0-2/task-04

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-04-core-resource-placeholders.md`  
> depends: `0-2/task-03`

### Exact Docs
- `docs/api/classifier-yaml.md`
- `docs/modules/classify.md`

### Existing Code
- `core/src/**`

### Expected New Paths
- `core/resources/classifier.yaml`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `test -f core/resources/classifier.yaml`

## 0-2/task-05

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-05-core-smoke-tests.md`  
> depends: `0-2/task-04`

### Exact Docs
- `docs/development/testing.md`
- `docs/development/build.md`

### Existing Code
- `core/src/**`

### Expected New Paths
- `core/tests/**`

### Forbidden Touches
- `apps/**`

### Risk Level
- High

### Validation
- `cd core && cargo test --workspace`

## 0-2/task-06

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-06-build-core-script.md`  
> depends: `0-2/task-05`

### Exact Docs
- `docs/development/build.md`
- `docs/development/setup.md`

### Existing Code
- `core/**`

### Expected New Paths
- `scripts/build-core.sh`

### Forbidden Touches
- `core/src/**`
- `apps/macos/AreaMatrix/**`

### Risk Level
- Medium

### Validation
- `bash -n scripts/build-core.sh`

## 0-2/task-07

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-07-update-bindings-script.md`  
> depends: `0-2/task-06`

### Exact Docs
- `docs/architecture/ffi-design.md`
- `docs/api/uniffi-recipes.md`
- `docs/development/build.md`

### Existing Code
- `core/area_matrix.udl`

### Expected New Paths
- `scripts/update-bindings.sh`

### Forbidden Touches
- `core/src/**`
- `apps/macos/AreaMatrix/**`

### Risk Level
- High

### Validation
- `bash -n scripts/update-bindings.sh`

## 0-2/task-08

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-08-check-all-ci.md`  
> depends: `0-2/task-07`

### Exact Docs
- `docs/development/testing.md`
- `docs/development/release.md`
- `docs/development/build.md`

### Existing Code
- `.github/workflows/core-ci.yml`
- `.github/workflows/macos-ci.yml`

### Expected New Paths
- `scripts/check-all.sh`
- `.github/workflows/core-ci.yml`
- `.github/workflows/macos-ci.yml`

### Forbidden Touches
- `core/src/**`
- `apps/macos/AreaMatrix/**`

### Risk Level
- Medium

### Validation
- `bash -n scripts/check-all.sh`
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`

## 0-2/task-09

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-09-macos-xcode-project.md`  
> depends: `0-2/task-08`

### Exact Docs
- `docs/architecture/overview.md`
- `docs/development/build.md`
- `docs/architecture/ffi-design.md`

### Existing Code
- None

### Expected New Paths
- `apps/macos/AreaMatrix.xcodeproj/**`
- `apps/macos/AGENTS.md`

### Forbidden Touches
- `core/src/storage/**`
- `core/src/db/**`
- `core/src/classify/**`

### Risk Level
- High

### Validation
- `xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO`

## 0-2/task-10

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-10-macos-app-entry.md`  
> depends: `0-2/task-09`

### Exact Docs
- `docs/architecture/layered-design.md`
- `docs/ux/README.md`

### Existing Code
- `apps/macos/AreaMatrix.xcodeproj/**`

### Expected New Paths
- `apps/macos/AreaMatrix/App/**`
- `apps/macos/AreaMatrix/Views/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO`

## 0-2/task-11

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-11-macos-bridge-placeholder.md`  
> depends: `0-2/task-10`

### Exact Docs
- `docs/architecture/ffi-design.md`
- `docs/api/core-api.md`

### Existing Code
- `apps/macos/AreaMatrix/**`
- `core/area_matrix.udl`

### Expected New Paths
- `apps/macos/AreaMatrix/Bridge/**`
- `apps/macos/AreaMatrix/Models/**`
- `apps/macos/AreaMatrix.xcodeproj/project.pbxproj`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO`

## 0-2/task-12

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-12-macos-test-target.md`  
> depends: `0-2/task-11`

### Exact Docs
- `docs/development/testing.md`
- `docs/development/build.md`

### Existing Code
- `apps/macos/AreaMatrix.xcodeproj/**`

### Expected New Paths
- `apps/macos/AreaMatrixTests/**`

### Forbidden Touches
- `core/src/**`

### Risk Level
- High

### Validation
- `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO`

## 0-2/task-13

> source task: `tasks/prompts/phase-0/0-2-engineering-foundation/task-13-foundation-integration-verify.md`  
> depends: `0-2/task-12`

### Exact Docs
- `docs/architecture/overview.md`
- `docs/development/build.md`
- `docs/development/testing.md`
- `docs/ux/README.md`

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
- `core/Cargo.toml`
- `core/area_matrix.udl`
- `apps/macos/AreaMatrix/**`
- `apps/macos/AreaMatrix.xcodeproj/**`

### Risk Level
- High

### Validation
- `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- `cd core && cargo test --workspace`
