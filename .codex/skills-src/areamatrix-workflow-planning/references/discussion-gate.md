# Discussion Gate

New v* versions must complete `workflow/versions/<version>/discussion/` before writing `changes/`.

Required files:

- `docs-discussion.md`: feature intent, user paths, Exact Docs, contention points, non-goals, and acceptance boundary.
- `middle-layer-discussion.md`: how discussion feeds changes, plans, drafts, queue, and promotion preview.
- `decisions.yaml`: machine-readable approval, open questions, blockers, risk boundaries, and next-layer status.

Approval requirements:

- `allow_changes: true`
- `exact_docs` is non-empty and every path exists.
- `docs-discussion.md` mentions each Exact Docs path.
- `open_questions` and `blockers` are empty, closed, resolved, accepted, deferred, or not-applicable.
- `risk_boundaries` is non-empty.

Open question and residual boundary:

- During discussion, unresolved product scope, Exact Docs, non-goals, v1 inheritance, or execution timing questions stay in `decisions.yaml`.
- Do not create `workflow/versions/<version>/residuals/**` for ordinary discussion questions.
- Create version residuals only when a discussion decision intentionally leaves a durable blocker, deferred item, accepted exception, reference-only item, or template-only item that must remain visible after discussion handoff.
- When version residuals are created, synchronize both the version residual index and the global `workflow/residuals/residuals.yaml` `version_residuals` list.

Use:

```bash
./dev workflow discuss --version <version> doctor
./dev workflow discuss --version <version> preview
```
