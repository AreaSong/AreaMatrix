# Bootstrap Lightweight Task Tracking

## Goal

Record the completed lightweight task system bootstrap as the first real
`tasks/` entry, so `./dev tasks status/list/show` can prove that archived
lightweight tasks are script-visible.

## Non-goals

- Do not create a second task-loop runner.
- Do not write `workflow/versions/<version>/execution/**`.
- Do not create `progress.json`, checkpoint state, phase trees, queue
  candidates, or promotion artifacts under `tasks/`.
- Do not change product behavior.

## Context

The lightweight task system now has a documented protocol under `tasks/`, plus
read-only `./dev tasks` commands that index `tasks/active/**` and
`tasks/done/**`. This task records that bootstrap as a completed lightweight
task and verifies the `done` lookup path.

## Steps

1. Add the completed task record under
   `tasks/done/2026/1.bootstrap-lightweight-tasks/`.
2. Keep the task record to the four-file protocol: `task.yaml`, `task.md`,
   `verify.md`, and `evidence.md`.
3. Run the validation commands from `task.yaml`.
4. Confirm `./dev tasks status`, `./dev tasks list`, and `./dev tasks show 1`
   read the archived task.

## Notes

This is a record of completed infrastructure work, not a new product feature.
