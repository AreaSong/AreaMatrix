# v3 Middle-layer Discussion

## Handoff Contract

The v3 middle layer carries the approved bilingual product contract into implementation slices. It does not replace
`docs/**`, write live execution files, or authorize promotion. Copy-ready implementation and verify-ready acceptance
remain separate.

## Ordered Slices

1. Product source: update all Exact Docs, schema/data-model, migration, first-launch, API and development contracts.
2. Core contract: add typed concrete content locale, repository config snapshot/revision/field patch, strict policy
   gates, classifier locale maps and degraded state, overview provenance/regeneration, receipt recovery, and repair
   separation.
3. UDL and bindings: remove the process-global locale setter, expose v2 DTOs and recovery tokens, regenerate tracked
   bindings through `./dev bindings update`, and migrate every consumer in one cutover.
4. macOS presentation: inject one observable `AppLocalizer`, preserve stable state identity, implement the three-state
   Welcome cycle, General immediate preference, Repository Save/Discard/Cancel draft, multi-window CAS conflict state,
   classifier two-language editor, and fixture-only UI recovery flows.
5. Governance and evidence: enforce String Catalog parity, Core Markdown catalog parity, no premature display-string
   persistence, no unknown-policy mutation bypass, operation provenance, file-safety invariants, and the complete UI
   language matrix.

## Required Sync Targets

- Product and UX: every Exact Docs path in `docs-discussion.md`.
- Core API and UDL: `docs/api/core-api.md` before `core/area_matrix.udl`.
- Rust: `core/src/content_catalog.rs`, config/CAS, classifier, overview, AI provenance, sync receipts, schema,
  repair/reindex and operation context modules.
- Swift: `AppLanguage`, `AppLocalizer`, Settings, Onboarding, Repository lifecycle, classifier editor, AI summaries,
  external sync, generated binding consumers and String Catalog.
- Tests: Rust contract/implementation/failure-recovery/integration tests, Swift state/page/UI tests, governance checks,
  and temporary repository file-hash evidence.

## Promotion Boundary

`changes`, `plans`, `drafts`, `queue`, and promotion preview may describe the slices after docs are synchronized.
Promotion remains explicit-only; no file under `workflow/versions/v3/execution/**` is written by this discussion or by
direct implementation in the current worktree.
