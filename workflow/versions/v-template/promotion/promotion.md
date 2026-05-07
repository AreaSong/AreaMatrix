# Promotion Preview: v-template

- Mode: preview only
- Live queue: not modified
- Progress file: not modified
- Future live paths below are previews only; no files have been written.
- Target kind: `preview-only`
- Writes live queue: `false`
- Template reference: `true`
- Apply allowed: `false`
- Gate: promotion blocked: v-template is a template reference and cannot apply to live tasks/prompts/**
- Target queue: `tasks/prompts`
- Future phase: `phase-5`
- Future batch: `5-1` (`template-reference`)
- Root dependency: `4-3/task-165`
- Blocked: `yes`

## Label Mapping

| Semantic task | Future live label | Depends | Task file |
|---|---|---|---|
| `template-docs-contract/docs-baseline` | `5-1/task-01` | `4-3/task-165` | `tasks/prompts/phase-5/5-1-template-reference/task-01-docs-baseline.md` |
| `template-docs-contract/discussion-gate` | `5-1/task-02` | `5-1/task-01` | `tasks/prompts/phase-5/5-1-template-reference/task-02-discussion-gate.md` |
| `template-execution-contract/queue-candidate` | `5-1/task-03` | `5-1/task-02` | `tasks/prompts/phase-5/5-1-template-reference/task-03-queue-candidate.md` |
| `template-execution-contract/promotion-preview` | `5-1/task-04` | `5-1/task-03` | `tasks/prompts/phase-5/5-1-template-reference/task-04-promotion-preview.md` |
| `template-execution-contract/projection-closeout` | `5-1/task-05` | `5-1/task-04` | `tasks/prompts/phase-5/5-1-template-reference/task-05-projection-closeout.md` |

## Future Manifest Sections

### 5-1/task-01 <- template-docs-contract/docs-baseline

```markdown
## 5-1/task-01

> source task: `workflow:template-docs-contract/docs-baseline`
> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> depends: `4-3/task-165`

### Exact Docs
- `workflow/architecture.md`
- `workflow/pipeline.md`

### Existing Code
- `workflow/architecture.md`
- `workflow/pipeline.md`
- `workflow/templates/README.md`

### Expected New Paths
- `workflow/versions/v-template/baseline/docs.yaml`
- `workflow/versions/v-template/discussion/decisions.yaml`

### Forbidden Touches
- None

### Risk Level
- Low

### Validation
- ./dev workflow baseline --version v-template doctor
- ./dev workflow doctor
```

### 5-1/task-02 <- template-docs-contract/discussion-gate

```markdown
## 5-1/task-02

> source task: `workflow:template-docs-contract/discussion-gate`
> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> depends: `5-1/task-01`

### Exact Docs
- `workflow/architecture.md`
- `workflow/pipeline.md`

### Existing Code
- `workflow/architecture.md`
- `workflow/pipeline.md`
- `workflow/templates/README.md`

### Expected New Paths
- `workflow/versions/v-template/baseline/docs.yaml`
- `workflow/versions/v-template/discussion/decisions.yaml`

### Forbidden Touches
- None

### Risk Level
- Low

### Validation
- ./dev workflow doctor
```

### 5-1/task-03 <- template-execution-contract/queue-candidate

```markdown
## 5-1/task-03

> source task: `workflow:template-execution-contract/queue-candidate`
> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> depends: `5-1/task-02`

### Exact Docs
- `workflow/pipeline.md`

### Existing Code
- `workflow/pipeline.md`
- `tasks/prompts/README.md`
- `scripts/dev_tools/workflow.py`
- `scripts/dev_tools/promotion.py`
- `scripts/dev_tools/workflow_projection.py`

### Expected New Paths
- `workflow/versions/v-template/queue/template-execution-contract/queue.yaml`
- `workflow/versions/v-template/promotion/promotion.yaml`
- `workflow/versions/v-template/projection/projection.yaml`
- `workflow/versions/v-template/closeout/closeout.yaml`

### Forbidden Touches
- None

### Risk Level
- Low

### Validation
- ./dev workflow queue --version v-template doctor
```

### 5-1/task-04 <- template-execution-contract/promotion-preview

```markdown
## 5-1/task-04

> source task: `workflow:template-execution-contract/promotion-preview`
> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> depends: `5-1/task-03`

### Exact Docs
- `workflow/pipeline.md`

### Existing Code
- `workflow/pipeline.md`
- `tasks/prompts/README.md`
- `scripts/dev_tools/workflow.py`
- `scripts/dev_tools/promotion.py`
- `scripts/dev_tools/workflow_projection.py`

### Expected New Paths
- `workflow/versions/v-template/queue/template-execution-contract/queue.yaml`
- `workflow/versions/v-template/promotion/promotion.yaml`
- `workflow/versions/v-template/projection/projection.yaml`
- `workflow/versions/v-template/closeout/closeout.yaml`

### Forbidden Touches
- None

### Risk Level
- Low

### Validation
- ./dev workflow promote --version v-template apply --preview
```

### 5-1/task-05 <- template-execution-contract/projection-closeout

```markdown
## 5-1/task-05

> source task: `workflow:template-execution-contract/projection-closeout`
> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> depends: `5-1/task-04`

### Exact Docs
- `workflow/pipeline.md`

### Existing Code
- `workflow/pipeline.md`
- `tasks/prompts/README.md`
- `scripts/dev_tools/workflow.py`
- `scripts/dev_tools/promotion.py`
- `scripts/dev_tools/workflow_projection.py`

### Expected New Paths
- `workflow/versions/v-template/queue/template-execution-contract/queue.yaml`
- `workflow/versions/v-template/promotion/promotion.yaml`
- `workflow/versions/v-template/projection/projection.yaml`
- `workflow/versions/v-template/closeout/closeout.yaml`

### Forbidden Touches
- None

### Risk Level
- Low

### Validation
- ./dev workflow project --version v-template doctor
- ./dev workflow closeout --version v-template doctor
```

## Future Task File Drafts

### tasks/prompts/phase-5/5-1-template-reference/task-01-docs-baseline.md

```markdown
# 5-1/task-01 template-docs-contract/docs-baseline

## 来源

- Workflow version: `v-template`
- Semantic task: `template-docs-contract/docs-baseline`
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`
- Module: `workflow-template`

## 目标

Prove that template workflow artifacts keep Exact Docs, discussion decisions, and baseline drift checks traceable.

## 核对清单

- 完成 `Validate Exact Docs baseline and drift checks for the template reference.`。
- 逐项读取 Exact Docs，并保持 Sync Targets 无漂移。
- 若涉及 Core API，必须同步 `docs/api/core-api.md` 与 `core/area_matrix.udl`。
- 不得移动、删除、覆盖用户原文件；不得突破风险边界。

## Exact Docs
- `workflow/architecture.md`
- `workflow/pipeline.md`

## Sync Targets
- `workflow/templates/README.md`

## 风险边界
- Does not define product behavior.
- Does not write live tasks/prompts.
- Docs drift must block downstream template gates.

## 完成标准

- 实现、文档、API / UDL、测试证据能回到 workflow change 和 manifest 逐项证明。
- 验证命令按任务风险和影响面完成；无法运行的验证必须说明原因。

## 验证
- ./dev workflow baseline --version v-template doctor
- ./dev workflow doctor
```

### tasks/prompts/phase-5/5-1-template-reference/task-02-discussion-gate.md

```markdown
# 5-1/task-02 template-docs-contract/discussion-gate

## 来源

- Workflow version: `v-template`
- Semantic task: `template-docs-contract/discussion-gate`
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`
- Module: `workflow-template`

## 目标

Prove that template workflow artifacts keep Exact Docs, discussion decisions, and baseline drift checks traceable.

## 核对清单

- 完成 `Validate discussion decisions and boundary language for the template reference.`。
- 逐项读取 Exact Docs，并保持 Sync Targets 无漂移。
- 若涉及 Core API，必须同步 `docs/api/core-api.md` 与 `core/area_matrix.udl`。
- 不得移动、删除、覆盖用户原文件；不得突破风险边界。

## Exact Docs
- `workflow/architecture.md`
- `workflow/pipeline.md`

## Sync Targets
- `workflow/templates/README.md`

## 风险边界
- Does not define product behavior.
- Does not write live tasks/prompts.
- Docs drift must block downstream template gates.

## 完成标准

- 实现、文档、API / UDL、测试证据能回到 workflow change 和 manifest 逐项证明。
- 验证命令按任务风险和影响面完成；无法运行的验证必须说明原因。

## 验证
- ./dev workflow doctor
```

### tasks/prompts/phase-5/5-1-template-reference/task-03-queue-candidate.md

```markdown
# 5-1/task-03 template-execution-contract/queue-candidate

## 来源

- Workflow version: `v-template`
- Semantic task: `template-execution-contract/queue-candidate`
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`
- Module: `workflow-template`

## 目标

Prove that plans, drafts, queue candidates, promotion preview, projection, and closeout remain preview-first and traceable.

## 核对清单

- 完成 `Validate version-local queue candidate structure for the template reference.`。
- 逐项读取 Exact Docs，并保持 Sync Targets 无漂移。
- 若涉及 Core API，必须同步 `docs/api/core-api.md` 与 `core/area_matrix.udl`。
- 不得移动、删除、覆盖用户原文件；不得突破风险边界。

## Exact Docs
- `workflow/pipeline.md`

## Sync Targets
- `workflow/templates/README.md`
- `tasks/prompts/README.md`

## 风险边界
- Promotion apply write is blocked for v-template.
- Preview commands must not write tasks/prompts or progress.json.
- Closeout cannot claim done without verify pass and checkpoint evidence.

## 完成标准

- 实现、文档、API / UDL、测试证据能回到 workflow change 和 manifest 逐项证明。
- 验证命令按任务风险和影响面完成；无法运行的验证必须说明原因。

## 验证
- ./dev workflow queue --version v-template doctor
```

### tasks/prompts/phase-5/5-1-template-reference/task-04-promotion-preview.md

```markdown
# 5-1/task-04 template-execution-contract/promotion-preview

## 来源

- Workflow version: `v-template`
- Semantic task: `template-execution-contract/promotion-preview`
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`
- Module: `workflow-template`

## 目标

Prove that plans, drafts, queue candidates, promotion preview, projection, and closeout remain preview-first and traceable.

## 核对清单

- 完成 `Validate promotion preview and apply-preview safety gates for the template reference.`。
- 逐项读取 Exact Docs，并保持 Sync Targets 无漂移。
- 若涉及 Core API，必须同步 `docs/api/core-api.md` 与 `core/area_matrix.udl`。
- 不得移动、删除、覆盖用户原文件；不得突破风险边界。

## Exact Docs
- `workflow/pipeline.md`

## Sync Targets
- `workflow/templates/README.md`
- `tasks/prompts/README.md`

## 风险边界
- Promotion apply write is blocked for v-template.
- Preview commands must not write tasks/prompts or progress.json.
- Closeout cannot claim done without verify pass and checkpoint evidence.

## 完成标准

- 实现、文档、API / UDL、测试证据能回到 workflow change 和 manifest 逐项证明。
- 验证命令按任务风险和影响面完成；无法运行的验证必须说明原因。

## 验证
- ./dev workflow promote --version v-template apply --preview
```

### tasks/prompts/phase-5/5-1-template-reference/task-05-projection-closeout.md

```markdown
# 5-1/task-05 template-execution-contract/projection-closeout

## 来源

- Workflow version: `v-template`
- Semantic task: `template-execution-contract/projection-closeout`
- Source change: `workflow/versions/v-template/changes/template-contracts.yaml`
- Module: `workflow-template`

## 目标

Prove that plans, drafts, queue candidates, promotion preview, projection, and closeout remain preview-first and traceable.

## 核对清单

- 完成 `Validate projection and closeout evidence gates for the template reference.`。
- 逐项读取 Exact Docs，并保持 Sync Targets 无漂移。
- 若涉及 Core API，必须同步 `docs/api/core-api.md` 与 `core/area_matrix.udl`。
- 不得移动、删除、覆盖用户原文件；不得突破风险边界。

## Exact Docs
- `workflow/pipeline.md`

## Sync Targets
- `workflow/templates/README.md`
- `tasks/prompts/README.md`

## 风险边界
- Promotion apply write is blocked for v-template.
- Preview commands must not write tasks/prompts or progress.json.
- Closeout cannot claim done without verify pass and checkpoint evidence.

## 完成标准

- 实现、文档、API / UDL、测试证据能回到 workflow change 和 manifest 逐项证明。
- 验证命令按任务风险和影响面完成；无法运行的验证必须说明原因。

## 验证
- ./dev workflow project --version v-template doctor
- ./dev workflow closeout --version v-template doctor
```

## Export Paths

| Live label | Copy-ready | Verify-ready |
|---|---|---|
| `5-1/task-01` | `tasks/prompts/_shared/copy-ready/phase-5/5-1-task-01.md` | `tasks/prompts/_shared/verify-ready/phase-5/5-1-task-01.md` |
| `5-1/task-02` | `tasks/prompts/_shared/copy-ready/phase-5/5-1-task-02.md` | `tasks/prompts/_shared/verify-ready/phase-5/5-1-task-02.md` |
| `5-1/task-03` | `tasks/prompts/_shared/copy-ready/phase-5/5-1-task-03.md` | `tasks/prompts/_shared/verify-ready/phase-5/5-1-task-03.md` |
| `5-1/task-04` | `tasks/prompts/_shared/copy-ready/phase-5/5-1-task-04.md` | `tasks/prompts/_shared/verify-ready/phase-5/5-1-task-04.md` |
| `5-1/task-05` | `tasks/prompts/_shared/copy-ready/phase-5/5-1-task-05.md` | `tasks/prompts/_shared/verify-ready/phase-5/5-1-task-05.md` |

## Safety

- This preview does not write `tasks/prompts/**`.
- This preview does not write `tasks/prompts/_shared/progress.json`.
- A future apply step must run separately after v1 is complete and gates pass.
