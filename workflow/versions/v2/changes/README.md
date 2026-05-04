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
- `doc_changes`
- `code_impacts`
- `risk.level`
- `risk.boundaries`
- `task_split`

Optional fields include `depends_on`, `docs.update`, `docs.api`, and `docs.udl`.

IDs are path-safe semantic slugs. Feature IDs must start with `v2-`, for example `v2-search-query`; task split IDs should be short slugs such as `docs-contract` or `core-query`.

`./dev changes doctor` validates structure, duplicate feature IDs, dependency references, missing docs, risk fields, and path-safe IDs. `./dev changes preview` prints the future task order and validation hints without generating prompts.

`doc_changes` is the docs-change ledger source. Each entry records `file`, `operation`, `line_start`, `line_end`, `heading`, `excerpt`, `summary`, `depends_on`, and related `tasks`. `./dev workflow doctor` checks the line range, heading, and excerpt to catch docs drift.

`code_impacts` separates `existing`, `expected`, and `tests`. Existing paths must exist; expected paths may be future implementation targets.

`./dev changes generate` renders the review draft package:

```bash
./dev changes generate
./dev changes generate --file workflow/versions/v2/changes/search.yaml
./dev changes generate --feature v2-search-query
```

Default mode prints full drafts to stdout and writes nothing. Explicit writes go to `workflow/versions/v2/drafts/` unless `--out-dir` is provided:

```bash
./dev changes generate --write
./dev changes generate --write --out-dir /tmp/areamatrix-v2-drafts
./dev changes generate --write --force
```

Each feature writes a three-piece draft set:

- `manifest.md`
- `<task-id>.copy.md`
- `<task-id>.verify.md`

These drafts are review artifacts only. They do not enter `tasks/prompts/**`, do not update live progress, and do not start the task-loop.
