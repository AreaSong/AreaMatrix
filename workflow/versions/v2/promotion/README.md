# v2 Promotion Preview

Promotion previews map reviewed workflow tasks to future live task labels.

Use:

```bash
./dev workflow promote --version v2 --preview
./dev workflow promote --version v2 --feature v2-search-query --preview
./dev workflow promote --version v2 --write
```

The default output is terminal-only and has no side effects. `--write` writes
review artifacts such as `promotion.yaml` and `promotion.md` into this directory.

While `v1-mvp` is `live-running`, promotion remains blocked. Preview artifacts do
not modify `tasks/prompts/**`, do not modify `progress.json`, and do not start
`./task-loop`.
