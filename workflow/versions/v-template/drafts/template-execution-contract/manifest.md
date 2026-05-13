# V-TEMPLATE Manifest Draft: template-execution-contract

## template-execution-contract/queue-candidate

> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> feature: `template-execution-contract`
> module: `workflow-template`
> depends: `template-docs-contract`

### Intent
- Prove that plans, drafts, queue candidates, promotion preview, projection, and closeout remain preview-first and traceable.

### Task
- `queue-candidate`: Validate version-local queue candidate structure for the template reference.

### Exact Docs
- `workflow/pipeline.md`

### Sync Targets
- `workflow/templates/README.md`
- `tasks/prompts/README.md`

### Risk Level
- Low

### Risk Boundaries
- Promotion apply write is blocked for v-template.
- Preview commands must not write tasks/prompts or progress.json.
- Closeout cannot claim done without verify pass and checkpoint evidence.

### Validation
- ./dev workflow queue --version v-template doctor

## template-execution-contract/promotion-preview

> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> feature: `template-execution-contract`
> module: `workflow-template`
> depends: `template-docs-contract`

### Intent
- Prove that plans, drafts, queue candidates, promotion preview, projection, and closeout remain preview-first and traceable.

### Task
- `promotion-preview`: Validate promotion preview and apply-preview safety gates for the template reference.

### Exact Docs
- `workflow/pipeline.md`

### Sync Targets
- `workflow/templates/README.md`
- `tasks/prompts/README.md`

### Risk Level
- Low

### Risk Boundaries
- Promotion apply write is blocked for v-template.
- Preview commands must not write tasks/prompts or progress.json.
- Closeout cannot claim done without verify pass and checkpoint evidence.

### Validation
- ./dev workflow promote --version v-template apply --preview

## template-execution-contract/projection-closeout

> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> feature: `template-execution-contract`
> module: `workflow-template`
> depends: `template-docs-contract`

### Intent
- Prove that plans, drafts, queue candidates, promotion preview, projection, and closeout remain preview-first and traceable.

### Task
- `projection-closeout`: Validate projection and closeout evidence gates for the template reference.

### Exact Docs
- `workflow/pipeline.md`

### Sync Targets
- `workflow/templates/README.md`
- `tasks/prompts/README.md`

### Risk Level
- Low

### Risk Boundaries
- Promotion apply write is blocked for v-template.
- Preview commands must not write tasks/prompts or progress.json.
- Closeout cannot claim done without verify pass and checkpoint evidence.

### Validation
- ./dev workflow project --version v-template doctor
- ./dev workflow closeout --version v-template doctor
