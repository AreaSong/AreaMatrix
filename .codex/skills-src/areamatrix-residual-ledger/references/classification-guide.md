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
- Use `deferred` when an item is intentionally postponed to another evidence path.
- Use `reference-only` for historical or non-current material.
- Use `template-only` for template artifacts that are intentionally not executable.
- Use `accepted-exception` for closeout-approved historical gaps.
- Use `closed` only when the linked source confirms closure.

## Docs Boundary

Do not move product docs into `workflow/residuals/**` just because they contain unfinished-sounding words. Keep product requirements in `docs/**`; remove task-like formatting when needed, then add or update a residual index entry only when the wording can affect planning, release, or collaboration judgment.

## Task Conversion Gate

Before creating `tasks/active/**`, require all of the following:

1. The residual has `executable_task: true`, or a maintainer explicitly asks to create a task.
2. The authoritative source has owner, scope, validation, and close condition.
3. The work does not require workflow discussion or promotion first.
4. The task will not write live execution `progress.json`, task-loop logs, run summaries, runner locks, checkpoint state, branches, commits, or tags.
