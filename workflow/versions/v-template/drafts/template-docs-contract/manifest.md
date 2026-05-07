# V-TEMPLATE Manifest Draft: template-docs-contract

## template-docs-contract/docs-baseline

> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> feature: `template-docs-contract`
> module: `workflow-template`
> depends: None

### Intent
- Prove that template workflow artifacts keep Exact Docs, discussion decisions, and baseline drift checks traceable.

### Task
- `docs-baseline`: Validate Exact Docs baseline and drift checks for the template reference.

### Exact Docs
- `workflow/architecture.md`
- `workflow/pipeline.md`

### Sync Targets
- `workflow/templates/README.md`

### Risk Level
- Low

### Risk Boundaries
- Does not define product behavior.
- Does not write live tasks/prompts.
- Docs drift must block downstream template gates.

### Validation
- ./dev workflow baseline --version v-template doctor
- ./dev workflow doctor

## template-docs-contract/discussion-gate

> source change: `workflow/versions/v-template/changes/template-contracts.yaml`
> feature: `template-docs-contract`
> module: `workflow-template`
> depends: None

### Intent
- Prove that template workflow artifacts keep Exact Docs, discussion decisions, and baseline drift checks traceable.

### Task
- `discussion-gate`: Validate discussion decisions and boundary language for the template reference.

### Exact Docs
- `workflow/architecture.md`
- `workflow/pipeline.md`

### Sync Targets
- `workflow/templates/README.md`

### Risk Level
- Low

### Risk Boundaries
- Does not define product behavior.
- Does not write live tasks/prompts.
- Docs drift must block downstream template gates.

### Validation
- ./dev workflow doctor
