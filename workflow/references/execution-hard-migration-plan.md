# Execution Hard Migration Plan And Record

本文记录 `tasks/prompts/**` 到 `workflow/versions/<version>/execution/**` 的脚本硬迁移设计与执行验收口径。

当前用户确认并执行的目标是：

```text
tasks/prompts/** -> workflow/versions/v1-mvp/execution/**
future versions -> workflow/versions/<version>/execution/**
```

最终状态不保留 `tasks/prompts/**` 作为 runtime 兼容入口；历史引用可以在归档文档中保留，但运行脚本、doctor、task-loop、projection 和 prompt pipeline 不得继续依赖旧路径。

## Final State

标准 execution root：

```text
workflow/versions/<version>/execution/
```

`v1-mvp` 的 Stage 1 历史队列迁移后保留内部形状：

```text
workflow/versions/v1-mvp/execution/
  _shared/
    prompt_pipeline.py
    prompt_pipeline_lib/
    progress.json
    manifests/
    copy-ready/
    verify-ready/
    audit-rules.md
    engineering-quality-rules.md
    task-slicing-rules.md
    dependency-graph.md
  phase-0/
  phase-1/
  phase-2/
  phase-3/
  phase-4/
```

未来版本使用同一结构：

```text
workflow/versions/v2/execution/
workflow/versions/v3/execution/
workflow/versions/<version>/execution/
```

`tasks/` 仍可保留给未来 lightweight task system，但 `tasks/prompts/` 不再是 approved execution queue。

## Non-goals

- 不引入 symlink、shadow copy 或长期 compatibility wrapper。
- 不把 `.codex/` 变成 execution source of truth。
- 不重排 task label、phase、batch、manifest 结构。
- 不修改 product behavior、Core API、UDL 或 macOS app 行为。

## Path Owner

新增统一路径 owner：

```text
scripts/dev_tools/execution_paths.py
```

职责：

| Function | Result |
| --- | --- |
| `default_execution_version()` | `v1-mvp` |
| `execution_root(root, version)` | `workflow/versions/<version>/execution` |
| `shared_root(root, version)` | `workflow/versions/<version>/execution/_shared` |
| `prompt_pipeline(root, version)` | `<shared>/prompt_pipeline.py` |
| `progress_file(root, version)` | `<shared>/progress.json` |
| `copy_ready_root(root, version)` | `<shared>/copy-ready` |
| `verify_ready_root(root, version)` | `<shared>/verify-ready` |
| `manifest_root(root, version)` | `<shared>/manifests` |
| `task_root(root, version)` | `workflow/versions/<version>/execution` |

Environment overrides:

| Variable | Purpose |
| --- | --- |
| `AREAMATRIX_EXECUTION_VERSION` | Default version selector, normally `v1-mvp` |
| `AREAMATRIX_EXECUTION_ROOT` | Explicit execution root for tests or emergency diagnostics |
| `PIPELINE` | Existing explicit pipeline override remains supported |
| `COPY_ROOT`, `VERIFY_ROOT`, `PROGRESS_FILE` | Existing runner overrides remain supported for dry-run and tests |

Rules:

- Runtime defaults must call `execution_paths.py`; they must not hand-build `tasks/prompts`.
- Temporary tests may override root paths, but production defaults must point to versioned execution.
- Old path fallback is not allowed in final state. If execution files are missing, commands should fail with a clear migration error instead of silently reading `tasks/prompts`.

## Python Import Strategy

Current scripts import prompt helpers through:

```python
from tasks.prompts._shared.prompt_pipeline_lib...
```

That import will break after hard migration. Final design:

1. `prompt_pipeline.py` remains inside execution `_shared/`.
2. `prompt_pipeline_lib/` remains adjacent to `prompt_pipeline.py`.
3. `prompt_pipeline_lib.paths` must discover repo root by walking upward, not by fixed `parents[4]`.
4. Non-pipeline scripts must stop importing `tasks.prompts._shared...`.
5. Shared runtime queries move into `scripts/dev_tools/execution_repository.py` or equivalent neutral code if they are needed outside prompt pipeline.

Recommended split:

```text
scripts/dev_tools/execution_paths.py       # path owner
scripts/dev_tools/execution_repository.py  # scan task files, load manifests, label ordering
```

Then:

- `promotion.py` imports from `execution_repository.py`, not from moved prompt pipeline internals.
- `workflow_projection.py` imports from `execution_repository.py`, not from `tasks.prompts`.
- `task_loop/console.py` imports from `execution_repository.py` for dashboard summaries.
- `prompt_pipeline_lib` may keep its own local implementation, but external scripts should not depend on its package path.

## Affected Surfaces

### Prompt Pipeline

Current runtime owner:

```text
tasks/prompts/_shared/prompt_pipeline.py
tasks/prompts/_shared/prompt_pipeline_lib/**
```

Target:

```text
workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py
workflow/versions/v1-mvp/execution/_shared/prompt_pipeline_lib/**
```

Required updates:

- `prompt_pipeline_lib/paths.py`
- displayed command examples in `commands.py`
- doctor/status/render/export path output
- allowed roots and markdown link checks where `tasks/` was only allowed because of `tasks/prompts`

### Task-loop Runner

Current defaults:

```text
COPY_ROOT=tasks/prompts/_shared/copy-ready
VERIFY_ROOT=tasks/prompts/_shared/verify-ready
PROGRESS_FILE=tasks/prompts/_shared/progress.json
PIPELINE=tasks/prompts/_shared/prompt_pipeline.py
```

Target defaults:

```text
COPY_ROOT=workflow/versions/v1-mvp/execution/_shared/copy-ready
VERIFY_ROOT=workflow/versions/v1-mvp/execution/_shared/verify-ready
PROGRESS_FILE=workflow/versions/v1-mvp/execution/_shared/progress.json
PIPELINE=workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py
```

Required updates:

- `scripts/task_loop/runner.py`
- `scripts/task_loop/console.py`
- `scripts/task_loop/self_check.py`
- `scripts/task_loop/state.py` only if status text assumes old paths
- `.codex/task-loop-runs/index.json` handling must remain compatible with historical summaries

### Dev Tools

Required updates:

- `scripts/dev_tools/checks.py`
- `scripts/dev_tools/promotion.py`
- `scripts/dev_tools/workflow.py`
- `scripts/dev_tools/workflow_projection.py`
- `scripts/dev_tools/migrate_evidence_paths.py`
- tests under `scripts/dev_tools/test_*.py`

`promotion.py` must generate version execution paths, not `tasks/prompts` paths.

`workflow_projection.py` must read progress and manifests from execution.

`checks.py` must resolve task labels through execution instead of `tasks/prompts`.

### Governance, Skills, And Docs

Required updates:

- `.ai-governance/README.md`
- `.ai-governance/workflows/prompt-task-runtime.md`
- `.ai-governance/workflows/external-capability-admission.md`
- `.ai-governance/workflows/subagent-boundaries.md`
- `.ai-governance/project/areamatrix-rules.md`
- `.codex/skills-src/areamatrix-task-loop/SKILL.md`
- `.codex/skills-src/areamatrix-doc-sync/**`
- `.codex/skills-src/areamatrix-validation-driver/**`
- `README.md`
- `README.zh-CN.md`
- `scripts/task_loop.md`
- `workflow/versions/README.md`

Generated or historical source-doc links under `workflow/versions/v1-mvp/source-docs/**` may keep old references only when they are explicitly historical. Any current command or rule must use execution paths.

## Migration Phases

以下 phase 是本次硬迁移的执行记录和复核清单。旧路径命令只作为迁移前 inventory 证据保留，不是当前 runtime 命令。

### Phase 0: Freeze And Inventory

Purpose: prove there is no live runner and record source state.

Required commands:

```bash
git status --short --untracked-files=all
./task-loop status
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
python3 tasks/prompts/_shared/prompt_pipeline.py status
```

Expected evidence:

- no live lock
- `completed: 637`
- prompt doctor OK
- dirty worktree understood before file moves

### Phase 1: Add Path Owner

Implement:

```text
scripts/dev_tools/execution_paths.py
scripts/dev_tools/execution_repository.py
```

At this phase, do not move files yet. Use tests with temporary execution roots to prove the new resolver works.

Required checks:

```bash
python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py
./dev workflow doctor
```

### Phase 2: Convert Runtime Defaults

Update runner, console, dev checks, workflow projection, and promotion code to use `execution_paths.py`.

Important rule: after this phase, runtime code should have no production default that points to `tasks/prompts`.

Allowed temporary condition: tests may create fixture directories named `tasks/prompts` only when testing historical input or explicit migration errors.

Required checks:

```bash
python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py
./task-loop check
./dev workflow check-template
```

### Phase 3: Move Stage 1 Queue

Use `git mv` to preserve history:

```bash
git mv tasks/prompts/_shared workflow/versions/v1-mvp/execution/_shared
git mv tasks/prompts/phase-0 workflow/versions/v1-mvp/execution/phase-0
git mv tasks/prompts/phase-1 workflow/versions/v1-mvp/execution/phase-1
git mv tasks/prompts/phase-2 workflow/versions/v1-mvp/execution/phase-2
git mv tasks/prompts/phase-3 workflow/versions/v1-mvp/execution/phase-3
git mv tasks/prompts/phase-4 workflow/versions/v1-mvp/execution/phase-4
```

If `tasks/prompts/README.md` exists, move it to:

```text
workflow/versions/v1-mvp/execution/README.md
```

Do not leave a symlink or wrapper at `tasks/prompts`.

Required checks immediately after move:

```bash
python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py doctor
python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py status
./task-loop status
./task-loop check
```

### Phase 4: Rewrite Current References

Rewrite current runtime and governance references from old to new paths.

Required command scan:

```bash
rg -n "tasks/prompts|tasks\\.prompts" scripts task-loop dev .ai-governance README.md README.zh-CN.md workflow .codex/skills-src
```

Allowed residuals:

- migration plan itself
- historical source-doc prose that explicitly says the path is old/historical
- archived task text that intentionally records original source paths

Forbidden residuals:

- runtime defaults
- Python imports
- validation commands
- current governance source-of-truth statements
- current README fixed-path warnings
- current skill instructions

### Phase 5: Final Hard-migration Gate

Required checks:

```bash
git diff --check
python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py
python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py doctor
python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py status
./task-loop status
./task-loop check
./dev preflight
./dev workflow doctor
./dev workflow check-template
./dev check skills
./dev check governance
```

Expected final state:

- `./task-loop status` prints `progress_file: .../workflow/versions/v1-mvp/execution/_shared/progress.json`
- prompt status still reports `637` tasks and `637` completed
- `rg -n "from tasks\\.prompts|tasks/prompts/_shared/prompt_pipeline.py|tasks/prompts/_shared/progress.json" scripts .ai-governance .codex/skills-src README.md README.zh-CN.md workflow` has no current-runtime hits
- `tasks/prompts` does not exist
- `workflow/versions/v1-mvp/execution/_shared/progress.json` exists
- `workflow/versions/v1-mvp/execution/phase-0` through `phase-4` exist

## Rollback Strategy

Before Phase 3, rollback is normal code revert.

After Phase 3, rollback must use `git mv` back to the old path, not copy/delete:

```bash
git mv workflow/versions/v1-mvp/execution/_shared tasks/prompts/_shared
git mv workflow/versions/v1-mvp/execution/phase-0 tasks/prompts/phase-0
git mv workflow/versions/v1-mvp/execution/phase-1 tasks/prompts/phase-1
git mv workflow/versions/v1-mvp/execution/phase-2 tasks/prompts/phase-2
git mv workflow/versions/v1-mvp/execution/phase-3 tasks/prompts/phase-3
git mv workflow/versions/v1-mvp/execution/phase-4 tasks/prompts/phase-4
```

Do not edit `progress.json` to fake rollback success. Re-run status and doctor after rollback.

## Completion Criteria

The hard migration is complete only when all are true:

- Stage 1 queue physically lives under `workflow/versions/v1-mvp/execution/**`.
- Runtime defaults point to execution paths.
- Python imports no longer depend on `tasks.prompts`.
- Prompt doctor/status pass from the new path.
- Task-loop status/check pass with the new progress path.
- Workflow doctor/check-template pass.
- Governance and skill docs describe execution as the current runtime owner.
- No `tasks/prompts` compatibility path remains.
