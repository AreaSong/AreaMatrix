# Execution Template

`execution/` is the version-local target for approved workflow tasks after promotion.

Standard location:

```text
workflow/versions/<version>/execution/
```

Initial hard migration should preserve the historical `workflow/versions/<version>/execution/**` internal
shape inside this directory before any deeper naming cleanup:

```text
execution/
  _shared/
  phase-0/
  phase-1/
  phase-2/
  phase-3/
  phase-4/
```

After scripts and validation are stable, execution material may be normalized
inside the same version-local directory:

```text
execution/
  _shared/
  phases/
  logs/
  checkpoints/
  reports/
```

`execution/` must not be written from discussion, middle-layer, changes, plans,
drafts, queue, or promotion preview. It is written only by an explicit promote /
apply step after approval.
