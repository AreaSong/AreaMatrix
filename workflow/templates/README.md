# Workflow Templates

Templates define the reusable shape for future `workflow/versions/v*/` instances.

- `version.yaml`: version metadata, lifecycle status, gates, and archive policy.
- `docs-discussion.md`: docs intent, user paths, Exact Docs, non-goals, and acceptance boundary.
- `middle-layer-discussion.md`: how discussion feeds changes, plans, drafts, queue, and promotion preview.
- `decisions.yaml`: machine-readable discussion approval, blockers, open questions, and risk boundaries.
- `middle-layer.example.yaml`: feature-level implementation intent ledger shape.
- `baseline.yaml`: docs baseline and drift-check shape.
- `change.example.yaml`: structured feature change source with docs ledger fields.
- `plan.md`: human-readable docs-change ledger output.
- `queue.yaml`: machine-readable queue candidate shape.
- `queue.md`: human-readable queue candidate review.
- `drafts.md`: manifest / copy / verify draft package shape.
- `promotion.yaml`: machine-readable promotion preview shape.
- `promotion.md`: human-readable promotion preview shape.
- `approval.yaml`: explicit promotion approval ledger shape.
- `apply.yaml`: explicit promote/apply preview shape; templates never write live queue.
- `projection.yaml`: result projection shape from task-loop runtime back to workflow.
- `closeout.yaml`: closeout/audit evidence shape.

Use templates as references only. `workflow/versions/v-template/` is the managed
template reference instance that proves these templates and doctors agree; it is
not a real product workflow and cannot be applied to live `tasks/prompts/**`.
Real work lives under `workflow/versions/v*/`. For new versions, prefer
`./dev workflow init --version v2` or another real `vN`; it renders a full
skeleton and keeps live promotion mapping pending by default.

Run the full template reference gate with:

```bash
./dev workflow check-template
```

Pipeline artifact `status` values are limited to `draft`, `ready`, `blocked`,
`deferred`, `promoted`, `done`, and `superseded`. Version lifecycle state uses
`lifecycle_status` so it does not collide with artifact status.
