# v-template Workflow Template Reference

`v-template` is the managed template reference instance for AreaMatrix workflow artifacts.
It proves the docs discussion -> middle-layer -> changes -> plans -> drafts -> queue
-> promotion preview -> projection -> closeout chain without representing a real product
version or a live execution queue.

## Boundaries

- It is a golden reference for templates and doctors.
- It must not be promoted into live `tasks/prompts/**`.
- It must not write `tasks/prompts/_shared/progress.json`.
- `./dev workflow init --version v-template` is intentionally rejected.
- Future real versions can still use normal `vN` names, including `v2`.

## Checks

```bash
./dev workflow check-template
./dev changes doctor
./dev workflow middle --version v-template doctor
./dev workflow baseline doctor
./dev workflow plan doctor
./dev workflow drafts doctor
./dev workflow queue doctor
./dev workflow promote --version v-template apply --preview
./dev workflow project doctor
./dev workflow closeout doctor
```

`project` and `closeout` remain `blocked` by design for this reference instance:
there is no live task-loop verify/checkpoint evidence, so the template cannot
claim `done`.
