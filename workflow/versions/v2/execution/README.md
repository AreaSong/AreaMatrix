# v2 Execution

This is the version-local execution target for `v2`.

It stays empty except for this README until promotion is explicitly approved.
The explicit apply step initializes `_shared/` runtime files and then writes
version-local task, manifest, copy-ready, verify-ready, and progress artifacts.
It must not copy v1 historical progress or task-loop evidence.

Expected initial shape after promotion apply:

```text
execution/
  _shared/
  phase-0/
  phase-1/
  phase-2/
  phase-3/
  phase-4/
  phase-5/
  ...
```
