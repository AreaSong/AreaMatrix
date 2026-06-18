# AreaMatrix Lightweight Tasks

`tasks/` is the lightweight task system for clear, small, independent work that
does not need a full version workflow.

Use `workflow/` for version-level or large feature lifecycles. Use
`tasks/active/` for focused fixes, small UI changes, local tooling updates,
small docs updates, and follow-up bugs from a completed workflow.

## Boundary

- `workflow/`: version workflow, discussion gate, middle-layer, changes, plans,
  drafts, queue candidates, promotion, version-local execution, projection, and
  closeout.
- `workflow/versions/<version>/execution/`: approved live execution queue for a
  version.
- `tasks/active/`: current lightweight tasks with script-visible progress.
- `tasks/done/`: completed lightweight task archive.
- `tasks/backlog/`: candidate pool and planning/governance prompt packages. It
  is not current progress and does not enter the live runner.
- `tasks/templates/`: reusable lightweight task templates.

`tasks/` must not create a second workflow system. Do not add phase trees,
promotion ledgers, queue candidates, `progress.json`, checkpoint state, or a
second task-loop runner under `tasks/`.

## Structure

```text
tasks/
├── README.md
├── active/
│   └── 1.example-task/
│       ├── task.yaml
│       ├── task.md
│       ├── verify.md
│       └── evidence.md
├── done/
│   └── 2026/
├── backlog/
└── templates/
    ├── task.yaml
    ├── task.md
    ├── verify.md
    └── evidence.md
```

`active/`, `done/`, and `templates/` may be absent until the first lightweight
task is created. `backlog/` already exists and keeps its candidate-pool meaning.

## Naming

Active task directories use:

```text
tasks/active/<number>.<slug>/
```

Examples:

```text
tasks/active/1.add-settings-button/
tasks/active/2.fix-sidebar-color/
tasks/active/3.repair-import-error-copy/
```

Rules:

- `<number>` is unique across the repository and never resets by year.
- `<slug>` uses lowercase letters, numbers, and hyphens.
- The directory name uses a dot: `<number>.<slug>`.
- Completed tasks keep the same number and slug under `tasks/done/YYYY/`.

## Task Files

Every lightweight task directory uses four files:

```text
task.yaml
task.md
verify.md
evidence.md
```

- `task.yaml`: machine-readable status, classification, boundaries, and
  validation commands.
- `task.md`: implementation prompt or instructions.
- `verify.md`: read-only acceptance prompt or checklist.
- `evidence.md`: result, changes, validation evidence, and remaining risk.

## Status Model

Allowed `status` values in `task.yaml`:

```text
todo
in_progress
blocked
verify_ready
done
archived
```

`todo`, `in_progress`, `blocked`, and `verify_ready` belong in `tasks/active/`.
`done` and `archived` belong in `tasks/done/YYYY/`.

Allowed `priority` values:

```text
p0
p1
p2
p3
```

Allowed `kind` values:

```text
feature
bugfix
refactor
docs
test
tooling
governance
chore
```

Allowed `risk` values:

```text
low
medium
high
mission-critical
```

Suggested `scope.layer` values:

```text
frontend
backend
core
app
scripts
docs
workflow
governance
assets
```

## Script Visibility

The directory protocol is designed so `./dev tasks` can index all lightweight
task state without reading workflow execution internals.

Read-only commands:

```bash
./dev tasks status
./dev tasks list
./dev tasks doctor
./dev tasks show 1
./dev tasks show 1 --task
./dev tasks show 1 --verify
./dev tasks show 1 --evidence
```

Guarded write command:

```bash
./dev tasks create --title "Add Settings Button" --layer frontend --area apps/macos --feature settings
./dev tasks create --title "Add Settings Button" --layer frontend --area apps/macos --feature settings --write
```

`create` previews by default. It writes only when `--write` is present, and the
write target is limited to `tasks/active/<next-number>.<slug>/`.

Expected lookup behavior:

- `./dev tasks show 1` first checks `tasks/active/1.*/`.
- If no active task matches, it checks `tasks/done/*/1.*/`.
- `./dev tasks status` summarizes active, done, blocked, verify-ready, and
  backlog package counts.
- `./dev backlog list` remains the read-only browser for backlog prompt
  packages.
- `./dev workflow status` remains the version workflow progress surface.
- `./dev tasks create` creates a lightweight active task record only; it does
  not execute the task, promote workflow queue candidates, update
  `progress.json`, or touch task-loop runtime state.

Keep these surfaces distinct:

```text
workflow status      version workflow progress, keyed by v1 / v2 / v-template
lightweight tasks    small independent task progress, keyed by 1 / 2 / 3
backlog packages     candidate package browser, keyed by package slug
```

## Archive Rule

When a lightweight task is complete:

1. Set `status: done` in `task.yaml`.
2. Update `updated` to the completion date.
3. Record PASS evidence in `evidence.md`.
4. Move the directory from `tasks/active/<number>.<slug>/` to
   `tasks/done/YYYY/<number>.<slug>/`.

Do not renumber completed tasks.
