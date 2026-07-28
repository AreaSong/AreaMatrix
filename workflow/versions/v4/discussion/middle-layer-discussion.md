# v4 Observability And Diagnostics Middle-layer Discussion

## Workflow Carry-forward

- Version: `v4`
- Discussion must feed `changes/*.yaml`.
- Changes must feed docs-change ledger plans.
- Plans and drafts must keep docs/API/UDL/task sync targets explicit.
- Queue candidates use the version-local queue before execution mapping is configured.
- Promotion preview must not write version execution or historical `workflow/versions/v1-mvp/execution/**`.

## Local Queue

- Local phase: `phase-0`
- Local batch: `0-1`
- Local task start: `task-01`

## Required Sync Targets

- Docs: product privacy and surfaces, workflows, user settings and troubleshooting, error UX,
  settings UX, FFI, macOS/concurrency architecture, Core API/errors, observability, testing, and
  performance.
- API: structured observability initialization, configuration, health, flush, event sink, trace
  context, and compatibility behavior for the existing logging API.
- UDL: records/enums/callbacks for configuration, event envelopes, trace context, privacy-safe
  resources, health, and the Core event sink.
- Tasks: separate docs/schema, Core, platform store, import trace, user UI, developer UI, diagnostic
  package, migration, security, and read-only verification slices.

## Feature Carry-forward

- `observability-contract`: event identity, modes, privacy types, action/component catalogs, and
  compatibility rules.
- `core-tracing`: one-time subscriber, bounded delivery, callback lifetime, sanitization, health,
  flush deadline, and tests.
- `macos-observability`: OSLog, actor-owned ring buffer, rolling JSONL, retention, disk budget,
  signposts, incident freezing, and health.
- `import-trace`: semantic UI action through Bridge and Core import/storage spans without changing
  transaction or file-safety behavior.
- `diagnostics-ui`: localized activity/problem center, mode controls, incident capture, developer
  timeline/tree/graph/terminal/raw views, filters, expected-vs-actual trace, and trace diff.
- `diagnostic-package`: manifest, events, environment, privacy report, summary, checksums, optional
  separately confirmed metadata snapshot/attachments, bounded parser, and offline viewer.
- `validation-and-governance`: privacy abuse cases, hostile filenames and packages, backpressure,
  disk-full, crash/panic, localization, bindings, Core/macOS coverage, docs drift, and review evidence.

## Layer Decisions

- `changes`: approved after discussion doctor passes.
- `plans`: approved after middle-layer/change consistency passes.
- `drafts`: implementation and read-only acceptance remain separate.
- `queue`: version-local candidates only until explicit promotion.
- `promotion`: blocked until execution mapping is configured.
- `execution`: blocked until promotion is approved.
