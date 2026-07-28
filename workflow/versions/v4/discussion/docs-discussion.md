# v4 Observability And Diagnostics Docs Discussion

## Feature Intent

- Version: `v4`
- Intent: Deliver a complete, local-first structured observability and diagnostics system shared by
  SwiftUI, the macOS platform layer, CoreBridge, Rust Core, storage, and support workflows.
- User paths:
  - A user reviews a plain-language activity timeline, marks an unknown problem, previews redaction,
    and saves a portable `.amdiagnostic` package without automatic upload.
  - A tester enables a bounded diagnostic session, reproduces a failure, and preserves the events
    before and after the marked incident.
  - A developer enables developer mode in any installed build and inspects the same causal chain as
    a timeline, tree, graph, terminal stream, raw structured data, or Instruments signpost.
  - A support recipient opens an untrusted diagnostic package offline, verifies checksums and limits,
    and relates actual events to the registered action and component contracts.

## Exact Docs

- `docs/product/privacy.md`
- `docs/product/product-surfaces.md`
- `docs/product/workflows.md`
- `docs/user-guide/settings.md`
- `docs/user-guide/troubleshooting.md`
- `docs/ux/error-messages.md`
- `docs/ux/settings-panel.md`
- `docs/architecture/ffi-design.md`
- `docs/architecture/macos-frontend-architecture.md`
- `docs/architecture/concurrency.md`
- `docs/api/core-api.md`
- `docs/api/error-codes.md`
- `docs/development/observability.md`
- `docs/development/testing.md`
- `docs/development/performance.md`

## Contention Points

- Runtime logs, interaction traces, transactional `change_log`, AI call audit, metadata snapshots,
  and shareable diagnostic packages remain distinct data products even when they share identity.
- Every installed build exposes standard, diagnostic, and developer modes; defaults, consent,
  retention, privacy, and resource limits differ, but availability is not compile-time hidden.
- OSLog remains the Apple developer sink. Portable support packages use the application-owned
  structured store and never scrape OSLog as their source of truth.
- Remote upload is not inferred from diagnostic export. Any future transport requires a separately
  approved endpoint, authentication, retention, deletion, withdrawal, and service security contract.
- Runtime logging failures never block user-file operations. Transactional business `change_log`
  behavior remains unchanged and may block the owning transaction under its existing contract.
- A business `operation_id` and a diagnostic `trace_id` have different lifecycle semantics and are
  linked rather than collapsed.

## Non-goals

- Do not record screen video, pointer coordinates, hover, scrolling, individual keystrokes, file or
  note contents, secrets, tokens, or complete AI request and response bodies.
- Do not add product analytics, behavioral telemetry, advertising measurement, automatic upload,
  remote silent activation, or executable replay.
- Do not use runtime logs as the recovery source of truth or replace `change_log` / `ai_call_log`.
- Do not write runtime logs into user-controlled repository roots by default.
- Do not change import, staging, DB, watcher, iCloud, or user-file mutation semantics while adding
  observation spans.
- Do not modify `workflow/versions/v4/execution/**` during discussion.
- Do not modify historical `workflow/versions/v1-mvp/execution/**` during discussion.
- Do not generate copy-ready / verify-ready prompts before decisions are approved.

## Acceptance Boundary

- Standard, diagnostic, and developer modes are user-accessible and bounded by explicit disk,
  retention, privacy, and deletion controls.
- A semantic UI action can be correlated across Swift, CoreBridge, Rust, DB/filesystem spans, and the
  resulting UI state without putting user content into the event envelope.
- The event schema, action catalog, component catalog, redaction policy, backpressure policy,
  rotation, incident freezing, health reporting, and compatibility rules are versioned and tested.
- User and developer presentations consume the same event identities while applying audience-specific
  fields and localized presentation.
- `.amdiagnostic` generation is local, user-triggered, previewable, checksummed, bounded, and safe to
  inspect as untrusted input.
- Logging failure, queue saturation, disk exhaustion, malformed diagnostic packages, and callback
  lifecycle failures have explicit degraded behavior and do not corrupt business state.
- Open questions and blockers are resolved or explicitly deferred in `decisions.yaml` before changes.
