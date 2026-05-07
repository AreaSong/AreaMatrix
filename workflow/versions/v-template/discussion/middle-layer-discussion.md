# v-template Middle-layer Discussion

## Workflow Carry-forward

- Version: `v-template`
- Discussion feeds `middle-layer/*.yaml`.
- Middle-layer feeds `changes/*.yaml`.
- Changes feed workflow plans.
- Plans feed task drafts.
- Drafts feed queue candidates.
- Queue candidates feed promotion preview.
- Promotion preview feeds projection and closeout checks only; it must not write live `tasks/prompts/**`.

## Required Sync Targets

- Docs: `workflow/architecture.md`, `workflow/pipeline.md`, `workflow/templates/README.md`
- API: none
- UDL: none
- Tasks: no live tasks; template drafts only

## Layer Decisions

- `middle-layer`: ready as template reference ledger.
- `changes`: ready as template reference changes ledger.
- `plans`: ready as generated review artifacts.
- `drafts`: ready as generated copy/verify examples.
- `queue`: ready as version-local queue candidates.
- `promotion`: preview-only and blocked from apply write.
