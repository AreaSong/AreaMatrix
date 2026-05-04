# Workflow Templates

Templates define the reusable shape for future `workflow/versions/v*/` instances.

- `version.yaml`: version metadata, status, gates, and archive policy.
- `change.example.yaml`: structured feature change source with docs ledger fields.
- `plan.md`: human-readable docs-change ledger output.
- `queue.yaml`: machine-readable queue candidate shape.
- `queue.md`: human-readable queue candidate review.
- `drafts.md`: manifest / copy / verify draft package shape.

Use templates as references only. Real work lives under `workflow/versions/v*/`.
