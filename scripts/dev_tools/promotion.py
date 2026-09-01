"""Promotion preview helpers for versioned workflow candidates."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from .changes import (
    DraftArtifact,
    FeatureRecord,
    SLUG_RE,
    as_list,
    display_path,
    docs_map,
    ordered_features,
    risk_map,
    sync_targets,
    task_validation,
)
from .execution_paths import copy_ready_root, manifest_root, shared_root, task_root, verify_ready_root
from .execution_repository import label_sort_key, scan_task_files
from .workflow_states import ARTIFACT_STATUSES, status_list


PROMOTION_ROOT_NAME = "promotion"
APPROVAL_FILE_NAME = "approval.yaml"
TEMPLATE_REFERENCE_VERSION = "v-template"
EXECUTION_SHARED_BOOTSTRAP_FILES = (
    "audit-rules.md",
    "task-slicing-rules.md",
    "engineering-quality-rules.md",
    "dependency-graph.md",
    "prompt_pipeline.py",
)
EXECUTION_SHARED_BOOTSTRAP_DIRS = ("prompt_pipeline_lib",)
EXECUTION_SHARED_RUNTIME_DIRS = ("copy-ready", "verify-ready", "manifests")


@dataclass(frozen=True)
class PromotionConfig:
    target_queue: str
    phase: str
    batch: str
    batch_slug: str
    start_task: int

    @property
    def batch_dir(self) -> str:
        return f"{self.batch}-{self.batch_slug}"


@dataclass(frozen=True)
class PromotionTask:
    semantic_id: str
    feature_id: str
    task_key: str
    title: str
    live_label: str
    depends_on: tuple[str, ...]
    task_path: Path
    copy_ready_path: Path
    verify_ready_path: Path
    manifest_path: Path
    task_content: str
    manifest_section: str
    verify_content: str = ""


def int_field(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def allowed_target_queues(version: str | None) -> set[str]:
    if version:
        return {f"workflow/versions/{version}/execution"}
    return {"workflow/versions/<version>/execution"}


def validate_promotion_preview_configs(root: Path, records: Sequence[Any]) -> list[str]:
    errors: list[str] = []
    for record in records:
        if record.data.get("promotion") == "already-live":
            continue
        config = record.data.get("promotion_preview")
        prefix = f"{display_path(root, record.path)}: promotion_preview"
        if not isinstance(config, dict):
            errors.append(f"{prefix} must be a mapping")
            continue
        errors.extend(validate_promotion_preview_config(prefix, config, record.version_id))
    return errors


def validate_promotion_preview_config(prefix: str, config: dict[str, Any], version: str | None = None) -> list[str]:
    errors: list[str] = []
    for key in ["target_queue"]:
        if key not in config:
            errors.append(f"{prefix}: missing field: {key}")
    if config.get("target_queue") not in allowed_target_queues(version):
        expected = " or ".join(sorted(allowed_target_queues(version)))
        errors.append(f"{prefix}: target_queue must be {expected}")
    if config.get("live_mapping") == "pending":
        return errors
    for key in ["phase", "batch", "batch_slug", "start_task"]:
        if key not in config:
            errors.append(f"{prefix}: missing field: {key}")
    phase = config.get("phase")
    if not isinstance(phase, str) or not phase.startswith("phase-") or not phase.split("-", 1)[1].isdigit():
        errors.append(f"{prefix}: phase must look like phase-5")
    batch = config.get("batch")
    if not isinstance(batch, str) or len(batch.split("-")) != 2 or not all(part.isdigit() for part in batch.split("-")):
        errors.append(f"{prefix}: batch must look like 5-1")
    batch_slug = config.get("batch_slug")
    if not isinstance(batch_slug, str) or not SLUG_RE.fullmatch(batch_slug):
        errors.append(f"{prefix}: batch_slug must be a lowercase slug")
    start_task = int_field(config.get("start_task"))
    if start_task is None or start_task < 1:
        errors.append(f"{prefix}: start_task must be an integer >= 1")
    return errors


def promotion_config_from_record(root: Path, record: Any) -> tuple[list[str], PromotionConfig | None]:
    config = record.data.get("promotion_preview")
    prefix = f"{display_path(root, record.path)}: promotion_preview"
    if not isinstance(config, dict):
        return [f"{prefix} must be a mapping"], None
    if config.get("live_mapping") == "pending":
        return [f"{prefix}: live_mapping is pending; configure live phase/batch before promotion preview"], None
    errors = validate_promotion_preview_config(prefix, config, record.version_id)
    if errors:
        return errors, None
    return (
        [],
        PromotionConfig(
            target_queue=str(config["target_queue"]),
            phase=str(config["phase"]),
            batch=str(config["batch"]),
            batch_slug=str(config["batch_slug"]),
            start_task=int_field(config.get("start_task")) or 1,
        ),
    )


def select_feature_closure(records: Sequence[FeatureRecord], feature: str | None) -> tuple[list[str], list[FeatureRecord]]:
    if not feature:
        return [], ordered_features(records)
    by_id = {record.feature_id: record for record in records if record.feature_id}
    if feature not in by_id:
        return [f"unknown feature id: {feature}"], []
    result: list[FeatureRecord] = []
    seen: set[str] = set()

    def visit(feature_id: str) -> None:
        if feature_id in seen:
            return
        record = by_id.get(feature_id)
        if not record:
            return
        for dep in as_list(record.feature.get("depends_on")):
            if isinstance(dep, str):
                visit(dep)
        seen.add(feature_id)
        result.append(record)

    visit(feature)
    return [], result


def last_live_label() -> str:
    tasks = scan_task_files()
    labels = sorted(tasks, key=label_sort_key)
    return labels[-1] if labels else "None"


def promotion_gate_status(version_record: Any | None, versions: Sequence[Any]) -> tuple[bool, str]:
    by_id = {record.version_id: record for record in versions}
    v1 = by_id.get("v1-mvp")
    if version_record and version_record.data.get("gate") in {
        "queue-only-until-v1-complete",
        "queue-only-until-explicit-approval-and-live-mapping",
    }:
        if v1 and v1.data.get("lifecycle_status") == "live-running":
            return True, "promotion blocked: v1-mvp is live-running"
        if v1 and v1.data.get("lifecycle_status") == "archived":
            return False, "promotion gate: v1-mvp archived; explicit approval and live mapping still required"
    return False, "promotion gate: open"


def build_promotion_tasks(
    root: Path,
    version: str,
    config: PromotionConfig,
    records: Sequence[FeatureRecord],
    root_dependency: str,
) -> list[PromotionTask]:
    tasks: list[PromotionTask] = []
    last_label_by_feature: dict[str, str] = {}
    task_number = config.start_task
    manifest_path = manifest_root(root, version) / f"{config.phase}.md"
    for record in ordered_features(records):
        feature_last_label = ""
        previous_label_in_feature = ""
        feature_deps = [dep for dep in as_list(record.feature.get("depends_on")) if isinstance(dep, str)]
        for raw_task in as_list(record.feature.get("task_split")):
            if not isinstance(raw_task, dict):
                continue
            task_key = str(raw_task.get("id", "unknown"))
            live_label = f"{config.batch}/task-{task_number:02d}"
            semantic_id = f"{record.feature_id}/{task_key}"
            deps = promotion_task_dependencies(
                feature_deps,
                last_label_by_feature,
                previous_label_in_feature,
                root_dependency,
            )
            task_path = task_root(root, version) / config.phase / config.batch_dir / task_filename(task_number, task_key)
            export_name = prompt_export_filename(live_label)
            tasks.append(
                PromotionTask(
                    semantic_id=semantic_id,
                    feature_id=record.feature_id,
                    task_key=task_key,
                    title=str(raw_task.get("title", "")),
                    live_label=live_label,
                    depends_on=tuple(deps),
                    task_path=task_path,
                    copy_ready_path=copy_ready_root(root, version) / config.phase / export_name,
                    verify_ready_path=verify_ready_root(root, version) / config.phase / export_name,
                    manifest_path=manifest_path,
                    task_content=render_promoted_task_file(root, version, record, raw_task, live_label, semantic_id),
                    manifest_section=render_promoted_manifest_section(root, record, raw_task, live_label, deps),
                    verify_content=render_promoted_verify_file(root, version, record, raw_task, live_label, semantic_id),
                )
            )
            previous_label_in_feature = live_label
            feature_last_label = live_label
            task_number += 1
        if feature_last_label:
            last_label_by_feature[record.feature_id] = feature_last_label
    return tasks


def promotion_task_dependencies(
    feature_deps: Sequence[str],
    last_label_by_feature: dict[str, str],
    previous_label_in_feature: str,
    root_dependency: str,
) -> list[str]:
    if previous_label_in_feature:
        return [previous_label_in_feature]
    mapped_feature_deps = [last_label_by_feature[dep] for dep in feature_deps if dep in last_label_by_feature]
    if mapped_feature_deps:
        return mapped_feature_deps
    return [] if root_dependency == "None" else [root_dependency]


def prompt_export_filename(label: str) -> str:
    return label.replace("/task-", "-task-") + ".md"


def task_filename(task_number: int, task_key: str) -> str:
    return f"task-{task_number:02d}-{task_key}.md"


def render_promoted_task_file(
    root: Path,
    version: str,
    record: FeatureRecord,
    task: dict[str, Any],
    live_label: str,
    semantic_id: str,
) -> str:
    docs = docs_map(record.feature)
    risk = risk_map(record.feature)
    risk_level = str(risk.get("level", "Unspecified"))
    validations = [f"- {item}" for item in task_validation(task)] or ["- ./dev workflow doctor"]
    lines = [
        f"# {live_label} {semantic_id}",
        "",
        "## 来源",
        "",
        f"- Workflow version: `{version}`",
        f"- Semantic task: `{semantic_id}`",
        f"- Source change: `{display_path(root, record.file)}`",
        f"- Module: `{record.feature.get('module', 'unknown')}`",
        "",
        "## 目标",
        "",
        f"{record.feature.get('intent', '')}",
        "",
        "## 核对清单",
        "",
        f"- 完成 `{task.get('title', '')}`。",
        "- 逐项读取 Exact Docs，并保持 Sync Targets 无漂移。",
        "- 若涉及 Core API，必须同步 `docs/api/core-api.md` 与 `core/area_matrix.udl`。",
        "- 不得移动、删除、覆盖用户原文件；不得突破风险边界。",
        "",
        "## Exact Docs",
        *[f"- `{doc}`" for doc in as_list(docs.get("source"))],
        "",
        "## Sync Targets",
        *[f"- `{target}`" for target in sync_targets(docs)],
        "",
        "## 风险边界",
        "### Risk Level",
        f"- {risk_level}",
        *[f"- {item}" for item in as_list(risk.get("boundaries"))],
        "",
        "## 完成标准",
        "",
        "- 实现、文档、API / UDL、测试证据能回到 workflow change 和 manifest 逐项证明。",
        "- 验证命令按任务风险和影响面完成；无法运行的验证必须说明原因。",
        "",
        "## 验证",
        *validations,
    ]
    return "\n".join(lines).rstrip() + "\n"


def render_promoted_verify_file(
    root: Path,
    version: str,
    record: FeatureRecord,
    task: dict[str, Any],
    live_label: str,
    semantic_id: str,
) -> str:
    """Render a read-only acceptance prompt separate from implementation."""

    docs = docs_map(record.feature)
    risk = risk_map(record.feature)
    risk_level = str(risk.get("level", "Unspecified"))
    validations = [f"- {item}" for item in task_validation(task)] or ["- ./dev workflow doctor"]
    lines = [
        f"# Verify-ready Prompt: {live_label} {semantic_id}",
        "",
        f"你现在进入 AreaMatrix {version} 的单任务验收模式。",
        "这次是验收，不是修复：禁止修改文件，禁止边验边改。",
        "",
        "## 验收对象",
        f"- Semantic task: `{semantic_id}`",
        f"- Source change: `{display_path(root, record.file)}`",
        f"- Task: `{task.get('title', '')}`",
        "### Risk Level",
        f"- {risk_level}",
        "",
        "## 必须读取",
        *[f"- `{doc}`" for doc in as_list(docs.get("source"))],
        "",
        "## 只读验收要求",
        "- 只读取并核对 copy-ready 实现结果、Exact Docs、manifest 和验证证据。",
        "- 不得实现、修复、重写或删除任何文件；发现问题只输出 FAIL 和阻塞项。",
        "- 不得执行 copy-ready prompt 中的实现步骤。",
        "- 风险边界必须逐条证明未被突破。",
        "",
        "## 验证",
        *validations,
        "",
        "## 输出要求",
        "- 通过时最后一行必须单独输出 VERIFY_RESULT: PASS。",
        "- 不通过时最后一行必须单独输出 VERIFY_RESULT: FAIL，并列出阻塞项。",
    ]
    return "\n".join(lines).rstrip() + "\n"


def render_promoted_manifest_section(
    root: Path,
    record: FeatureRecord,
    task: dict[str, Any],
    live_label: str,
    depends_on: Sequence[str],
) -> str:
    feature = record.feature
    docs = docs_map(feature)
    impacts = feature.get("code_impacts") if isinstance(feature.get("code_impacts"), dict) else {}
    risk = risk_map(feature)
    semantic_id = f"{record.feature_id}/{task.get('id', 'unknown')}"
    validations = [f"- {item}" for item in task_validation(task)] or ["- ./dev workflow doctor"]
    lines = [
        f"## {live_label}",
        "",
        f"> source task: `workflow:{semantic_id}`",
        f"> source change: `{display_path(root, record.file)}`",
        f"> depends: {', '.join(f'`{dep}`' for dep in depends_on) or 'None'}",
        "",
        "### Exact Docs",
        *[f"- `{doc}`" for doc in as_list(docs.get("source"))],
        "",
        "### Existing Code",
        *[f"- `{item}`" for item in as_list(impacts.get("existing"))],
        "",
        "### Expected New Paths",
        *[f"- `{item}`" for item in as_list(impacts.get("expected"))],
        "",
        "### Forbidden Touches",
        "- None",
        "",
        "### Risk Level",
        f"- {risk.get('level', 'Unspecified')}",
        "",
        "### Validation",
        *validations,
    ]
    return "\n".join(lines).rstrip() + "\n"


def promotion_artifacts(
    root: Path,
    version: str,
    out_root: Path,
    config: PromotionConfig,
    tasks: Sequence[PromotionTask],
    blocked: bool,
    gate_message: str,
    root_dependency: str,
) -> list[DraftArtifact]:
    return [
        DraftArtifact(path=out_root / "promotion.yaml", content=promotion_yaml_content(root, version, config, tasks, blocked, gate_message, root_dependency)),
        DraftArtifact(path=out_root / "promotion.md", content=promotion_md_content(root, version, config, tasks, blocked, gate_message, root_dependency)),
    ]


def approval_artifact(root: Path, version: str, blocked: bool, gate_message: str, tasks: Sequence[PromotionTask]) -> DraftArtifact:
    status = "blocked" if blocked else "ready"
    template_reference = version == TEMPLATE_REFERENCE_VERSION
    lines = [
        f"version: {version}",
        f"status: {status}",
        "kind: promotion-approval",
        "approved: " + ("false" if blocked else "true"),
        f"gate_message: {gate_message}",
        "mode: approval-only",
        "target_kind: approval-only",
        "writes_live_queue: false",
        f"template_reference: {'true' if template_reference else 'false'}",
        f"apply_allowed: {'false' if blocked or template_reference else 'true'}",
        "tasks:",
    ]
    for task in tasks:
        lines.extend(
            [
                f"  - semantic_id: {task.semantic_id}",
                f"    live_label: {task.live_label}",
                f"    task_file: {display_path(root, task.task_path)}",
                f"    copy_ready: {display_path(root, task.copy_ready_path)}",
                f"    verify_ready: {display_path(root, task.verify_ready_path)}",
            ]
        )
    return DraftArtifact(root / "workflow/versions" / version / PROMOTION_ROOT_NAME / APPROVAL_FILE_NAME, "\n".join(lines).rstrip() + "\n")


def load_approval(path: Path) -> tuple[list[str], dict[str, Any] | None]:
    from .changes import parse_yaml_subset

    try:
        data = parse_yaml_subset(path.read_text(encoding="utf-8"), path)
    except ValueError as exc:
        return [str(exc)], None
    if not isinstance(data, dict):
        return [f"{path}: top-level YAML must be a mapping"], None
    return [], data


def validate_approval(root: Path, version: str) -> list[str]:
    path = root / "workflow/versions" / version / PROMOTION_ROOT_NAME / APPROVAL_FILE_NAME
    if not path.is_file():
        return [f"missing promotion approval: {display_path(root, path)}"]
    errors, data = load_approval(path)
    if errors or data is None:
        return errors
    if data.get("version") != version:
        errors.append(f"{display_path(root, path)}: version must be {version}")
    if data.get("status") not in ARTIFACT_STATUSES:
        errors.append(f"{display_path(root, path)}: status must be one of {status_list(ARTIFACT_STATUSES)}")
    if data.get("kind") != "promotion-approval":
        errors.append(f"{display_path(root, path)}: kind must be promotion-approval")
    if data.get("approved") is not True:
        errors.append(f"{display_path(root, path)}: approved must be true before apply")
    if data.get("writes_live_queue") is not False:
        errors.append(f"{display_path(root, path)}: approval must not write live queue")
    return errors


def validate_apply(root: Path, version: str, tasks: Sequence[PromotionTask]) -> list[str]:
    errors: list[str] = []
    existing_labels = set(scan_task_files(root, version))
    seen_labels: set[str] = set()
    for task in tasks:
        if task.live_label in existing_labels:
            errors.append(f"live label already exists: {task.live_label}")
        if task.live_label in seen_labels:
            errors.append(f"duplicate promotion live label: {task.live_label}")
        seen_labels.add(task.live_label)
        for path in [task.task_path, task.copy_ready_path, task.verify_ready_path]:
            if path.exists():
                errors.append(f"promotion target already exists: {display_path(root, path)}")
        if not task.manifest_section.strip():
            errors.append(f"{task.semantic_id}: manifest section is empty")
        if not task.task_content.strip():
            errors.append(f"{task.semantic_id}: task content is empty")
        if not task.verify_content.strip():
            errors.append(f"{task.semantic_id}: verify-ready content is empty")
        elif task.verify_content == task.task_content:
            errors.append(f"{task.semantic_id}: copy-ready and verify-ready content must be distinct")
        elif "禁止修改文件" not in task.verify_content or "VERIFY_RESULT:" not in task.verify_content:
            errors.append(f"{task.semantic_id}: verify-ready prompt must declare read-only acceptance")
    return errors


def execution_bootstrap_artifacts(root: Path, version: str) -> list[DraftArtifact]:
    source = shared_root(root, "v1-mvp")
    target = shared_root(root, version)
    readme = target / "README.md"
    artifacts: list[DraftArtifact] = []
    if not readme.exists():
        artifacts.append(DraftArtifact(readme, execution_shared_readme(version)))
    for name in EXECUTION_SHARED_BOOTSTRAP_FILES:
        source_path = source / name
        target_path = target / name
        if source_path.is_file() and not target_path.exists():
            artifacts.append(DraftArtifact(target_path, source_path.read_text(encoding="utf-8")))
    for name in EXECUTION_SHARED_BOOTSTRAP_DIRS:
        artifacts.extend(copy_tree_artifacts(source / name, target / name))
    for name in EXECUTION_SHARED_RUNTIME_DIRS:
        target_path = target / name / "README.md"
        if not target_path.exists():
            artifacts.append(DraftArtifact(target_path, execution_runtime_readme(name, version)))
    progress = target / "progress.json"
    if not progress.exists():
        artifacts.append(DraftArtifact(progress, empty_progress_content(version)))
    return artifacts


def copy_tree_artifacts(source: Path, target: Path) -> list[DraftArtifact]:
    artifacts: list[DraftArtifact] = []
    if not source.is_dir():
        return artifacts
    for path in sorted(item for item in source.rglob("*") if item.is_file()):
        if path.name == ".DS_Store":
            continue
        target_path = target / path.relative_to(source)
        if not target_path.exists():
            artifacts.append(DraftArtifact(target_path, path.read_text(encoding="utf-8")))
    return artifacts


def execution_runtime_readme(name: str, version: str) -> str:
    title = name.replace("-", " ").title()
    lines = [
        f"# {title}",
        "",
        f"This directory is initialized for `{version}` execution runtime artifacts.",
        "Promotion apply writes version-local task artifacts here; historical v1 task",
        "content and progress are not copied into this version.",
    ]
    return "\n".join(lines) + "\n"


def execution_shared_readme(version: str) -> str:
    pipeline = f"workflow/versions/{version}/execution/_shared/prompt_pipeline.py"
    lines = [
        "# Prompt Shared Runtime",
        "",
        f"This directory contains shared prompt runtime material for `{version}`.",
        "It is initialized from the current runtime template during promotion apply,",
        "without copying historical v1 manifests, exported prompts, or progress.",
        "",
        "## Common Commands",
        "",
        "```bash",
        f"python3 {pipeline} doctor",
        f"python3 {pipeline} plan --all",
        f"python3 {pipeline} next",
        f"python3 {pipeline} status",
        "```",
    ]
    return "\n".join(lines) + "\n"


def empty_progress_content(version: str) -> str:
    data = {"version": 1, "execution_version": version, "tasks": {}}
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def promotion_apply_artifacts(root: Path, version: str, tasks: Sequence[PromotionTask]) -> list[DraftArtifact]:
    artifacts: list[DraftArtifact] = execution_bootstrap_artifacts(root, version)
    manifest_sections: dict[Path, list[str]] = {}
    for task in tasks:
        artifacts.append(DraftArtifact(task.task_path, task.task_content))
        artifacts.append(DraftArtifact(task.copy_ready_path, task.task_content))
        if not task.verify_content.strip():
            raise ValueError(f"{task.semantic_id}: verify-ready content is required")
        artifacts.append(DraftArtifact(task.verify_ready_path, task.verify_content))
        manifest_sections.setdefault(task.manifest_path, []).append(task.manifest_section)
    for path, sections in manifest_sections.items():
        header = f"# {path.stem}\n\n" if not path.exists() else path.read_text(encoding="utf-8").rstrip() + "\n\n"
        artifacts.append(DraftArtifact(path, header + "\n\n".join(section.rstrip() for section in sections) + "\n"))
    return artifacts


def promotion_apply_paths(root: Path, version: str, tasks: Sequence[PromotionTask]) -> list[Path]:
    paths: list[Path] = []
    seen: set[Path] = set()
    for artifact in execution_bootstrap_artifacts(root, version):
        append_unique_path(paths, seen, artifact.path)
    for task in tasks:
        for path in [task.task_path, task.copy_ready_path, task.verify_ready_path, task.manifest_path]:
            append_unique_path(paths, seen, path)
    return paths


def append_unique_path(paths: list[Path], seen: set[Path], path: Path) -> None:
    if path in seen:
        return
    paths.append(path)
    seen.add(path)


def promotion_yaml_content(
    root: Path,
    version: str,
    config: PromotionConfig,
    tasks: Sequence[PromotionTask],
    blocked: bool,
    gate_message: str,
    root_dependency: str,
) -> str:
    status = "blocked" if blocked else "ready"
    template_reference = version == TEMPLATE_REFERENCE_VERSION
    lines = [
        f"version: {version}",
        f"status: {status}",
        "kind: promotion-preview",
        "mode: preview",
        "target_kind: preview-only",
        "writes_live_queue: false",
        f"template_reference: {'true' if template_reference else 'false'}",
        f"apply_allowed: {'false' if blocked or template_reference else 'true'}",
        f"target_queue: {config.target_queue}",
        f"phase: {config.phase}",
        f"batch: {config.batch}",
        f"batch_slug: {config.batch_slug}",
        f"start_task: {config.start_task}",
        f"root_dependency: {root_dependency}",
        f"blocked: {'true' if blocked else 'false'}",
        f"gate_message: {gate_message}",
        "tasks:",
    ]
    for task in tasks:
        lines.extend(
            [
                f"  - semantic_id: {task.semantic_id}",
                f"    live_label: {task.live_label}",
                f"    feature: {task.feature_id}",
                f"    task_key: {task.task_key}",
                f"    title: {task.title}",
                f"    task_file: {display_path(root, task.task_path)}",
                f"    manifest: {display_path(root, task.manifest_path)}",
                f"    copy_ready: {display_path(root, task.copy_ready_path)}",
                f"    verify_ready: {display_path(root, task.verify_ready_path)}",
            ]
        )
        if task.depends_on:
            lines.append("    depends_on:")
            for dep in task.depends_on:
                lines.append(f"      - {dep}")
        else:
            lines.append("    depends_on: []")
    return "\n".join(lines).rstrip() + "\n"


def promotion_apply_preview_artifact(root: Path, version: str, tasks: Sequence[PromotionTask], blocked: bool, gate_message: str, errors: Sequence[str]) -> DraftArtifact:
    status = "blocked" if blocked or errors else "ready"
    template_reference = version == TEMPLATE_REFERENCE_VERSION
    lines = [
        f"version: {version}",
        f"status: {status}",
        "kind: promotion-apply-preview",
        "target_kind: apply-preview",
        "writes_live_queue: false",
        f"template_reference: {'true' if template_reference else 'false'}",
        f"apply_allowed: {'false' if blocked or errors or template_reference else 'true'}",
        f"gate_message: {gate_message}",
        "files_to_write:",
    ]
    for path in promotion_apply_paths(root, version, tasks):
        lines.append(f"  - {display_path(root, path)}")
    lines.append("blocked_by:")
    if blocked or errors:
        for error in ([gate_message] if blocked else []):
            lines.append(f"  - {error}")
        for error in errors:
            lines.append(f"  - {error}")
    else:
        lines.append("  - None")
    return DraftArtifact(root / "workflow/versions" / version / PROMOTION_ROOT_NAME / "apply.yaml", "\n".join(lines).rstrip() + "\n")


def promotion_md_content(
    root: Path,
    version: str,
    config: PromotionConfig,
    tasks: Sequence[PromotionTask],
    blocked: bool,
    gate_message: str,
    root_dependency: str,
) -> str:
    lines = [
        f"# Promotion Preview: {version}",
        "",
        "- Mode: preview only",
        "- Live queue: not modified",
        "- Progress file: not modified",
        "- Future live paths below are previews only; no files have been written.",
        f"- Target kind: `preview-only`",
        f"- Writes live queue: `false`",
        f"- Template reference: `{'true' if version == TEMPLATE_REFERENCE_VERSION else 'false'}`",
        f"- Apply allowed: `{'false' if blocked or version == TEMPLATE_REFERENCE_VERSION else 'true'}`",
        f"- Gate: {gate_message}",
        f"- Target queue: `{config.target_queue}`",
        f"- Future phase: `{config.phase}`",
        f"- Future batch: `{config.batch}` (`{config.batch_slug}`)",
        f"- Root dependency: `{root_dependency}`",
        f"- Blocked: `{'yes' if blocked else 'no'}`",
        "",
        "## Label Mapping",
        "",
        "| Semantic task | Future live label | Depends | Task file |",
        "|---|---|---|---|",
    ]
    for task in tasks:
        deps = ", ".join(f"`{dep}`" for dep in task.depends_on) or "None"
        lines.append(f"| `{task.semantic_id}` | `{task.live_label}` | {deps} | `{display_path(root, task.task_path)}` |")
    lines.extend(["", "## Future Manifest Sections"])
    for task in tasks:
        lines.extend(["", f"### {task.live_label} <- {task.semantic_id}", "", "```markdown", task.manifest_section.rstrip(), "```"])
    lines.extend(["", "## Future Task File Drafts"])
    for task in tasks:
        lines.extend(["", f"### {display_path(root, task.task_path)}", "", "```markdown", task.task_content.rstrip(), "```"])
    lines.extend(["", "## Export Paths", "", "| Live label | Copy-ready | Verify-ready |", "|---|---|---|"])
    for task in tasks:
        lines.append(
            f"| `{task.live_label}` | `{display_path(root, task.copy_ready_path)}` | `{display_path(root, task.verify_ready_path)}` |"
        )
    lines.extend(
        [
            "",
            "## Safety",
            "",
            "- This preview does not write version execution files.",
            "- This preview does not write version execution progress.",
            "- A future apply step must run separately after v1 is complete and gates pass.",
        ]
    )
    return "\n".join(lines).rstrip() + "\n"
