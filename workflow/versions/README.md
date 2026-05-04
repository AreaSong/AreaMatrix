# AreaMatrix Workflow Versions

This directory tracks prompt-workflow versions without moving the live v1 task queue.

- `v1-mvp/` records the current `tasks/prompts/**` queue as the active MVP workflow. It is a placeholder only until the 637-task queue is finished and archived.
- `v2/changes/` records future feature changes as structured YAML. These files are validated and previewed by `./dev changes`, but they do not generate prompt files and do not join the live task-loop queue.

Current live state remains:

- prompts: `tasks/prompts/**`
- progress: `tasks/prompts/_shared/progress.json`
- runner: `./task-loop`
- console: `./dev`
