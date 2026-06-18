# v2 Docs Discussion

## Feature Intent

- Version: `v2`
- Stage name: Stage 2 Experience Improvement.
- Intent: turn the long-term roadmap Stage 2 scope into a real v2 planning
  track after Stage 1 MVP historical execution is archived.
- User paths:
  - A maintainer reads `docs/roadmap/milestones.md` to confirm the Stage 2
    product themes before writing v2 change ledgers.
  - A maintainer keeps Stage 1 internal source docs archived under
    `workflow/versions/v1-mvp/` instead of treating them as current v2 scope.
  - A maintainer reviews v2 middle-layer and changes artifacts before any
    drafts, queue candidates, promotion preview, or execution files are
    generated.

## Exact Docs

- `docs/README.md`
- `docs/roadmap/milestones.md`

## Contention Points

- v2 starts from the formal roadmap Stage 2 "体验完善" scope: advanced file
  operations, tags, full-text search, conflict resolution UI, custom
  classification UI, and UX details.
- The first v2 planning feature is scope confirmation only; implementation
  slices still need middle-layer, changes, plans, drafts, queue, and explicit
  promotion gates.
- Archived Stage 1 internal Stage 2/3/4 specs may be used for historical reference only.
- Stage 1 formal distribution blockers remain deferred to v1 release evidence and must not be treated as v2 product scope.

## Non-goals

- Do not modify `workflow/versions/v2/execution/**` during discussion.
- Do not generate copy-ready / verify-ready prompts before decisions are approved.
- Do not treat `workflow/versions/v1-mvp/source-docs/stage-*` historical specs as current v2 requirements.
- Do not close Developer ID, notarization, stapler, clean-Mac first launch, iCloud placeholder M-02, or formal `v0.1.0` tag blockers in v2 planning.

## Acceptance Boundary

- Docs scope is understood before writing changes YAML.
- Open questions and blockers are resolved or explicitly deferred in `decisions.yaml`.
- `workflow/versions/v2/middle-layer/*.yaml` and
  `workflow/versions/v2/changes/*.yaml` may be written after this gate, but
  `workflow/versions/v2/execution/**` remains blocked until explicit promotion
  approval and live mapping.
