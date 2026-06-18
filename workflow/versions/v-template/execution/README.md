# v-template Execution

This directory proves that the standard workflow skeleton includes a version-local
execution layer.

`v-template` is a template reference. It must not receive promoted task files,
write progress, or claim task-loop evidence.

Expected future shape after approved promotion apply in a real version:

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
