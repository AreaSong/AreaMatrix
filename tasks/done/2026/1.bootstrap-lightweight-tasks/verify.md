# Verify Bootstrap Lightweight Task Tracking

## Read

- `tasks/README.md`
- `tasks/done/2026/1.bootstrap-lightweight-tasks/task.yaml`
- `tasks/done/2026/1.bootstrap-lightweight-tasks/task.md`
- `tasks/done/2026/1.bootstrap-lightweight-tasks/evidence.md`
- `scripts/dev_tools/tasks.py`
- `scripts/dev_tools/test_tasks_tools.py`

## Check

- The task directory name matches `1.bootstrap-lightweight-tasks`.
- `task.yaml` has `id: 1`, `slug: bootstrap-lightweight-tasks`, and
  `status: done`.
- The task appears under `done/2026` in `./dev tasks status` and
  `./dev tasks list`.
- `./dev tasks show 1` reads this archived task.
- No live workflow execution path, task-loop log, run summary, lock, or
  checkpoint state is created.

## Validation

- `python3 -m py_compile scripts/dev_tools/*.py scripts/task_loop/*.py`
- `python3 -m unittest scripts.dev_tools.test_tasks_tools scripts.dev_tools.test_backlog_tools`
- `./dev tasks status`
- `./dev tasks list`
- `./dev tasks show 1`
- `./task-loop check`
- `./dev check governance`
- `./dev check prompts`
- `git diff --check`

## Pass

PASS when the archived task is script-visible, validation passes, and no
forbidden state path is created or modified.

## Fail

FAIL when `./dev tasks` cannot find task `1`, the task metadata does not match
the directory, validation fails, or the change writes live execution state.
