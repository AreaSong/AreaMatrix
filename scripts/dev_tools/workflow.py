"""Versioned workflow checks, plans, and queue candidates."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from .changes import (
    DraftArtifact,
    as_list,
    collect_changes,
    display_path,
    docs_map,
    filter_feature_records,
    ordered_features,
    parse_yaml_subset,
    risk_map,
    sync_targets,
    task_validation,
    write_artifacts,
)
from .discussion import (
    DISCUSSION_TEMPLATES,
    discussion_gate_label,
    discussion_gate_message,
    validate_discussion_records,
)
from .promotion import (
    PROMOTION_ROOT_NAME,
    build_promotion_tasks,
    last_live_label,
    promotion_artifacts,
    promotion_config_from_record,
    promotion_gate_status,
    select_feature_closure,
    validate_promotion_preview_configs,
)


TEMPLATE_ROOT = Path("workflow/templates")
VERSION_ROOT = Path("workflow/versions")
PLAN_ROOT_NAME = "plans"
QUEUE_ROOT_NAME = "queue"
DEFAULT_VERSION = "v2"
ALLOWED_VERSION_STATUS = {"planning", "live-running", "archived", "blocked"}
ALLOWED_DOC_OPS = {"create", "update", "delete", "reference"}
REQUIRED_TEMPLATES = [
    "version.yaml",
    "change.example.yaml",
    *DISCUSSION_TEMPLATES,
    "plan.md",
    "queue.yaml",
    "queue.md",
    "drafts.md",
    "promotion.yaml",
    "promotion.md",
]


@dataclass(frozen=True)
class VersionRecord:
    version_id: str
    path: Path
    data: dict[str, Any]


def read_yaml_file(path: Path) -> dict[str, Any]:
    data = parse_yaml_subset(path.read_text(encoding="utf-8"), path)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: top-level YAML must be a mapping")
    return data


def load_versions(root: Path) -> tuple[list[str], list[VersionRecord]]:
    errors: list[str] = []
    records: list[VersionRecord] = []
    versions_dir = root / VERSION_ROOT
    if not versions_dir.is_dir():
        return [f"missing versions directory: {VERSION_ROOT}"], records
    for directory in sorted(path for path in versions_dir.iterdir() if path.is_dir()):
        path = directory / "version.yaml"
        if not path.is_file():
            errors.append(f"{display_path(root, path)}: missing version.yaml")
            continue
        try:
            data = read_yaml_file(path)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        version_id = str(data.get("id", ""))
        if version_id != directory.name:
            errors.append(f"{display_path(root, path)}: id must match directory name {directory.name}")
        if data.get("status") not in ALLOWED_VERSION_STATUS:
            errors.append(f"{display_path(root, path)}: status must be one of {', '.join(sorted(ALLOWED_VERSION_STATUS))}")
        if "depends_on" in data and not isinstance(data.get("depends_on"), list):
            errors.append(f"{display_path(root, path)}: depends_on must be a list")
        records.append(VersionRecord(version_id=version_id, path=path, data=data))
    errors.extend(validate_version_graph(root, records))
    return errors, records


def validate_version_graph(root: Path, records: Sequence[VersionRecord]) -> list[str]:
    errors: list[str] = []
    by_id = {record.version_id: record for record in records if record.version_id}
    for record in records:
        for dep in as_list(record.data.get("depends_on")):
            if not isinstance(dep, str) or not dep.strip():
                errors.append(f"{display_path(root, record.path)}: dependency must be a non-empty string")
            elif dep not in by_id:
                errors.append(f"{display_path(root, record.path)}: depends on unknown version {dep}")
    return errors


def validate_templates(root: Path) -> list[str]:
    errors: list[str] = []
    for name in REQUIRED_TEMPLATES:
        path = root / TEMPLATE_ROOT / name
        if not path.is_file():
            errors.append(f"missing workflow template: {display_path(root, path)}")
    return errors


def promotion_config_for(root: Path, version: str) -> tuple[list[str], Any | None, VersionRecord | None, list[VersionRecord]]:
    errors, versions = load_versions(root)
    record = next((item for item in versions if item.version_id == version), None)
    if not record:
        errors.append(f"unknown workflow version: {version}")
        return errors, None, None, versions
    config_errors, config = promotion_config_from_record(root, record)
    errors.extend(config_errors)
    return errors, config, record, versions


def validate_v1_gate(root: Path, versions: Sequence[VersionRecord]) -> list[str]:
    errors: list[str] = []
    by_id = {record.version_id: record for record in versions}
    v1 = by_id.get("v1-mvp")
    v2 = by_id.get("v2")
    if not v1:
        errors.append("missing v1-mvp version record")
    elif v1.data.get("status") != "live-running":
        errors.append("v1-mvp status must stay live-running until the 637-task queue is complete")
    if not v2:
        errors.append("missing v2 version record")
    elif v2.data.get("gate") != "queue-only-until-v1-complete":
        errors.append("v2 gate must be queue-only-until-v1-complete while v1 is live-running")
    progress = root / "tasks/prompts/_shared/progress.json"
    if not progress.is_file():
        errors.append("missing live v1 progress file: tasks/prompts/_shared/progress.json")
    return errors


def lines_for_range(path: Path, start: int, end: int) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    if start < 1 or end < start or end > len(lines):
        return ""
    return "\n".join(lines[start - 1 : end])


def int_field(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def validate_doc_changes(root: Path, records: Sequence[Any]) -> list[str]:
    errors: list[str] = []
    for record in records:
        feature_id = record.feature_id
        for index, change in enumerate(as_list(record.feature.get("doc_changes")), start=1):
            prefix = f"{display_path(root, record.file)}: feature {feature_id} doc_changes #{index}"
            if not isinstance(change, dict):
                errors.append(f"{prefix}: must be a mapping")
                continue
            for key in ["file", "operation", "line_start", "line_end", "heading", "excerpt", "summary", "tasks"]:
                if key not in change:
                    errors.append(f"{prefix}: missing field: {key}")
            if change.get("operation") not in ALLOWED_DOC_OPS:
                errors.append(f"{prefix}: operation must be one of {', '.join(sorted(ALLOWED_DOC_OPS))}")
            file_value = change.get("file")
            doc_path = root / str(file_value) if isinstance(file_value, str) else None
            if not doc_path or not doc_path.is_file():
                errors.append(f"{prefix}: doc file does not exist: {file_value}")
                continue
            start = int_field(change.get("line_start"))
            end = int_field(change.get("line_end"))
            if start is None or end is None:
                errors.append(f"{prefix}: line_start and line_end must be integers")
                continue
            selected = lines_for_range(doc_path, start, end)
            if not selected:
                errors.append(f"{prefix}: line range is outside the file")
                continue
            heading = str(change.get("heading", "")).strip()
            excerpt = str(change.get("excerpt", "")).strip()
            if heading and heading not in selected:
                errors.append(f"{prefix}: heading not found in selected line range")
            if excerpt and excerpt not in selected:
                errors.append(f"{prefix}: excerpt not found in selected line range")
            task_ids = set()
            for task in as_list(record.feature.get("task_split")):
                if isinstance(task, dict) and isinstance(task.get("id"), str):
                    task_ids.add(task["id"])
            for task_id in as_list(change.get("tasks")):
                if task_id not in task_ids:
                    errors.append(f"{prefix}: unknown task reference {task_id}")
    return errors


def validate_code_impacts(root: Path, records: Sequence[Any]) -> list[str]:
    errors: list[str] = []
    for record in records:
        impacts = record.feature.get("code_impacts")
        prefix = f"{display_path(root, record.file)}: feature {record.feature_id}"
        if not isinstance(impacts, dict):
            errors.append(f"{prefix}: missing code_impacts mapping")
            continue
        for key in ["existing", "expected", "tests"]:
            if key not in impacts or not isinstance(impacts.get(key), list):
                errors.append(f"{prefix}: code_impacts.{key} must be a list")
        for value in as_list(impacts.get("existing")):
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{prefix}: code_impacts.existing values must be strings")
            elif "*" in value:
                base = value.split("*", 1)[0].rstrip("/")
                if base and not (root / base).exists():
                    errors.append(f"{prefix}: existing glob base does not exist: {value}")
            elif not (root / value).exists():
                errors.append(f"{prefix}: existing path does not exist: {value}")
    return errors


def collect_workflow(root: Path, version: str, feature: str | None = None) -> tuple[list[str], list[Any]]:
    change_root = VERSION_ROOT / version / "changes"
    errors, records, _ = collect_changes(root, None)
    if version != DEFAULT_VERSION:
        errors.append(f"unsupported workflow version for changes: {version}")
    expected_prefix = root / change_root
    records = [record for record in records if record.file.resolve().is_relative_to(expected_prefix.resolve())]
    filter_errors, selected = filter_feature_records(records, feature)
    errors.extend(filter_errors)
    errors.extend(validate_doc_changes(root, selected))
    errors.extend(validate_code_impacts(root, selected))
    return errors, selected


def collect_workflow_with_dependencies(root: Path, version: str, feature: str | None = None) -> tuple[list[str], list[Any]]:
    change_root = VERSION_ROOT / version / "changes"
    errors, records, _ = collect_changes(root, None)
    if version != DEFAULT_VERSION:
        errors.append(f"unsupported workflow version for changes: {version}")
    expected_prefix = root / change_root
    version_records = [record for record in records if record.file.resolve().is_relative_to(expected_prefix.resolve())]
    selected_errors, selected = select_feature_closure(version_records, feature)
    errors.extend(selected_errors)
    errors.extend(validate_doc_changes(root, selected))
    errors.extend(validate_code_impacts(root, selected))
    return errors, selected


def feature_plan_content(root: Path, version: str, record: Any) -> str:
    feature = record.feature
    docs = docs_map(feature)
    impacts = feature.get("code_impacts") if isinstance(feature.get("code_impacts"), dict) else {}
    risk = risk_map(feature)
    lines = [
        f"# Workflow Plan: {record.feature_id}",
        "",
        f"- Version: `{version}`",
        f"- Source change: `{display_path(root, record.file)}`",
        f"- Module: `{feature.get('module', 'unknown')}`",
        f"- Status: docs-change ledger / queue candidate planning",
        f"- Depends on: {', '.join(f'`{dep}`' for dep in as_list(feature.get('depends_on'))) or 'None'}",
        f"- Risk: `{risk.get('level', 'Unspecified')}`",
        "",
        "## Intent",
        "",
        str(feature.get("intent", "")),
        "",
        "## Docs Change Ledger",
        "",
        "| File | Lines | Heading | Operation | Summary | Tasks |",
        "|---|---:|---|---|---|---|",
    ]
    for change in as_list(feature.get("doc_changes")):
        if not isinstance(change, dict):
            continue
        tasks = ", ".join(f"`{task}`" for task in as_list(change.get("tasks"))) or "None"
        lines.append(
            f"| `{change.get('file', '')}` | {change.get('line_start', '')}-{change.get('line_end', '')} | "
            f"{change.get('heading', '')} | {change.get('operation', '')} | {change.get('summary', '')} | {tasks} |"
        )
    lines.extend(
        [
            "",
            "## Exact Docs",
            *[f"- `{doc}`" for doc in as_list(docs.get("source"))],
            "",
            "## Sync Targets",
            *[f"- `{target}`" for target in sync_targets(docs)],
            "",
            "## Code Impact",
            "",
            "### Existing",
            *[f"- `{item}`" for item in as_list(impacts.get("existing"))],
            "",
            "### Expected",
            *[f"- `{item}`" for item in as_list(impacts.get("expected"))],
            "",
            "### Tests",
            *[f"- `{item}`" for item in as_list(impacts.get("tests"))],
            "",
            "## Risk Boundaries",
            *[f"- {item}" for item in as_list(risk.get("boundaries"))],
            "",
            "## Task Split",
        ]
    )
    for task in as_list(feature.get("task_split")):
        if isinstance(task, dict):
            lines.append(f"- `{record.feature_id}/{task.get('id', 'unknown')}`: {task.get('title', '')}")
    lines.extend(
        [
            "",
            "## Queue Readiness",
            "",
            "- Status: candidate planning only.",
            "- Live queue: blocked while `v1-mvp` is `live-running`.",
            "- Promotion: explicit only; this plan does not write `tasks/prompts/**`.",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"


def plan_artifacts(root: Path, version: str, out_root: Path, records: Sequence[Any]) -> list[DraftArtifact]:
    return [
        DraftArtifact(path=out_root / f"{record.feature_id}.plan.md", content=feature_plan_content(root, version, record))
        for record in ordered_features(records)
    ]


def queue_yaml_content(root: Path, version: str, record: Any) -> str:
    lines = [
        f"version: {version}",
        f"feature: {record.feature_id}",
        "status: candidate",
        "promotion_gate: explicit-only",
        "live_queue_blocked: true",
        "tasks:",
    ]
    for task in as_list(record.feature.get("task_split")):
        if not isinstance(task, dict):
            continue
        task_key = task.get("id", "unknown")
        lines.extend(
            [
                f"  - id: {record.feature_id}/{task_key}",
            ]
        )
        deps = as_list(record.feature.get("depends_on"))
        if deps:
            lines.append("    depends_on:")
            for dep in deps:
                lines.append(f"      - {dep}")
        else:
            lines.append("    depends_on: []")
        lines.extend(
            [
                f"    draft_copy: workflow/versions/{version}/drafts/{record.feature_id}/{task_key}.copy.md",
                f"    draft_verify: workflow/versions/{version}/drafts/{record.feature_id}/{task_key}.verify.md",
                "    validation:",
            ]
        )
        validations = task_validation(task)
        if validations:
            for validation in validations:
                lines.append(f"      - {validation}")
        else:
            lines.append("      - ./dev workflow doctor")
    return "\n".join(lines).rstrip() + "\n"


def queue_md_content(root: Path, version: str, record: Any) -> str:
    feature = record.feature
    lines = [
        f"# Queue Candidate: {record.feature_id}",
        "",
        f"- Version: `{version}`",
        "- Status: candidate",
        "- Promotion: explicit only",
        "- Live queue blocked: true while `v1-mvp` is `live-running`",
        f"- Source change: `{display_path(root, record.file)}`",
        "",
        "## Candidate Tasks",
    ]
    for task in as_list(feature.get("task_split")):
        if isinstance(task, dict):
            lines.append(f"- `{record.feature_id}/{task.get('id', 'unknown')}`: {task.get('title', '')}")
    lines.extend(
        [
            "",
            "## Promotion Notes",
            "",
            "- Do not write `tasks/prompts/**` in this phase.",
            "- Promotion must be a later explicit command after gates pass.",
            "- Queue candidates can be reviewed while v1 is still running.",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"


def queue_artifacts(root: Path, version: str, out_root: Path, records: Sequence[Any]) -> list[DraftArtifact]:
    artifacts: list[DraftArtifact] = []
    for record in ordered_features(records):
        feature_dir = out_root / record.feature_id
        artifacts.append(DraftArtifact(path=feature_dir / "queue.yaml", content=queue_yaml_content(root, version, record)))
        artifacts.append(DraftArtifact(path=feature_dir / "queue.md", content=queue_md_content(root, version, record)))
    return artifacts


def print_named_artifacts(root: Path, header: str, artifacts: Sequence[DraftArtifact]) -> None:
    print(header)
    print("- mode: preview only; no files written")
    print("- live queue: not modified")
    for artifact in artifacts:
        print()
        print(f"--- {display_path(root, artifact.path)} ---")
        print(artifact.content.rstrip())


def output_root(root: Path, version: str, out_dir: str | None, default_name: str) -> Path:
    path = Path(out_dir) if out_dir else root / VERSION_ROOT / version / default_name
    return path if path.is_absolute() else root / path


def run_workflow_doctor(root: Path, args: argparse.Namespace) -> int:
    errors: list[str] = []
    errors.extend(validate_templates(root))
    version_errors, versions = load_versions(root)
    errors.extend(version_errors)
    errors.extend(validate_promotion_preview_configs(root, versions))
    errors.extend(validate_v1_gate(root, versions))
    errors.extend(validate_discussion_records(root, versions))
    change_errors, _ = collect_workflow(root, DEFAULT_VERSION)
    errors.extend(change_errors)
    if errors:
        print("workflow doctor: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("workflow doctor: OK")
    print(f"- templates: {len(REQUIRED_TEMPLATES)}")
    print(f"- versions: {len(versions)}")
    for record in versions:
        print(f"- discussion {record.version_id}: {discussion_gate_label(record.version_id, record.data)}")
    print("- promotion preview: configured")
    print("- v1 gate: queue-only for v2 while v1 is live-running")
    return 0


def run_workflow_status(root: Path, args: argparse.Namespace) -> int:
    errors, versions = load_versions(root)
    if errors:
        print("workflow status: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("Workflow status")
    for record in versions:
        print()
        print(f"- {record.version_id}: {record.data.get('status', 'unknown')}")
        print(f"  depends_on: {', '.join(as_list(record.data.get('depends_on'))) or 'None'}")
        print(f"  live_queue: {record.data.get('live_queue') or 'None'}")
        print(f"  gate: {record.data.get('gate') or 'None'}")
        print(f"  promotion: {record.data.get('promotion') or 'None'}")
        print(f"  discussion: {discussion_gate_message(record.version_id, record.data)}")
    print()
    print("Current gate: v2 may reach queue candidates, but must not promote to tasks/prompts/** while v1-mvp is live-running.")
    return 0


def run_workflow_plan(root: Path, args: argparse.Namespace) -> int:
    if args.force and not args.write:
        print("workflow plan: --force requires --write")
        return 1
    errors, records = collect_workflow(root, args.version, args.feature)
    if errors:
        print("workflow plan: doctor failed")
        for error in errors:
            print(f"- {error}")
        return 1
    artifacts = plan_artifacts(root, args.version, output_root(root, args.version, args.out_dir, PLAN_ROOT_NAME), records)
    if not args.write:
        print_named_artifacts(root, "Workflow plans", artifacts)
        return 0
    try:
        written = write_artifacts(artifacts, force=args.force, label="workflow plan file")
    except FileExistsError as exc:
        print(f"workflow plan: {exc}")
        return 1
    print("workflow plan: wrote files")
    print(f"- files: {len(written)}")
    for path in written:
        print(f"  - {path}")
    return 0


def run_workflow_queue(root: Path, args: argparse.Namespace) -> int:
    if args.force and not args.write:
        print("workflow queue: --force requires --write")
        return 1
    errors, records = collect_workflow(root, args.version, args.feature)
    if errors:
        print("workflow queue: doctor failed")
        for error in errors:
            print(f"- {error}")
        return 1
    artifacts = queue_artifacts(root, args.version, output_root(root, args.version, args.out_dir, QUEUE_ROOT_NAME), records)
    if not args.write:
        print_named_artifacts(root, "Workflow queue candidates", artifacts)
        return 0
    try:
        written = write_artifacts(artifacts, force=args.force, label="workflow queue file")
    except FileExistsError as exc:
        print(f"workflow queue: {exc}")
        return 1
    print("workflow queue: wrote files")
    print(f"- files: {len(written)}")
    for path in written:
        print(f"  - {path}")
    return 0


def run_workflow_promote(root: Path, args: argparse.Namespace) -> int:
    if args.force and not args.write:
        print("workflow promote: --force requires --write")
        return 1
    config_errors, config, version_record, versions = promotion_config_for(root, args.version)
    errors = list(config_errors)
    errors.extend(validate_v1_gate(root, versions))
    workflow_errors, records = collect_workflow_with_dependencies(root, args.version, args.feature)
    errors.extend(workflow_errors)
    if errors or not config:
        print("workflow promote: doctor failed")
        for error in errors:
            print(f"- {error}")
        return 1
    root_dependency = last_live_label()
    blocked, gate_message = promotion_gate_status(version_record, versions)
    tasks = build_promotion_tasks(root, args.version, config, records, root_dependency)
    artifacts = promotion_artifacts(
        root,
        args.version,
        output_root(root, args.version, args.out_dir, PROMOTION_ROOT_NAME),
        config,
        tasks,
        blocked,
        gate_message,
        root_dependency,
    )
    if not args.write:
        print_named_artifacts(root, "Workflow promotion preview", artifacts)
        return 0
    try:
        written = write_artifacts(artifacts, force=args.force, label="workflow promotion preview file")
    except FileExistsError as exc:
        print(f"workflow promote: {exc}")
        return 1
    print("workflow promote: wrote preview files")
    print(f"- files: {len(written)}")
    print(f"- gate: {gate_message}")
    for path in written:
        print(f"  - {path}")
    return 0
