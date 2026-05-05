"""Workflow version initialization helpers."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from .changes import DraftArtifact, display_path, write_artifacts
from .middle_layer import middle_layer_readme


VERSION_RE = re.compile(r"^v[2-9][0-9]*$")
VERSION_ROOT = Path("workflow/versions")
LAYER_READMES = {
    "middle-layer": "Middle-layer",
    "changes": "Change Files",
    "plans": "Plans",
    "drafts": "Drafts",
    "queue": "Queue Candidates",
    "promotion": "Promotion Preview",
}


def validate_init_version(version: str) -> list[str]:
    if version == "v1-mvp":
        return ["workflow init cannot create v1-mvp; it is the historical live queue record"]
    if not VERSION_RE.fullmatch(version):
        return ["workflow init version must look like v3, v4, or v10"]
    if version == "v2":
        return ["workflow init cannot recreate v2; v2 is an existing compatibility instance"]
    return []


def version_title(version: str, title: str | None) -> str:
    return title.strip() if title and title.strip() else f"AreaMatrix {version} planning workflow"


def default_version_root(root: Path, version: str, out_dir: str | None) -> Path:
    path = Path(out_dir) if out_dir else root / VERSION_ROOT / version
    return path if path.is_absolute() else root / path


def version_yaml(version: str, title: str) -> str:
    return f"""id: {version}
title: {title}
status: planning
depends_on:
  - v1-mvp
live_queue: ""
middle_layers: required
discussion:
  required: true
  status: required-before-changes
gate: queue-only-until-v1-complete
promotion: explicit-only
local_queue:
  phase: phase-0
  batch: 0-1
  batch_slug: {version}-planning
  start_task: 1
promotion_preview:
  target_queue: tasks/prompts
  live_mapping: pending
archive_policy: archive-after-complete
"""


def docs_discussion(version: str) -> str:
    return f"""# {version} Docs Discussion

## Feature Intent

- Version: `{version}`
- Intent:
- User paths:

## Exact Docs

- `docs/README.md`

## Contention Points

- None yet.

## Non-goals

- Do not modify live `tasks/prompts/**` during discussion.
- Do not generate copy-ready / verify-ready prompts before decisions are approved.

## Acceptance Boundary

- Docs scope is understood before writing changes YAML.
- Open questions and blockers are resolved or explicitly deferred in `decisions.yaml`.
"""


def middle_layer_discussion(version: str) -> str:
    return f"""# {version} Middle-layer Discussion

## Workflow Carry-forward

- Version: `{version}`
- Discussion must feed `changes/*.yaml`.
- Changes must feed docs-change ledger plans.
- Plans and drafts must keep docs/API/UDL/task sync targets explicit.
- Queue candidates use the version-local queue before live promotion mapping is configured.
- Promotion preview must not write live `tasks/prompts/**`.

## Local Queue

- Local phase: `phase-0`
- Local batch: `0-1`
- Local task start: `task-01`

## Required Sync Targets

- Docs:
- API:
- UDL:
- Tasks:

## Layer Decisions

- `changes`: waiting for discussion approval.
- `plans`: waiting for changes.
- `drafts`: waiting for plans.
- `queue`: waiting for drafts.
- `promotion`: blocked until live mapping is configured.
"""


def decisions(version: str) -> str:
    return f"""version: {version}
status: draft
allow_changes: false
exact_docs:
  - docs/README.md
decisions:
  - id: docs-scope
    status: open
    summary: Confirm the exact docs scope before writing changes YAML.
open_questions:
  - id: docs-scope
    status: open
    question: Which docs sections are the source of truth for this version?
blockers:
  - id: discussion-not-approved
    status: open
    summary: Discussion has not approved changes generation yet.
risk_boundaries:
  - Do not write live tasks/prompts from discussion.
next_layers:
  changes: blocked
  plans: blocked
  drafts: blocked
  queue: blocked
  promotion: blocked
"""


def layer_readme(version: str, layer: str, title: str) -> str:
    if layer == "middle-layer":
        detail = "Middle-layer ledgers are feature-level implementation intent records created after discussion approval."
    elif layer == "changes":
        detail = "This directory starts with README only. Add real change YAML after discussion doctor passes."
    elif layer == "promotion":
        detail = "Promotion preview is blocked until live mapping is explicitly configured."
    else:
        detail = f"{title} are review artifacts for {version}; they do not write live tasks/prompts."
    return f"""# {version} {title}

{detail}

- Version-local queue starts at `phase-0 / 0-1 / task-01`.
- Live `tasks/prompts/**` mapping is pending and must be configured later.
- Do not modify `tasks/prompts/**` or `tasks/prompts/_shared/progress.json` from this layer.
"""


def workflow_readme(version: str) -> str:
    return f"""# {version} Workflow

`{version}` is a planning workflow instance created from the reusable v* template.

## Flow

```text
discussion
-> middle-layer
-> changes
-> plans
-> drafts
-> queue
-> promotion preview
-> future explicit promote into tasks/prompts/**
```

The version-local queue starts at `phase-0 / 0-1 / task-01`. Future live mapping
is pending and must be configured before promotion preview can target global
`tasks/prompts/**` labels.
"""


def init_artifacts(root: Path, version: str, title: str | None, out_dir: str | None) -> list[DraftArtifact]:
    target = default_version_root(root, version, out_dir)
    resolved_title = version_title(version, title)
    artifacts = [
        DraftArtifact(target / "version.yaml", version_yaml(version, resolved_title)),
        DraftArtifact(target / "README.md", workflow_readme(version)),
        DraftArtifact(target / "discussion/docs-discussion.md", docs_discussion(version)),
        DraftArtifact(target / "discussion/middle-layer-discussion.md", middle_layer_discussion(version)),
        DraftArtifact(target / "discussion/decisions.yaml", decisions(version)),
        DraftArtifact(target / "middle-layer/README.md", middle_layer_readme(version)),
    ]
    for layer, title_value in LAYER_READMES.items():
        if layer == "middle-layer":
            continue
        artifacts.append(DraftArtifact(target / layer / "README.md", layer_readme(version, layer, title_value)))
    return artifacts


def run_workflow_init(root: Path, args: argparse.Namespace) -> int:
    if args.force and not args.write:
        print("workflow init: --force requires --write")
        return 1
    errors = validate_init_version(args.version)
    if errors:
        print("workflow init: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    artifacts = init_artifacts(root, args.version, args.title, args.out_dir)
    if not args.write:
        print("Workflow version init")
        print("- mode: preview only; no files written")
        print("- live queue: not modified")
        print("- progress file: not modified")
        for artifact in artifacts:
            print()
            print(f"--- {display_path(root, artifact.path)} ---")
            print(artifact.content.rstrip())
        return 0
    try:
        written = write_artifacts(artifacts, force=args.force, label="workflow init file")
    except FileExistsError as exc:
        print(f"workflow init: {exc}")
        return 1
    print("workflow init: wrote files")
    print(f"- version: {args.version}")
    print(f"- root: {artifacts[0].path.parent}")
    print(f"- files: {len(written)}")
    for path in written:
        print(f"  - {path}")
    return 0
