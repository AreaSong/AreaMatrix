"""Versioned workflow checks, plans, and queue candidates."""

from __future__ import annotations

import argparse
import subprocess
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
from .middle_layer import (
    MiddleLayerRecord,
    collect_middle_layer_workflow,
)
from .promotion import (
    PROMOTION_ROOT_NAME,
    approval_artifact,
    build_promotion_tasks,
    last_live_label,
    promotion_artifacts,
    promotion_apply_preview_artifact,
    promotion_apply_artifacts,
    promotion_config_from_record,
    promotion_gate_status,
    select_feature_closure,
    validate_approval,
    validate_apply,
    validate_promotion_preview_configs,
)
from .workflow_baseline import (
    validate_baseline,
    validate_required_baselines,
)
from .workflow_projection import (
    validate_closeout,
    validate_projection,
)
from .workflow_states import ARTIFACT_STATUSES, VERSION_LIFECYCLE_STATUSES, status_list


TEMPLATE_ROOT = Path("workflow/templates")
VERSION_ROOT = Path("workflow/versions")
PLAN_ROOT_NAME = "plans"
QUEUE_ROOT_NAME = "queue"
TEMPLATE_REFERENCE_VERSION = "v-template"
DEFAULT_VERSION = TEMPLATE_REFERENCE_VERSION
ALLOWED_QUEUE_STATUS = ARTIFACT_STATUSES
ALLOWED_VERSION_STATUS = VERSION_LIFECYCLE_STATUSES
ALLOWED_DOC_OPS = {"create", "update", "delete", "reference"}
REQUIRED_TEMPLATES = [
    "version.yaml",
    "change.example.yaml",
    "baseline.yaml",
    *DISCUSSION_TEMPLATES,
    "plan.md",
    "queue.yaml",
    "queue.md",
    "drafts.md",
    "middle-layer.example.yaml",
    "promotion.yaml",
    "promotion.md",
    "approval.yaml",
    "apply.yaml",
    "projection.yaml",
    "closeout.yaml",
]
ALLOWED_LOCAL_QUEUE_KEYS = {"phase", "batch", "batch_slug", "start_task"}
REQUIRED_ARCHITECTURE_DOCS = {
    "architecture.md": [
        "`docs/` 是产品源事实",
        "`promotion preview` 只做 dry-run",
        "`explicit promote` 是进入 live 队列的唯一动作",
        "`task-loop` 只执行已批准的 live queue",
    ],
    "pipeline.md": [
        "docs baseline snapshot",
        "promotion approval",
        "explicit promote",
        "result projection",
        "closeout/audit",
    ],
}


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
        lifecycle_status = data.get("lifecycle_status")
        if lifecycle_status not in ALLOWED_VERSION_STATUS:
            errors.append(f"{display_path(root, path)}: lifecycle_status must be one of {status_list(ALLOWED_VERSION_STATUS)}")
        if "status" in data:
            errors.append(f"{display_path(root, path)}: use lifecycle_status for version state; status is reserved for pipeline artifacts")
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


def validate_local_queue(root: Path, records: Sequence[VersionRecord]) -> list[str]:
    errors: list[str] = []
    for record in records:
        if record.data.get("promotion") == "already-live":
            continue
        if record.version_id == TEMPLATE_REFERENCE_VERSION:
            continue
        prefix = f"{display_path(root, record.path)}: local_queue"
        local_queue = record.data.get("local_queue")
        if not isinstance(local_queue, dict):
            errors.append(f"{prefix} must be a mapping")
            continue
        for key in ["phase", "batch", "batch_slug", "start_task"]:
            if key not in local_queue:
                errors.append(f"{prefix}: missing field: {key}")
        for key in local_queue:
            if key not in ALLOWED_LOCAL_QUEUE_KEYS:
                errors.append(f"{prefix}: unsupported field: {key}")
        phase = local_queue.get("phase")
        if not isinstance(phase, str) or not phase.startswith("phase-") or not phase.split("-", 1)[1].isdigit():
            errors.append(f"{prefix}: phase must look like phase-0")
        batch = local_queue.get("batch")
        if not isinstance(batch, str) or len(batch.split("-")) != 2 or not all(part.isdigit() for part in batch.split("-")):
            errors.append(f"{prefix}: batch must look like 0-1")
        batch_slug = local_queue.get("batch_slug")
        if not isinstance(batch_slug, str) or not batch_slug.strip():
            errors.append(f"{prefix}: batch_slug must be a non-empty string")
        start_task = int_field(local_queue.get("start_task"))
        if start_task is None or start_task < 1:
            errors.append(f"{prefix}: start_task must be an integer >= 1")
    return errors


def promotion_mapping_label(record: VersionRecord) -> str:
    if record.data.get("promotion") == "already-live":
        return "already-live"
    config = record.data.get("promotion_preview")
    if not isinstance(config, dict):
        return "missing"
    if config.get("live_mapping") == "pending":
        return "pending"
    phase = config.get("phase")
    batch = config.get("batch")
    if phase and batch:
        return f"configured ({phase}/{batch})"
    return "incomplete"


def local_queue_label(record: VersionRecord) -> str:
    if record.data.get("promotion") == "already-live":
        return "already-live"
    if record.version_id == TEMPLATE_REFERENCE_VERSION:
        return "template-reference"
    config = record.data.get("local_queue")
    if not isinstance(config, dict):
        return "None"
    phase = config.get("phase", "unknown")
    batch = config.get("batch", "unknown")
    start_task = config.get("start_task", "unknown")
    return f"{phase}/{batch}/task-{int_field(start_task) or 1:02d}"


def validate_templates(root: Path) -> list[str]:
    errors: list[str] = []
    for name in REQUIRED_TEMPLATES:
        path = root / TEMPLATE_ROOT / name
        if not path.is_file():
            errors.append(f"missing workflow template: {display_path(root, path)}")
    return errors


def validate_architecture_docs(root: Path) -> list[str]:
    errors: list[str] = []
    readme = root / "workflow/README.md"
    if not readme.is_file():
        errors.append("missing workflow README: workflow/README.md")
        readme_text = ""
    else:
        readme_text = readme.read_text(encoding="utf-8", errors="replace")
    for name, snippets in REQUIRED_ARCHITECTURE_DOCS.items():
        path = root / "workflow" / name
        if not path.is_file():
            errors.append(f"missing workflow architecture doc: workflow/{name}")
            continue
        if f"[`{name}`]({name})" not in readme_text:
            errors.append(f"workflow/README.md: missing link to {name}")
        text = path.read_text(encoding="utf-8", errors="replace")
        for snippet in snippets:
            if snippet not in text:
                errors.append(f"workflow/{name}: missing required boundary text: {snippet}")
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
    if not v1:
        errors.append("missing v1-mvp version record")
    elif v1.data.get("lifecycle_status") != "live-running":
        errors.append("v1-mvp lifecycle_status must stay live-running until the 637-task queue is complete")
    for record in versions:
        if record.version_id == "v1-mvp" or record.data.get("promotion") == "already-live":
            continue
        if record.version_id == TEMPLATE_REFERENCE_VERSION:
            continue
        if "v1-mvp" in as_list(record.data.get("depends_on")) and record.data.get("gate") != "queue-only-until-v1-complete":
            errors.append(f"{record.version_id} gate must be queue-only-until-v1-complete while v1 is live-running")
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


def middle_layer_required(record: VersionRecord | None) -> bool:
    if not record:
        return False
    if record.version_id == "v1-mvp":
        return False
    return record.data.get("middle_layers") == "required"


def version_record_for(root: Path, version: str) -> tuple[list[str], VersionRecord | None]:
    errors, versions = load_versions(root)
    record = next((item for item in versions if item.version_id == version), None)
    if not record:
        errors.append(f"unknown workflow version: {version}")
    return errors, record


def collect_workflow(root: Path, version: str, feature: str | None = None) -> tuple[list[str], list[Any], list[MiddleLayerRecord]]:
    change_root = VERSION_ROOT / version / "changes"
    errors, version_record = version_record_for(root, version)
    change_errors, records, _ = collect_changes(root, None, version)
    errors.extend(change_errors)
    expected_prefix = root / change_root
    records = [record for record in records if record.file.resolve().is_relative_to(expected_prefix.resolve())]
    filter_errors, selected = filter_feature_records(records, feature)
    errors.extend(filter_errors)
    errors.extend(validate_doc_changes(root, selected))
    errors.extend(validate_code_impacts(root, selected))
    middle_records: list[MiddleLayerRecord] = []
    if middle_layer_required(version_record):
        middle_errors, middle_records, _ = collect_middle_layer_workflow(root, version, feature)
        errors.extend(middle_errors)
    return errors, selected, middle_records


def collect_workflow_with_dependencies(root: Path, version: str, feature: str | None = None) -> tuple[list[str], list[Any], list[MiddleLayerRecord]]:
    change_root = VERSION_ROOT / version / "changes"
    errors, version_record = version_record_for(root, version)
    change_errors, records, _ = collect_changes(root, None, version)
    errors.extend(change_errors)
    expected_prefix = root / change_root
    version_records = [record for record in records if record.file.resolve().is_relative_to(expected_prefix.resolve())]
    selected_errors, selected = select_feature_closure(version_records, feature)
    errors.extend(selected_errors)
    errors.extend(validate_doc_changes(root, selected))
    errors.extend(validate_code_impacts(root, selected))
    middle_records: list[MiddleLayerRecord] = []
    if middle_layer_required(version_record):
        middle_errors, middle_records, _ = collect_middle_layer_workflow(root, version, None)
        errors.extend(middle_errors)
        if feature:
            wanted = {record.feature_id for record in selected}
            middle_records = [record for record in middle_records if record.feature_id in wanted]
    return errors, selected, middle_records


def collect_workflow_for_gate(root: Path, version: str, feature: str | None = None) -> tuple[list[str], list[Any], list[MiddleLayerRecord]]:
    errors, records, middle_records = collect_workflow(root, version, feature)
    baseline_errors, _ = validate_baseline(root, version, require_file=True)
    errors.extend(baseline_errors)
    return errors, records, middle_records


def middle_record_for(feature_id: str, records: Sequence[MiddleLayerRecord]) -> MiddleLayerRecord | None:
    return next((record for record in records if record.feature_id == feature_id), None)


def middle_plan_lines(root: Path, record: MiddleLayerRecord | None) -> list[str]:
    if not record:
        return ["- Middle-layer: not required or not present for this version."]
    deps = record.data.get("dependencies") if isinstance(record.data.get("dependencies"), dict) else {}
    lines = [
        f"- Middle-layer ledger: `{display_path(root, record.file)}`",
        f"- Feature dependencies: {', '.join(f'`{dep}`' for dep in as_list(deps.get('features'))) or 'None'}",
        "",
        "### Insertions",
    ]
    for item in as_list(record.data.get("insertions")):
        if isinstance(item, dict):
            lines.append(f"- `{item.get('target', '')}`: {item.get('reason', '')}")
    lines.extend(["", "### Linked Features"])
    for item in as_list(record.data.get("links")):
        if isinstance(item, dict):
            lines.append(f"- `{item.get('feature', '')}` ({item.get('relationship', '')}): {item.get('reason', '')}")
    lines.extend(["", "### Slice Plan"])
    for item in as_list(record.data.get("slice_plan")):
        if isinstance(item, dict):
            lines.append(f"- `{item.get('id', '')}`: {item.get('purpose', '')}")
    return lines


def feature_plan_content(root: Path, version: str, record: Any, middle_record: MiddleLayerRecord | None = None) -> str:
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
        "- Status: `ready`",
        "- Kind: `workflow-plan`",
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
            "## Middle-layer Ledger",
            "",
            *middle_plan_lines(root, middle_record),
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
            "- Status: `ready`.",
            "- Kind: queue-candidate review only.",
            "- Live queue: blocked while `v1-mvp` is `live-running`.",
            "- Promotion: explicit only; this plan does not write `tasks/prompts/**`.",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"


def plan_artifacts(root: Path, version: str, out_root: Path, records: Sequence[Any], middle_records: Sequence[MiddleLayerRecord] = ()) -> list[DraftArtifact]:
    return [
        DraftArtifact(path=out_root / f"{record.feature_id}.plan.md", content=feature_plan_content(root, version, record, middle_record_for(record.feature_id, middle_records)))
        for record in ordered_features(records)
    ]


def queue_yaml_content(root: Path, version: str, record: Any) -> str:
    lines = [
        f"version: {version}",
        f"feature: {record.feature_id}",
        "status: ready",
        "kind: queue-candidate",
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
        "- Status: `ready`",
        "- Kind: queue-candidate",
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


def expected_draft_paths(root: Path, version: str, records: Sequence[Any]) -> list[Path]:
    paths: list[Path] = []
    draft_root = root / VERSION_ROOT / version / "drafts"
    for record in ordered_features(records):
        paths.append(draft_root / record.feature_id / "manifest.md")
        for task in as_list(record.feature.get("task_split")):
            if not isinstance(task, dict):
                continue
            task_key = str(task.get("id", "unknown"))
            paths.append(draft_root / record.feature_id / f"{task_key}.copy.md")
            paths.append(draft_root / record.feature_id / f"{task_key}.verify.md")
    return paths


def validate_plan_gate(root: Path, version: str, feature: str | None = None) -> tuple[list[str], int]:
    errors, records, middle_records = collect_workflow_for_gate(root, version, feature)
    middle_by_id = {record.feature_id for record in middle_records}
    for record in records:
        prefix = f"{display_path(root, record.file)}: feature {record.feature_id}"
        if middle_records and record.feature_id not in middle_by_id:
            errors.append(f"{prefix}: missing middle-layer trace")
        if not as_list(record.feature.get("task_split")):
            errors.append(f"{prefix}: task_split must be non-empty")
        risk = risk_map(record.feature)
        if not as_list(risk.get("boundaries")):
            errors.append(f"{prefix}: risk.boundaries must be non-empty")
        for task in as_list(record.feature.get("task_split")):
            if isinstance(task, dict) and not task_validation(task):
                errors.append(f"{prefix}: task_split {task.get('id', 'unknown')} validation must be non-empty")
    return errors, len(records)


def validate_drafts_gate(root: Path, version: str, feature: str | None = None) -> tuple[list[str], int]:
    errors, records, _ = collect_workflow_for_gate(root, version, feature)
    checked = 0
    for path in expected_draft_paths(root, version, records):
        checked += 1
        if not path.is_file():
            errors.append(f"missing workflow draft artifact: {display_path(root, path)}")
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if path.name == "manifest.md":
            for section in ["### Exact Docs", "### Validation", "### Risk Boundaries"]:
                if section not in text:
                    errors.append(f"{display_path(root, path)}: missing section {section}")
        elif path.name.endswith(".copy.md"):
            for snippet in ["## Exact Docs", "## 建议验证", f"不得把 {version} 草稿直接写入 `tasks/prompts/**`"]:
                if snippet not in text:
                    errors.append(f"{display_path(root, path)}: missing copy boundary: {snippet}")
        elif path.name.endswith(".verify.md"):
            for snippet in ["只读验收", "VERIFY_RESULT: PASS", "VERIFY_RESULT: FAIL"]:
                if snippet not in text:
                    errors.append(f"{display_path(root, path)}: missing verify boundary: {snippet}")
    return errors, checked


def validate_queue_gate(root: Path, version: str, feature: str | None = None) -> tuple[list[str], int]:
    errors, records, _ = collect_workflow_for_gate(root, version, feature)
    draft_errors, _ = validate_drafts_gate(root, version, feature)
    errors.extend(draft_errors)
    count = 0
    queue_root = root / VERSION_ROOT / version / "queue"
    feature_ids = {record.feature_id for record in records}
    for record in ordered_features(records):
        count += 1
        queue_yaml = queue_root / record.feature_id / "queue.yaml"
        queue_md = queue_root / record.feature_id / "queue.md"
        if not queue_yaml.is_file():
            errors.append(f"missing workflow queue artifact: {display_path(root, queue_yaml)}")
            continue
        if not queue_md.is_file():
            errors.append(f"missing workflow queue review: {display_path(root, queue_md)}")
        try:
            data = read_yaml_file(queue_yaml)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        if data.get("version") != version:
            errors.append(f"{display_path(root, queue_yaml)}: version must be {version}")
        if data.get("feature") != record.feature_id:
            errors.append(f"{display_path(root, queue_yaml)}: feature must be {record.feature_id}")
        if data.get("status") not in ALLOWED_QUEUE_STATUS:
            errors.append(f"{display_path(root, queue_yaml)}: status must be one of {status_list(ALLOWED_QUEUE_STATUS)}")
        if data.get("status") != "ready":
            errors.append(f"{display_path(root, queue_yaml)}: queue candidate status must be ready")
        if data.get("kind") != "queue-candidate":
            errors.append(f"{display_path(root, queue_yaml)}: kind must be queue-candidate")
        if data.get("promotion_gate") != "explicit-only":
            errors.append(f"{display_path(root, queue_yaml)}: promotion_gate must be explicit-only")
        for task in as_list(data.get("tasks")):
            if not isinstance(task, dict):
                errors.append(f"{display_path(root, queue_yaml)}: task entries must be mappings")
                continue
            task_id = str(task.get("id", ""))
            if not task_id.startswith(f"{record.feature_id}/"):
                errors.append(f"{display_path(root, queue_yaml)}: task id must start with {record.feature_id}/")
            for key in ["draft_copy", "draft_verify", "validation"]:
                if key not in task:
                    errors.append(f"{display_path(root, queue_yaml)}: task {task_id} missing {key}")
            for dep in as_list(task.get("depends_on")):
                if isinstance(dep, str) and dep.startswith(version) and dep.split("/", 1)[0] not in feature_ids:
                    errors.append(f"{display_path(root, queue_yaml)}: task {task_id} depends on unknown version-local feature {dep}")
    return errors, count


def git_worktree_dirty(root: Path) -> list[str]:
    proc = subprocess.run(["git", "status", "--short"], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if proc.returncode != 0:
        return [f"git status failed: {(proc.stderr or proc.stdout).strip()}"]
    return [line for line in proc.stdout.splitlines() if line.strip()]


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
    errors.extend(validate_architecture_docs(root))
    errors.extend(validate_templates(root))
    version_errors, versions = load_versions(root)
    errors.extend(version_errors)
    errors.extend(validate_local_queue(root, versions))
    errors.extend(validate_promotion_preview_configs(root, versions))
    errors.extend(validate_v1_gate(root, versions))
    errors.extend(validate_discussion_records(root, versions))
    errors.extend(validate_required_baselines(root, versions))
    middle_summary: dict[str, int] = {}
    for record in versions:
        if middle_layer_required(record):
            change_errors, _, middle_records = collect_workflow(root, record.version_id)
            errors.extend(change_errors)
            middle_summary[record.version_id] = len(middle_records)
    for record in versions:
        if middle_layer_required(record) and record.version_id not in middle_summary:
            middle_errors, middle_records, _ = collect_middle_layer_workflow(root, record.version_id, None)
            errors.extend(middle_errors)
            middle_summary[record.version_id] = len(middle_records)
    if errors:
        print("workflow doctor: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("workflow doctor: OK")
    print("- architecture docs: checked")
    print(f"- templates: {len(REQUIRED_TEMPLATES)}")
    print(f"- versions: {len(versions)}")
    for version, count in sorted(middle_summary.items()):
        print(f"- middle-layer {version}: {count}")
    for record in versions:
        print(f"- discussion {record.version_id}: {discussion_gate_label(record.version_id, record.data)}")
        if record.data.get("promotion") != "already-live":
            print(f"- local queue {record.version_id}: {local_queue_label(record)}")
            print(f"- live mapping {record.version_id}: {promotion_mapping_label(record)}")
            print(f"- middle-layer {record.version_id}: {'required' if middle_layer_required(record) else 'skipped'}")
    print("- promotion preview: configured")
    print("- v1 gate: dependent versions stay queue-only while v1 is live-running")
    return 0


def template_reference_note(version: str, status: str | None = None) -> str:
    suffix = ""
    if status:
        suffix = f" status {status}"
    return f"{version}:{suffix} blocked as expected for template reference; no live task-loop verify/checkpoint evidence is required or claimed."


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
        print(f"- {record.version_id}: {record.data.get('lifecycle_status', 'unknown')}")
        print(f"  depends_on: {', '.join(as_list(record.data.get('depends_on'))) or 'None'}")
        print(f"  live_queue: {record.data.get('live_queue') or 'None'}")
        print(f"  gate: {record.data.get('gate') or 'None'}")
        print(f"  promotion: {record.data.get('promotion') or 'None'}")
        print(f"  local_queue: {local_queue_label(record)}")
        print(f"  live_mapping: {promotion_mapping_label(record)}")
        print(f"  discussion: {discussion_gate_message(record.version_id, record.data)}")
        if record.version_id == TEMPLATE_REFERENCE_VERSION:
            print("  projection: blocked as expected for template reference")
            print("  closeout: blocked as expected for template reference")
    print()
    print("Current gate: dependent versions may reach queue candidates, but must not promote to tasks/prompts/** while v1-mvp is live-running.")
    return 0


@dataclass(frozen=True)
class TemplateCheck:
    label: str
    runner: Any
    args: argparse.Namespace


def run_template_check_step(root: Path, check: TemplateCheck) -> int:
    print(f"[check-template] {check.label}")
    result = check.runner(root, check.args)
    print(f"[check-template] {check.label}: {'OK' if result == 0 else 'FAILED'}")
    return result


def run_workflow_check_template(root: Path, args: argparse.Namespace) -> int:
    from .changes import run_changes_doctor
    from .middle_layer import run_workflow_middle
    from .workflow_baseline import run_workflow_baseline
    from .workflow_projection import run_workflow_closeout, run_workflow_project

    version = TEMPLATE_REFERENCE_VERSION
    checks = [
        TemplateCheck("workflow doctor", run_workflow_doctor, argparse.Namespace()),
        TemplateCheck("changes doctor", run_changes_doctor, argparse.Namespace(version=version, file=None)),
        TemplateCheck("middle doctor", run_workflow_middle, argparse.Namespace(version=version, feature=None, middle_command="doctor")),
        TemplateCheck("baseline doctor", run_workflow_baseline, argparse.Namespace(version=version, baseline_command="doctor")),
        TemplateCheck("plan doctor", run_workflow_plan, argparse.Namespace(version=version, feature=None, plan_command="doctor")),
        TemplateCheck("drafts doctor", run_workflow_drafts, argparse.Namespace(version=version, feature=None, drafts_command="doctor")),
        TemplateCheck("queue doctor", run_workflow_queue, argparse.Namespace(version=version, feature=None, queue_command="doctor")),
        TemplateCheck("project doctor", run_workflow_project, argparse.Namespace(version=version, project_command="doctor")),
        TemplateCheck("closeout doctor", run_workflow_closeout, argparse.Namespace(version=version, closeout_command="doctor")),
        TemplateCheck(
            "promotion apply preview",
            run_workflow_promote,
            argparse.Namespace(
                version=version,
                feature=None,
                preview=False,
                write=False,
                out_dir=None,
                force=False,
                promote_command="apply",
            ),
        ),
    ]
    failures = 0
    print("Workflow template reference check")
    print(f"- version: {version}")
    print("- live queue: not modified")
    print("- progress file: not modified")
    for check in checks:
        if run_template_check_step(root, check) != 0:
            failures += 1
    if failures:
        print("workflow check-template: FAILED")
        print(f"- failed checks: {failures}")
        return 1
    print("workflow check-template: OK")
    print(f"- checks: {len(checks)}")
    return 0


def run_workflow_plan(root: Path, args: argparse.Namespace) -> int:
    if getattr(args, "plan_command", None) == "doctor":
        errors, count = validate_plan_gate(root, args.version, args.feature)
        if errors:
            print("workflow plan doctor: FAILED")
            for error in errors:
                print(f"- {error}")
            return 1
        print("workflow plan doctor: OK")
        print(f"- version: {args.version}")
        print(f"- features: {count}")
        return 0
    if args.force and not args.write:
        print("workflow plan: --force requires --write")
        return 1
    errors, records, middle_records = collect_workflow(root, args.version, args.feature)
    if errors:
        print("workflow plan: doctor failed")
        for error in errors:
            print(f"- {error}")
        return 1
    artifacts = plan_artifacts(root, args.version, output_root(root, args.version, args.out_dir, PLAN_ROOT_NAME), records, middle_records)
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
    if getattr(args, "queue_command", None) == "doctor":
        errors, count = validate_queue_gate(root, args.version, args.feature)
        if errors:
            print("workflow queue doctor: FAILED")
            for error in errors:
                print(f"- {error}")
            return 1
        print("workflow queue doctor: OK")
        print(f"- version: {args.version}")
        print(f"- features: {count}")
        return 0
    if args.force and not args.write:
        print("workflow queue: --force requires --write")
        return 1
    errors, records, _ = collect_workflow(root, args.version, args.feature)
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


def run_workflow_drafts(root: Path, args: argparse.Namespace) -> int:
    if args.drafts_command == "doctor":
        errors, count = validate_drafts_gate(root, args.version, args.feature)
        if errors:
            print("workflow drafts doctor: FAILED")
            for error in errors:
                print(f"- {error}")
            return 1
        print("workflow drafts doctor: OK")
        print(f"- version: {args.version}")
        print(f"- artifacts: {count}")
        return 0
    print(f"workflow drafts: unsupported command {args.drafts_command}")
    return 2


def run_workflow_promote(root: Path, args: argparse.Namespace) -> int:
    mode = getattr(args, "promote_command", None) or ("preview" if getattr(args, "preview", False) or not getattr(args, "write", False) else "preview")
    if args.force and not args.write:
        print("workflow promote: --force requires --write")
        return 1
    config_errors, config, version_record, versions = promotion_config_for(root, args.version)
    errors = list(config_errors)
    errors.extend(validate_v1_gate(root, versions))
    workflow_errors, records, _ = collect_workflow_with_dependencies(root, args.version, args.feature)
    errors.extend(workflow_errors)
    if errors or not config:
        print("workflow promote: doctor failed")
        for error in errors:
            print(f"- {error}")
        return 1
    root_dependency = last_live_label()
    blocked, gate_message = promotion_gate_status(version_record, versions)
    if args.version == TEMPLATE_REFERENCE_VERSION:
        blocked = True
        gate_message = "promotion blocked: v-template is a template reference and cannot apply to live tasks/prompts/**"
    tasks = build_promotion_tasks(root, args.version, config, records, root_dependency)
    if mode == "approve":
        artifact = approval_artifact(root, args.version, blocked, gate_message, tasks)
        if not args.write:
            print_named_artifacts(root, "Workflow promotion approval", [artifact])
            return 0
        try:
            written = write_artifacts([artifact], force=args.force, label="workflow promotion approval file")
        except FileExistsError as exc:
            print(f"workflow promote approve: {exc}")
            return 1
        print("workflow promote approve: wrote approval file")
        for path in written:
            print(f"  - {path}")
        return 0
    if mode == "apply":
        approval_errors = validate_approval(root, args.version)
        apply_errors = validate_apply(root, tasks)
        dirty = git_worktree_dirty(root)
        if dirty and args.write:
            apply_errors.append("git worktree must be clean before promotion apply --write")
        gate_errors = [gate_message] if blocked else []
        if approval_errors or gate_errors or apply_errors:
            if not args.write:
                preview = promotion_apply_preview_artifact(root, args.version, tasks, blocked, gate_message, [*approval_errors, *apply_errors])
                print_named_artifacts(root, "Workflow promotion apply preview", [preview])
                return 0
            print("workflow promote apply: blocked")
            for error in [*approval_errors, *gate_errors, *apply_errors]:
                print(f"- {error}")
            return 1
        artifacts = promotion_apply_artifacts(tasks)
        if not args.write:
            preview = promotion_apply_preview_artifact(root, args.version, tasks, blocked, gate_message, [*approval_errors, *apply_errors])
            print_named_artifacts(root, "Workflow promotion apply preview", [preview, *artifacts])
            return 0
        try:
            written = write_artifacts(artifacts, force=False, label="live promotion file")
        except FileExistsError as exc:
            print(f"workflow promote apply: {exc}")
            return 1
        print("workflow promote apply: wrote live files")
        for path in written:
            print(f"  - {path}")
        return 0
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
