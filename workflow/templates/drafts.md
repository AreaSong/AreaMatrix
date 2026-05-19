# Draft Package Template

Each feature draft package contains:

```text
workflow/versions/v*/drafts/<feature-id>/
  manifest.md
  <task-id>.copy.md
  <task-id>.verify.md
```

Drafts are review artifacts. They are not live tasks and do not change progress.

## Copy-ready Draft Requirements

- Goal and non-goals.
- Source of truth paths.
- Owner / landing.
- Exact allowed and forbidden paths.
- Ordered implementation steps.
- Validation commands.
- Completion report fields, including risks and unverified items.

## Verify-ready Draft Requirements

- Read-only acceptance scope.
- Required source of truth and manifest / draft paths.
- File-by-file evidence checks.
- Validation commands to rerun.
- PASS / FAIL result line and blocker list.

Do not combine copy-ready and verify-ready content in one artifact.
