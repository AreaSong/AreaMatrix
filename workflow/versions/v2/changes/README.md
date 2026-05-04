# v2 Change Files

This folder holds AI-readable YAML tracking files for future v2 work.

Required top-level fields:

- `id`
- `title`
- `version: v2`
- `status`
- `features`

Required feature fields:

- `id`
- `module`
- `intent`
- `docs.source`
- `risk.level`
- `risk.boundaries`
- `task_split`

Optional fields include `depends_on`, `docs.update`, `docs.api`, and `docs.udl`.

`./dev changes doctor` validates structure, duplicate feature IDs, dependency references, missing docs, and risk fields. `./dev changes preview` prints the future task order and validation hints without generating prompts.
