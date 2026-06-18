# Verify Example Task

## Read

- `tasks/active/1.example-task/task.yaml`
- `tasks/active/1.example-task/task.md`

## Check

- The implementation matches the goal and non-goals.
- The changed paths stay inside `paths.touch`.
- No path under `paths.forbid` changed.
- Validation evidence is fresh and task-scoped.

## Validation

- `./dev check`

## Pass

PASS only when the task goal is complete, validation evidence is present, and no
forbidden path or scope drift is found.

## Fail

FAIL when behavior is incomplete, validation is missing, forbidden paths changed,
or the task expanded into workflow-level work.
