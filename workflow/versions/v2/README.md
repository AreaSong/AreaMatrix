# v2 Workflow

`v2` is the first reusable v* workflow instance for requirements after the current MVP queue.

The supported flow is:

```text
discussion compatibility exemption
-> changes/*.yaml
-> plans/*.plan.md
-> drafts/<feature>/
-> queue/<feature>/
-> promotion/
-> future explicit promote into tasks/prompts/**
```

While `v1-mvp` is `live-running`, v2 may reach queue candidates but must not promote into the live task queue.
`v2` predates the discussion gate, so `version.yaml` records an existing-instance
compatibility exemption. Future versions must create and pass `discussion/`
before writing `changes/`.

Use:

```bash
./dev workflow doctor
./dev workflow status
./dev workflow discuss --version v2 doctor
./dev workflow discuss --version v2 preview
./dev workflow plan --version v2
./dev workflow queue --version v2
./dev workflow promote --version v2 --preview
./dev workflow promote --version v2 --feature v2-search-query --preview
./dev changes doctor
./dev changes preview
./dev changes generate
```

`workflow plan` generates the docs-change ledger. `workflow queue` generates queue candidates. `changes generate` remains the compatible draft generator.
`workflow promote` previews how semantic workflow tasks would map into future
numeric `tasks/prompts/**` labels; it is blocked while v1 is live and does not
write the live queue.

To write drafts explicitly:

```bash
./dev changes generate --write
./dev changes generate --feature v2-search-query --write
./dev changes generate --write --out-dir /tmp/areamatrix-v2-drafts
```

The default write target is `workflow/versions/v2/drafts/`. Existing draft files are protected; use `--force` with `--write` only when intentionally replacing a draft package:

```bash
./dev changes generate --write --force
```

Plans, drafts, and queue candidates are review artifacts. They are not `tasks/prompts/**`, do not edit v1 manifests, do not write `progress.json`, and do not connect to `./task-loop`.
Promotion previews are also review artifacts. Explicit `--write` writes only
`workflow/versions/v2/promotion/` preview files; it still does not promote.
