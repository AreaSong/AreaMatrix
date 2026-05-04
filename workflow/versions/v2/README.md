# v2 Workflow

`v2` is the planning surface for new requirements after the current MVP queue.

The first supported input is `changes/*.yaml`. Each change file should describe features, exact source docs, docs/API/UDL sync targets, dependencies, risk boundaries, and an expected task split.

Use:

```bash
./dev changes doctor
./dev changes preview
```

These commands validate and preview only. They do not write copy-ready or verify-ready prompts, do not edit manifests, and do not connect to `./task-loop`.
