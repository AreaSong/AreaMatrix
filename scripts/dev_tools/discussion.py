"""Workflow discussion gate helpers."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Sequence

from .changes import DraftArtifact, as_list, display_path, parse_yaml_subset, write_artifacts


VERSION_ROOT = Path("workflow/versions")
DISCUSSION_ROOT_NAME = "discussion"
REQUIRED_DISCUSSION_FILES = ["docs-discussion.md", "middle-layer-discussion.md", "decisions.yaml"]
DISCUSSION_TEMPLATES = REQUIRED_DISCUSSION_FILES
CLOSED_STATUSES = {"resolved", "closed", "accepted", "deferred", "not-applicable", "none"}


def discussion_dir(root: Path, version: str) -> Path:
    return root / VERSION_ROOT / version / DISCUSSION_ROOT_NAME


def output_root(root: Path, version: str, out_dir: str | None) -> Path:
    path = Path(out_dir) if out_dir else discussion_dir(root, version)
    return path if path.is_absolute() else root / path


def read_version_data(root: Path, version: str) -> tuple[list[str], dict[str, Any] | None, Path]:
    path = root / VERSION_ROOT / version / "version.yaml"
    if not path.is_file():
        return [f"missing version record: {display_path(root, path)}"], None, path
    try:
        data = parse_yaml_subset(path.read_text(encoding="utf-8"), path)
    except ValueError as exc:
        return [str(exc)], None, path
    if not isinstance(data, dict):
        return [f"{display_path(root, path)}: top-level YAML must be a mapping"], None, path
    if data.get("id") != version:
        return [f"{display_path(root, path)}: id must match requested version {version}"], data, path
    return [], data, path


def discussion_config(data: dict[str, Any]) -> dict[str, Any]:
    raw = data.get("discussion")
    return raw if isinstance(raw, dict) else {}


def discussion_gate_label(version: str, data: dict[str, Any]) -> str:
    config = discussion_config(data)
    status = str(config.get("status", "")).strip()
    if version == "v1-mvp" or data.get("middle_layers") == "skipped":
        return "skipped"
    if status == "template-reference":
        return "template-reference"
    if config.get("required") is False:
        return "not-required"
    return "required"


def discussion_required(version: str, data: dict[str, Any]) -> bool:
    return discussion_gate_label(version, data) == "required"


def discussion_gate_message(version: str, data: dict[str, Any]) -> str:
    config = discussion_config(data)
    label = discussion_gate_label(version, data)
    reason = str(config.get("reason", "")).strip()
    if label == "skipped":
        return f"{version}: discussion gate skipped"
    if label == "template-reference":
        suffix = f"; {reason}" if reason else ""
        return f"{version}: managed template reference{suffix}"
    if label == "not-required":
        suffix = f"; {reason}" if reason else ""
        return f"{version}: discussion gate not required{suffix}"
    return f"{version}: discussion gate required"


def docs_discussion_template(version: str) -> str:
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

## Acceptance Boundary

- Docs scope is understood before writing changes YAML.
- Open questions and blockers are resolved or explicitly deferred in `decisions.yaml`.
"""


def middle_layer_template(version: str) -> str:
    return f"""# {version} Middle-layer Discussion

## Workflow Carry-forward

- Version: `{version}`
- Discussion must feed `changes/*.yaml`.
- Changes must feed docs-change ledger plans.
- Plans and drafts must keep docs/API/UDL/task sync targets explicit.
- Queue candidates and promotion preview must not write live `tasks/prompts/**`.

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
- `promotion`: preview only.
"""


def decisions_template(version: str) -> str:
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


def discussion_artifacts(root: Path, version: str, out_dir: str | None) -> list[DraftArtifact]:
    target = output_root(root, version, out_dir)
    return [
        DraftArtifact(target / "docs-discussion.md", docs_discussion_template(version)),
        DraftArtifact(target / "middle-layer-discussion.md", middle_layer_template(version)),
        DraftArtifact(target / "decisions.yaml", decisions_template(version)),
    ]


def load_decisions(path: Path) -> tuple[list[str], dict[str, Any] | None]:
    try:
        data = parse_yaml_subset(path.read_text(encoding="utf-8"), path)
    except ValueError as exc:
        return [str(exc)], None
    if not isinstance(data, dict):
        return [f"{path}: top-level YAML must be a mapping"], None
    return [], data


def unresolved_items(data: dict[str, Any], key: str) -> list[str]:
    unresolved: list[str] = []
    for index, item in enumerate(as_list(data.get(key)), start=1):
        if isinstance(item, str):
            if item.strip():
                unresolved.append(item)
            continue
        if not isinstance(item, dict):
            unresolved.append(f"{key} #{index}")
            continue
        status = str(item.get("status", "")).strip()
        if status not in CLOSED_STATUSES:
            label = str(item.get("id") or item.get("summary") or item.get("question") or f"{key} #{index}")
            unresolved.append(label)
    return unresolved


def validate_exact_docs(root: Path, data: dict[str, Any], docs_text: str, prefix: str) -> list[str]:
    errors: list[str] = []
    exact_docs = as_list(data.get("exact_docs"))
    if not exact_docs:
        return [f"{prefix}: exact_docs must be a non-empty list"]
    for doc in exact_docs:
        if not isinstance(doc, str) or not doc.strip():
            errors.append(f"{prefix}: exact_docs values must be strings")
            continue
        doc_path = Path(doc)
        resolved = doc_path if doc_path.is_absolute() else root / doc_path
        if not resolved.is_file():
            errors.append(f"{prefix}: Exact Docs path does not exist: {doc}")
        if doc not in docs_text:
            errors.append(f"{prefix}: docs-discussion.md must mention Exact Docs path: {doc}")
    return errors


def validate_decisions(root: Path, version: str, decisions_path: Path, docs_path: Path) -> list[str]:
    errors, data = load_decisions(decisions_path)
    if errors or data is None:
        return errors
    prefix = display_path(root, decisions_path)
    if data.get("version") != version:
        errors.append(f"{prefix}: version must be {version}")
    if data.get("allow_changes") is not True:
        errors.append(f"{prefix}: allow_changes must be true before entering changes")
    if not as_list(data.get("risk_boundaries")):
        errors.append(f"{prefix}: risk_boundaries must be a non-empty list")
    if not as_list(data.get("decisions")):
        errors.append(f"{prefix}: decisions must be a non-empty list")
    docs_text = docs_path.read_text(encoding="utf-8", errors="replace") if docs_path.is_file() else ""
    errors.extend(validate_exact_docs(root, data, docs_text, prefix))
    for key in ["open_questions", "blockers"]:
        unresolved = unresolved_items(data, key)
        for item in unresolved:
            errors.append(f"{prefix}: unresolved {key[:-1]}: {item}")
    return errors


def validate_discussion_artifacts(root: Path, version: str, directory: Path | None = None) -> list[str]:
    base = directory or discussion_dir(root, version)
    errors: list[str] = []
    paths = {name: base / name for name in REQUIRED_DISCUSSION_FILES}
    for name, path in paths.items():
        if not path.is_file():
            errors.append(f"missing discussion file: {display_path(root, path)}")
    if errors:
        return errors
    docs_text = paths["docs-discussion.md"].read_text(encoding="utf-8", errors="replace")
    middle_text = paths["middle-layer-discussion.md"].read_text(encoding="utf-8", errors="replace")
    if "Exact Docs" not in docs_text:
        errors.append(f"{display_path(root, paths['docs-discussion.md'])}: missing Exact Docs section")
    for keyword in ["changes", "plans", "drafts", "queue", "promotion"]:
        if keyword not in middle_text:
            errors.append(f"{display_path(root, paths['middle-layer-discussion.md'])}: missing layer keyword: {keyword}")
    errors.extend(validate_decisions(root, version, paths["decisions.yaml"], paths["docs-discussion.md"]))
    from .workflow_baseline import baseline_path, validate_baseline

    if baseline_path(root, version).is_file():
        baseline_errors, _ = validate_baseline(root, version, require_file=True)
        errors.extend(baseline_errors)
    return errors


def validate_discussion_for_version(root: Path, version: str, data: dict[str, Any]) -> list[str]:
    if not discussion_required(version, data):
        return []
    return validate_discussion_artifacts(root, version)


def validate_discussion_records(root: Path, records: Sequence[Any]) -> list[str]:
    errors: list[str] = []
    for record in records:
        errors.extend(validate_discussion_for_version(root, str(record.version_id), record.data))
    return errors


def discussion_summary_lines(version: str, data: dict[str, Any]) -> list[str]:
    return [f"- discussion: {discussion_gate_label(version, data)}"]


def print_discussion_preview(root: Path, version: str, data: dict[str, Any]) -> int:
    label = discussion_gate_label(version, data)
    print("Workflow discussion preview")
    print(f"- version: {version}")
    print(f"- gate: {label}")
    print(f"- status: {discussion_gate_message(version, data)}")
    if label != "required":
        print("- next: current version may continue under its recorded discussion policy.")
        return 0
    base = discussion_dir(root, version)
    print(f"- discussion_dir: {display_path(root, base)}")
    for name in REQUIRED_DISCUSSION_FILES:
        path = base / name
        status = "present" if path.is_file() else "missing"
        print(f"- {name}: {status}")
    decisions = base / "decisions.yaml"
    if decisions.is_file():
        _, data = load_decisions(decisions)
        if data:
            print(f"- allow_changes: {data.get('allow_changes')}")
            print(f"- exact_docs: {', '.join(str(item) for item in as_list(data.get('exact_docs'))) or 'None'}")
            blockers = unresolved_items(data, "blockers")
            questions = unresolved_items(data, "open_questions")
            print(f"- unresolved_blockers: {len(blockers)}")
            print(f"- unresolved_open_questions: {len(questions)}")
    print("- next: resolve discussion, set allow_changes: true, then run changes doctor.")
    return 0


def run_workflow_discuss(root: Path, args: argparse.Namespace) -> int:
    if args.discuss_command == "init":
        if args.force and not args.write:
            print("workflow discuss init: --force requires --write")
            return 1
        artifacts = discussion_artifacts(root, args.version, args.out_dir)
        if not args.write:
            print("Workflow discussion init")
            print("- mode: preview only; no files written")
            for artifact in artifacts:
                print()
                print(f"--- {display_path(root, artifact.path)} ---")
                print(artifact.content.rstrip())
            return 0
        try:
            written = write_artifacts(artifacts, force=args.force, label="workflow discussion file")
        except FileExistsError as exc:
            print(f"workflow discuss init: {exc}")
            return 1
        print("workflow discuss init: wrote files")
        print(f"- files: {len(written)}")
        for path in written:
            print(f"  - {path}")
        return 0

    version_errors, data, _ = read_version_data(root, args.version)
    if version_errors or data is None:
        header = "workflow discuss doctor" if args.discuss_command == "doctor" else "workflow discuss preview"
        print(f"{header}: FAILED")
        for error in version_errors:
            print(f"- {error}")
        return 1

    if args.discuss_command == "preview":
        return print_discussion_preview(root, args.version, data)

    if args.discuss_command == "doctor":
        if not discussion_required(args.version, data):
            print("workflow discuss doctor: OK")
            print(f"- {discussion_gate_message(args.version, data)}")
            return 0
        errors = validate_discussion_artifacts(root, args.version)
        if errors:
            print("workflow discuss doctor: FAILED")
            for error in errors:
                print(f"- {error}")
            return 1
        print("workflow discuss doctor: OK")
        print(f"- {args.version}: discussion gate passed")
        return 0

    print(f"workflow discuss: unsupported command {args.discuss_command}")
    return 2
