# Residual Classification Guide

Use this guide to keep AreaMatrix residual tracking separate from product docs, release evidence, closeout records, and live task state.

## Classification

| Type | Meaning | Can become a task? |
|---|---|---|
| `release-evidence` | Formal release or alpha evidence is missing or blocked. | Only after the release owner defines executable local work. |
| `closeout-exception` | Historical gap accepted by closeout. | No; do not rewrite historical logs or Git state. |
| `historical-reference` | Non-current vision or planning material. | Only through a fresh planning gate. |
| `template-reference` | Template or sample version material. | No; create a real version separately. |
| `backlog-reference` | Closed or inactive backlog package. | Only if reopened by planning. |
| `product-doc-marker` | Product docs contain words that look like task state but describe product behavior. | No; fix wording or index ambiguity, not task state. |

## Status Rules

- Use `open` only when a real unresolved item exists and has no clearer blocker class.
- Use `blocked-external` when closure needs external environment, accounts, devices, certificates, or third-party state.
- Use `blocked-decision` when closure needs maintainer or release decision.
- Use `mixed-blocked` only on aggregate version index rows that also include `status_breakdown`; do not use it for individual residual items.
- Use `deferred` when an item is intentionally postponed to another evidence path.
- Use `reference-only` for historical or non-current material.
- Use `template-only` for template artifacts that are intentionally not executable.
- Use `accepted-exception` for closeout-approved historical gaps.
- Use `closed` only when the linked source confirms closure.

## Reporting Rule

When answering broad questions like "还有什么问题没有解决", "还有哪些未完成", or "what remains unresolved", use two groups:

1. **Current unresolved blockers**: `open`, `blocked-external`, `blocked-decision`, and relevant `deferred` items that still affect release, planning, or execution.
2. **Indexed but not current tasks**: `reference-only`, `template-only`, `accepted-exception`, and closed backlog references.

Always include both groups when they exist. The answer must cover every ID in `workflow/residuals/README.md` "全量 residual ID 清单" and must not compress non-current items into prose. For example, AreaFlow must appear as `global-ref-areaflow` / `reference-only`, with the explanation that it is historical vision material and not a current AreaMatrix task.

Conclusion wording:

- Good: "当前没有 active task；当前阻塞正式 alpha 的是 release evidence / release decision。完整 residual ledger 还包括 reference-only、template-only、accepted-exception、closed backlog 和 product-doc marker 项。"
- Avoid: "真正没解决的只有正式 Stage 1 alpha 发布证据。" This hides indexed residuals unless followed immediately by the full residual inventory.

Completeness check before answering:

1. Read `workflow/residuals/README.md`.
2. Read every `version_residuals[].source` from `workflow/residuals/residuals.yaml`.
3. Compare the response against the full residual ID inventory.
4. If any ID is omitted, fix the response before sending it.

## Docs Boundary

Do not move product docs into `workflow/residuals/**` just because they contain unfinished-sounding words. Keep product requirements in `docs/**`; remove task-like formatting when needed, then add or update a residual index entry only when the wording can affect planning, release, or collaboration judgment.

## Task Conversion Gate

Before creating `tasks/active/**`, require all of the following:

1. The residual has `executable_task: true`, or a maintainer explicitly asks to create a task.
2. The authoritative source has owner, scope, validation, and close condition.
3. The work does not require workflow discussion or promotion first.
4. The task will not write live execution `progress.json`, task-loop logs, run summaries, runner locks, checkpoint state, branches, commits, or tags.

## Version Bootstrap Boundary

For a new version such as `v2`, ordinary discussion open questions are not residuals. Keep them in `workflow/versions/<version>/discussion/decisions.yaml` until maintainers explicitly decide that an item should survive discussion handoff as one of:

- `open`
- `blocked-external`
- `blocked-decision`
- `mixed-blocked` only for aggregate version index rows with `status_breakdown`
- `deferred`
- `accepted-exception`
- `reference-only`
- `template-only`

When that happens, create or update `workflow/versions/<version>/residuals/README.md` and `residuals.yaml`, then add or update the matching `version_residuals` entry in `workflow/residuals/residuals.yaml`. Do not add discussion-only questions to `tasks/active/**`.
