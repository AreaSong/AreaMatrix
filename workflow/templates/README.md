# Workflow Templates

Templates define the reusable shape for future `workflow/versions/v*/` instances.

- `version.yaml`: version metadata, status, gates, and archive policy.
- `docs-discussion.md`: docs intent, user paths, Exact Docs, non-goals, and acceptance boundary.
- `middle-layer-discussion.md`: how discussion feeds changes, plans, drafts, queue, and promotion preview.
- `decisions.yaml`: machine-readable discussion approval, blockers, open questions, and risk boundaries.
- `middle-layer.example.yaml`: feature-level implementation intent ledger shape.
- `change.example.yaml`: structured feature change source with docs ledger fields.
- `plan.md`: human-readable docs-change ledger output.
- `queue.yaml`: machine-readable queue candidate shape.
- `queue.md`: human-readable queue candidate review.
- `drafts.md`: manifest / copy / verify draft package shape.
- `promotion.yaml`: machine-readable promotion preview shape.
- `promotion.md`: human-readable promotion preview shape.

Use templates as references only. Real work lives under `workflow/versions/v*/`.
For new versions, prefer `./dev workflow init --version v3`; it renders a full
skeleton and keeps live promotion mapping pending by default.
