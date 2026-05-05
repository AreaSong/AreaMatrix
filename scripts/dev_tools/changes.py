"""V2 workflow change tracking checks and previews."""

from __future__ import annotations

import argparse
import ast
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


DEFAULT_VERSION = "v2"
VERSION_ROOT = Path("workflow/versions")
CHANGE_ROOT = VERSION_ROOT / DEFAULT_VERSION / "changes"
DEFAULT_DRAFT_ROOT = VERSION_ROOT / DEFAULT_VERSION / "drafts"
ALLOWED_STATUS = {"draft", "planned", "ready", "blocked", "archived"}
ALLOWED_RISK = {"Low", "Medium", "High", "Mission-Critical"}
SYNC_DOC_KEYS = ("update", "api", "udl")
SLUG_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$")


class ChangeYAMLError(ValueError):
    pass


@dataclass
class FeatureRecord:
    file: Path
    change_id: str
    feature: dict[str, Any]

    @property
    def feature_id(self) -> str:
        return str(self.feature.get("id", ""))


@dataclass(frozen=True)
class DraftArtifact:
    path: Path
    content: str


@dataclass(frozen=True)
class DraftTask:
    task_id: str
    feature_id: str
    task_key: str
    title: str
    manifest: str
    copy_prompt: str
    verify_prompt: str


def parse_scalar(raw: str, path: Path, line_no: int) -> Any:
    value = raw.strip()
    if value == "[]":
        return []
    if value == "{}":
        return {}
    if value in {"true", "True"}:
        return True
    if value in {"false", "False"}:
        return False
    if value in {"null", "Null", "~"}:
        return None
    if value.startswith(('"', "'")):
        try:
            return ast.literal_eval(value)
        except (SyntaxError, ValueError) as exc:
            raise ChangeYAMLError(f"{path}:{line_no}: invalid quoted scalar") from exc
    if value.startswith(("[", "{", "&", "*", "!", "|", ">")):
        raise ChangeYAMLError(f"{path}:{line_no}: unsupported YAML scalar syntax: {value}")
    return value


def logical_lines(text: str, path: Path) -> list[tuple[int, int, str]]:
    lines: list[tuple[int, int, str]] = []
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        if "\t" in raw_line:
            raise ChangeYAMLError(f"{path}:{line_no}: tabs are not supported")
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        if indent % 2 != 0:
            raise ChangeYAMLError(f"{path}:{line_no}: indentation must use two-space steps")
        lines.append((line_no, indent, raw_line.strip()))
    return lines


def split_mapping(value: str, path: Path, line_no: int) -> tuple[str, str]:
    if ":" not in value:
        raise ChangeYAMLError(f"{path}:{line_no}: expected key: value mapping")
    key, raw_value = value.split(":", 1)
    key = key.strip()
    if not key or any(ch.isspace() for ch in key):
        raise ChangeYAMLError(f"{path}:{line_no}: unsupported key syntax: {key!r}")
    return key, raw_value.strip()


def parse_yaml_subset(text: str, path: Path) -> Any:
    """Parse the small YAML subset used by workflow change files."""

    lines = logical_lines(text, path)
    if not lines:
        return {}
    data, index = parse_block(lines, 0, lines[0][1], path)
    if index != len(lines):
        line_no, indent, _ = lines[index]
        raise ChangeYAMLError(f"{path}:{line_no}: unexpected indentation at {indent}")
    return data


def parse_block(lines: list[tuple[int, int, str]], index: int, indent: int, path: Path) -> tuple[Any, int]:
    if index >= len(lines):
        return {}, index
    _, actual_indent, stripped = lines[index]
    if actual_indent != indent:
        raise ChangeYAMLError(f"{path}:{lines[index][0]}: expected indent {indent}, got {actual_indent}")
    if stripped.startswith("- "):
        return parse_list(lines, index, indent, path)
    return parse_mapping(lines, index, indent, path)


def parse_mapping(lines: list[tuple[int, int, str]], index: int, indent: int, path: Path) -> tuple[dict[str, Any], int]:
    result: dict[str, Any] = {}
    while index < len(lines):
        line_no, current_indent, stripped = lines[index]
        if current_indent < indent:
            break
        if current_indent > indent:
            raise ChangeYAMLError(f"{path}:{line_no}: unexpected nested mapping")
        if stripped.startswith("- "):
            break
        key, raw_value = split_mapping(stripped, path, line_no)
        if key in result:
            raise ChangeYAMLError(f"{path}:{line_no}: duplicate key: {key}")
        index += 1
        if raw_value:
            result[key] = parse_scalar(raw_value, path, line_no)
            if index < len(lines) and lines[index][1] > indent:
                raise ChangeYAMLError(f"{path}:{lines[index][0]}: scalar key cannot have nested children")
            continue
        if index < len(lines) and lines[index][1] > indent:
            result[key], index = parse_block(lines, index, lines[index][1], path)
        else:
            result[key] = {}
    return result, index


def parse_list(lines: list[tuple[int, int, str]], index: int, indent: int, path: Path) -> tuple[list[Any], int]:
    result: list[Any] = []
    while index < len(lines):
        line_no, current_indent, stripped = lines[index]
        if current_indent < indent:
            break
        if current_indent > indent:
            raise ChangeYAMLError(f"{path}:{line_no}: unexpected nested list item")
        if not stripped.startswith("- "):
            break
        item_text = stripped[2:].strip()
        index += 1
        if not item_text:
            if index >= len(lines) or lines[index][1] <= indent:
                result.append({})
            else:
                item, index = parse_block(lines, index, lines[index][1], path)
                result.append(item)
            continue
        if ":" in item_text and not item_text.startswith(('"', "'")):
            key, raw_value = split_mapping(item_text, path, line_no)
            item_map: dict[str, Any] = {}
            if raw_value:
                item_map[key] = parse_scalar(raw_value, path, line_no)
            elif index < len(lines) and lines[index][1] > indent:
                item_map[key], index = parse_block(lines, index, lines[index][1], path)
            else:
                item_map[key] = {}
            if index < len(lines) and lines[index][1] > indent:
                extra, index = parse_mapping(lines, index, lines[index][1], path)
                for extra_key, extra_value in extra.items():
                    if extra_key in item_map:
                        raise ChangeYAMLError(f"{path}:{line_no}: duplicate key in list item: {extra_key}")
                    item_map[extra_key] = extra_value
            result.append(item_map)
            continue
        result.append(parse_scalar(item_text, path, line_no))
        if index < len(lines) and lines[index][1] > indent:
            raise ChangeYAMLError(f"{path}:{lines[index][0]}: scalar list item cannot have nested children")
    return result, index


def change_root(version: str = DEFAULT_VERSION) -> Path:
    return VERSION_ROOT / version / "changes"


def change_files(root: Path, file_arg: str | None, version: str = DEFAULT_VERSION) -> list[Path]:
    if file_arg:
        path = Path(file_arg)
        return [path if path.is_absolute() else root / path]
    directory = root / change_root(version)
    return sorted(directory.glob("*.yaml")) if directory.is_dir() else []


def as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def path_exists(root: Path, value: str) -> bool:
    path = Path(value)
    return path.exists() if path.is_absolute() else (root / path).exists()


def load_change(path: Path) -> dict[str, Any]:
    data = parse_yaml_subset(path.read_text(encoding="utf-8"), path)
    if not isinstance(data, dict):
        raise ChangeYAMLError(f"{path}: top-level YAML must be a mapping")
    return data


def validate_loaded_change(root: Path, path: Path, data: dict[str, Any], version: str = DEFAULT_VERSION) -> tuple[list[str], list[FeatureRecord]]:
    errors: list[str] = []
    features: list[FeatureRecord] = []
    for key in ["id", "title", "version", "status", "features"]:
        if key not in data:
            errors.append(f"{path}: missing top-level field: {key}")
    if data.get("version") != version:
        errors.append(f"{path}: version must be {version}")
    if data.get("status") not in ALLOWED_STATUS:
        errors.append(f"{path}: status must be one of {', '.join(sorted(ALLOWED_STATUS))}")
    raw_features = data.get("features")
    if not isinstance(raw_features, list) or not raw_features:
        errors.append(f"{path}: features must be a non-empty list")
        return errors, features
    change_id = str(data.get("id", ""))
    for index, raw_feature in enumerate(raw_features, start=1):
        if not isinstance(raw_feature, dict):
            errors.append(f"{path}: feature #{index} must be a mapping")
            continue
        validate_feature(root, path, index, raw_feature, errors, version)
        features.append(FeatureRecord(file=path, change_id=change_id, feature=raw_feature))
    return errors, features


def validate_feature(root: Path, path: Path, index: int, feature: dict[str, Any], errors: list[str], version: str = DEFAULT_VERSION) -> None:
    prefix = f"{path}: feature #{index}"
    for key in ["id", "module", "intent", "docs", "risk", "task_split"]:
        if key not in feature:
            errors.append(f"{prefix}: missing field: {key}")
    if not isinstance(feature.get("id"), str) or not str(feature.get("id")).strip():
        errors.append(f"{prefix}: id must be a non-empty string")
    elif not SLUG_RE.fullmatch(str(feature.get("id"))):
        errors.append(f"{prefix}: id must be a lowercase slug")
    elif not str(feature.get("id")).startswith(f"{version}-"):
        errors.append(f"{prefix}: id must start with {version}-")
    if "depends_on" in feature and not isinstance(feature.get("depends_on"), list):
        errors.append(f"{prefix}: depends_on must be a list")
    docs = feature.get("docs")
    if not isinstance(docs, dict):
        errors.append(f"{prefix}: docs must be a mapping")
    else:
        source = docs.get("source")
        if not isinstance(source, list) or not source:
            errors.append(f"{prefix}: docs.source must be a non-empty list")
        else:
            for doc in source:
                if not isinstance(doc, str) or not doc.strip():
                    errors.append(f"{prefix}: docs.source values must be strings")
                elif not path_exists(root, doc):
                    errors.append(f"{prefix}: missing source doc: {doc}")
        for key in SYNC_DOC_KEYS:
            if key in docs and not isinstance(docs.get(key), list):
                errors.append(f"{prefix}: docs.{key} must be a list")
            for target in as_list(docs.get(key)):
                if not isinstance(target, str) or not target.strip():
                    errors.append(f"{prefix}: docs.{key} values must be strings")
                elif not path_exists(root, target):
                    errors.append(f"{prefix}: missing sync target: {target}")
    risk = feature.get("risk")
    if not isinstance(risk, dict):
        errors.append(f"{prefix}: risk must be a mapping")
    else:
        if risk.get("level") not in ALLOWED_RISK:
            errors.append(f"{prefix}: risk.level must be one of {', '.join(sorted(ALLOWED_RISK))}")
        boundaries = risk.get("boundaries")
        if not isinstance(boundaries, list) or not boundaries:
            errors.append(f"{prefix}: risk.boundaries must be a non-empty list")
    task_split = feature.get("task_split")
    if not isinstance(task_split, list) or not task_split:
        errors.append(f"{prefix}: task_split must be a non-empty list")
    else:
        task_ids: set[str] = set()
        for task_index, task in enumerate(task_split, start=1):
            if not isinstance(task, dict):
                errors.append(f"{prefix}: task_split #{task_index} must be a mapping")
                continue
            for task_key in ["id", "title"]:
                if not isinstance(task.get(task_key), str) or not str(task.get(task_key)).strip():
                    errors.append(f"{prefix}: task_split #{task_index} missing {task_key}")
            task_id = str(task.get("id", ""))
            if task_id:
                if not SLUG_RE.fullmatch(task_id):
                    errors.append(f"{prefix}: task_split #{task_index} id must be a lowercase slug")
                if task_id in task_ids:
                    errors.append(f"{prefix}: duplicate task_split id: {task_id}")
                task_ids.add(task_id)
            if "validation" in task and not isinstance(task.get("validation"), list):
                errors.append(f"{prefix}: task_split #{task_index} validation must be a list")


def collect_changes(root: Path, file_arg: str | None = None, version: str = DEFAULT_VERSION) -> tuple[list[str], list[FeatureRecord], list[Path]]:
    errors: list[str] = []
    records: list[FeatureRecord] = []
    files = change_files(root, file_arg, version)
    if not files:
        errors.append(f"no {version} change files found under {change_root(version)}")
        return errors, records, files
    for path in files:
        if not path.is_file():
            errors.append(f"missing change file: {path}")
            continue
        try:
            data = load_change(path)
        except ChangeYAMLError as exc:
            errors.append(str(exc))
            continue
        file_errors, file_records = validate_loaded_change(root, path, data, version)
        errors.extend(file_errors)
        records.extend(file_records)
    errors.extend(validate_feature_graph(records))
    return errors, records, files


def validate_feature_graph(records: Sequence[FeatureRecord]) -> list[str]:
    errors: list[str] = []
    by_id: dict[str, FeatureRecord] = {}
    for record in records:
        feature_id = record.feature_id
        if not feature_id:
            continue
        if feature_id in by_id:
            errors.append(f"duplicate feature id: {feature_id} ({by_id[feature_id].file} and {record.file})")
        by_id[feature_id] = record
    for record in records:
        feature_id = record.feature_id
        for dep in as_list(record.feature.get("depends_on")):
            if not isinstance(dep, str) or not dep.strip():
                errors.append(f"{record.file}: feature {feature_id} has non-string dependency")
            elif dep == feature_id:
                errors.append(f"{record.file}: feature {feature_id} cannot depend on itself")
            elif dep not in by_id:
                errors.append(f"{record.file}: feature {feature_id} depends on unknown feature {dep}")
    errors.extend(validate_no_cycles(records, by_id))
    return errors


def validate_no_cycles(records: Sequence[FeatureRecord], by_id: dict[str, FeatureRecord]) -> list[str]:
    errors: list[str] = []
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(feature_id: str, stack: list[str]) -> None:
        if feature_id in visited:
            return
        if feature_id in visiting:
            errors.append(f"dependency cycle: {' -> '.join([*stack, feature_id])}")
            return
        record = by_id.get(feature_id)
        if not record:
            return
        visiting.add(feature_id)
        for dep in as_list(record.feature.get("depends_on")):
            if isinstance(dep, str):
                visit(dep, [*stack, feature_id])
        visiting.remove(feature_id)
        visited.add(feature_id)

    for record in records:
        if record.feature_id:
            visit(record.feature_id, [])
    return errors


def ordered_features(records: Sequence[FeatureRecord]) -> list[FeatureRecord]:
    by_id = {record.feature_id: record for record in records if record.feature_id}
    result: list[FeatureRecord] = []
    visited: set[str] = set()

    def visit(record: FeatureRecord) -> None:
        feature_id = record.feature_id
        if feature_id in visited:
            return
        for dep in as_list(record.feature.get("depends_on")):
            if isinstance(dep, str) and dep in by_id:
                visit(by_id[dep])
        visited.add(feature_id)
        result.append(record)

    for record in records:
        visit(record)
    return result


def filter_feature_records(records: Sequence[FeatureRecord], feature_id: str | None) -> tuple[list[str], list[FeatureRecord]]:
    if not feature_id:
        return [], list(records)
    selected = [record for record in records if record.feature_id == feature_id]
    if not selected:
        return [f"unknown feature id: {feature_id}"], []
    return [], selected


def bullet_lines(values: Sequence[Any], empty: str = "None") -> list[str]:
    items = [str(value) for value in values if isinstance(value, str) and value.strip()]
    return [f"- `{item}`" for item in items] if items else [f"- {empty}"]


def plain_bullet_lines(values: Sequence[Any], empty: str = "None") -> list[str]:
    items = [str(value) for value in values if isinstance(value, str) and value.strip()]
    return [f"- {item}" for item in items] if items else [f"- {empty}"]


def docs_map(feature: dict[str, Any]) -> dict[str, Any]:
    return feature.get("docs", {}) if isinstance(feature.get("docs"), dict) else {}


def risk_map(feature: dict[str, Any]) -> dict[str, Any]:
    return feature.get("risk", {}) if isinstance(feature.get("risk"), dict) else {}


def sync_targets(docs: dict[str, Any]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for key in SYNC_DOC_KEYS:
        for value in as_list(docs.get(key)):
            if isinstance(value, str) and value not in seen:
                result.append(value)
                seen.add(value)
    return result


def display_path(root: Path, path: Path) -> str:
    try:
        return str(path.resolve().relative_to(root.resolve()))
    except ValueError:
        return str(path)


def task_validation(task: dict[str, Any]) -> list[Any]:
    return as_list(task.get("validation"))


def render_manifest_section(root: Path, record: FeatureRecord, task: dict[str, Any]) -> str:
    feature = record.feature
    docs = docs_map(feature)
    risk = risk_map(feature)
    task_key = str(task.get("id", "unknown"))
    task_id = f"{record.feature_id}/{task_key}"
    lines = [
        f"## {task_id}",
        "",
        f"> source change: `{display_path(root, record.file)}`",
        f"> feature: `{record.feature_id}`",
        f"> module: `{feature.get('module', 'unknown')}`",
        f"> depends: {', '.join(f'`{dep}`' for dep in as_list(feature.get('depends_on'))) or 'None'}",
        "",
        "### Intent",
        f"- {feature.get('intent', '')}",
        "",
        "### Task",
        f"- `{task_key}`: {task.get('title', '')}",
        "",
        "### Exact Docs",
        *bullet_lines(as_list(docs.get("source"))),
        "",
        "### Sync Targets",
        *bullet_lines(sync_targets(docs)),
        "",
        "### Risk Level",
        f"- {risk.get('level', 'Unspecified')}",
        "",
        "### Risk Boundaries",
        *plain_bullet_lines(as_list(risk.get("boundaries"))),
        "",
        "### Validation",
        *plain_bullet_lines(task_validation(task)),
    ]
    return "\n".join(lines).rstrip() + "\n"


def render_copy_prompt(root: Path, record: FeatureRecord, task: dict[str, Any]) -> str:
    feature = record.feature
    docs = docs_map(feature)
    risk = risk_map(feature)
    task_key = str(task.get("id", "unknown"))
    task_id = f"{record.feature_id}/{task_key}"
    lines = [
        f"# V2 Copy-ready Draft: {task_id}",
        "",
        "你现在进入 AreaMatrix v2 草稿任务执行模式。",
        "",
        "## 工作边界",
        f"- Source change: `{display_path(root, record.file)}`",
        f"- Feature: `{record.feature_id}`",
        f"- Module: `{feature.get('module', 'unknown')}`",
        f"- Task: `{task_key}` - {task.get('title', '')}",
        f"- Risk: `{risk.get('level', 'Unspecified')}`",
        "- 是否允许修改文件：`是，但仅限本 v2 草稿任务直接要求的 docs/API/UDL/实现/测试；不得接入 live v1 task-loop queue`",
        "",
        "## Exact Docs",
        *bullet_lines(as_list(docs.get("source"))),
        "",
        "## 必须同步检查",
        *bullet_lines(sync_targets(docs)),
        "",
        "## 风险边界",
        *plain_bullet_lines(as_list(risk.get("boundaries"))),
        "",
        "## 执行要求",
        "- 先读取 Source change、Exact Docs、Sync Targets，再决定实现范围。",
        "- 若涉及 Core API，必须保持 `docs/api/core-api.md` 与 `core/area_matrix.udl` 一致。",
        "- 不得移动、删除、覆盖用户原文件；不得把 v2 草稿直接写入 `tasks/prompts/**`。",
        "- 完成后记录实际改动、验证命令、风险处理和未覆盖项。",
        "",
        "## 建议验证",
        *plain_bullet_lines(task_validation(task)),
    ]
    return "\n".join(lines).rstrip() + "\n"


def render_verify_prompt(root: Path, record: FeatureRecord, task: dict[str, Any]) -> str:
    feature = record.feature
    docs = docs_map(feature)
    risk = risk_map(feature)
    task_key = str(task.get("id", "unknown"))
    task_id = f"{record.feature_id}/{task_key}"
    lines = [
        f"# V2 Verify-ready Draft: {task_id}",
        "",
        "你现在进入 AreaMatrix v2 草稿任务只读验收模式。",
        "这次是验收，不是修复：禁止修改文件，禁止边验边改。",
        "",
        "## 验收对象",
        f"- Source change: `{display_path(root, record.file)}`",
        f"- Feature: `{record.feature_id}`",
        f"- Module: `{feature.get('module', 'unknown')}`",
        f"- Task: `{task_key}` - {task.get('title', '')}",
        f"- Risk: `{risk.get('level', 'Unspecified')}`",
        "",
        "## 必须读取",
        f"- Change YAML: `{display_path(root, record.file)}`",
        f"- Manifest draft section: `## {task_id}`",
        *bullet_lines(as_list(docs.get("source"))),
        "",
        "## 验收清单",
        "- task 实现必须能回到 Source change、Exact Docs 和 Manifest draft 逐项证明。",
        "- docs/API/UDL sync targets 必须无漂移；如未涉及，需要说明为什么无需修改。",
        "- 风险边界必须逐条证明未破坏。",
        "- 不得把草稿误判为已进入 live v1 queue；不得修改 progress。",
        "- 不能只看 diff；必须核对文档、草稿 manifest、实际文件和验证证据。",
        "",
        "## 建议验证",
        *plain_bullet_lines(task_validation(task)),
        "",
        "## 输出要求",
        "- 若通过，最后一行写：`VERIFY_RESULT: PASS`",
        "- 若不通过，最后一行写：`VERIFY_RESULT: FAIL`，并列出阻塞项。",
    ]
    return "\n".join(lines).rstrip() + "\n"


def build_draft_tasks(root: Path, record: FeatureRecord) -> list[DraftTask]:
    drafts: list[DraftTask] = []
    for task in as_list(record.feature.get("task_split")):
        if not isinstance(task, dict):
            continue
        task_key = str(task.get("id", "unknown"))
        task_id = f"{record.feature_id}/{task_key}"
        drafts.append(
            DraftTask(
                task_id=task_id,
                feature_id=record.feature_id,
                task_key=task_key,
                title=str(task.get("title", "")),
                manifest=render_manifest_section(root, record, task),
                copy_prompt=render_copy_prompt(root, record, task),
                verify_prompt=render_verify_prompt(root, record, task),
            )
        )
    return drafts


def manifest_artifact(root: Path, record: FeatureRecord, drafts: Sequence[DraftTask]) -> DraftArtifact:
    content = f"# V2 Manifest Draft: {record.feature_id}\n\n" + "\n".join(draft.manifest for draft in drafts)
    return DraftArtifact(path=root / record.feature_id / "manifest.md", content=content.rstrip() + "\n")


def draft_artifacts(repo_root: Path, output_root: Path, records: Sequence[FeatureRecord]) -> list[DraftArtifact]:
    artifacts: list[DraftArtifact] = []
    for record in ordered_features(records):
        drafts = build_draft_tasks(repo_root, record)
        artifacts.append(manifest_artifact(output_root, record, drafts))
        for draft in drafts:
            feature_dir = output_root / draft.feature_id
            artifacts.append(DraftArtifact(path=feature_dir / f"{draft.task_key}.copy.md", content=draft.copy_prompt))
            artifacts.append(DraftArtifact(path=feature_dir / f"{draft.task_key}.verify.md", content=draft.verify_prompt))
    return artifacts


def print_artifacts(repo_root: Path, artifacts: Sequence[DraftArtifact]) -> None:
    print("V2 generated prompt drafts")
    print("- mode: preview only; no files written")
    print("- queue: not connected to current v1 task-loop")
    for artifact in artifacts:
        print()
        print(f"--- {display_path(repo_root, artifact.path)} ---")
        print(artifact.content.rstrip())


def write_artifacts(artifacts: Sequence[DraftArtifact], *, force: bool, label: str = "draft file") -> list[Path]:
    existing = [artifact.path for artifact in artifacts if artifact.path.exists()]
    if existing and not force:
        existing_text = "\n".join(f"- {path}" for path in existing[:10])
        raise FileExistsError(f"{label} already exists; use --force to overwrite:\n{existing_text}")
    written: list[Path] = []
    for artifact in artifacts:
        artifact.path.parent.mkdir(parents=True, exist_ok=True)
        artifact.path.write_text(artifact.content, encoding="utf-8")
        written.append(artifact.path)
    return written


def run_changes_doctor(root: Path, args: argparse.Namespace) -> int:
    errors, records, files = collect_changes(root, args.file)
    if errors:
        print("v2 change doctor: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("v2 change doctor: OK")
    print(f"- files: {len(files)}")
    print(f"- features: {len(records)}")
    return 0


def run_changes_preview(root: Path, args: argparse.Namespace) -> int:
    errors, records, _ = collect_changes(root, args.file)
    if errors:
        print("v2 change preview: doctor failed")
        for error in errors:
            print(f"- {error}")
        return 1
    print("V2 change preview")
    print("- mode: preview only; no prompt files are generated")
    print("- queue: not connected to current v1 task-loop")
    for index, record in enumerate(ordered_features(records), start=1):
        feature = record.feature
        docs = feature.get("docs", {}) if isinstance(feature.get("docs"), dict) else {}
        risk = feature.get("risk", {}) if isinstance(feature.get("risk"), dict) else {}
        print()
        print(f"{index}. {record.feature_id} [{feature.get('module', 'unknown')}]")
        print(f"   intent: {feature.get('intent', '')}")
        print(f"   file: {record.file.relative_to(root) if record.file.is_absolute() else record.file}")
        print(f"   depends_on: {', '.join(as_list(feature.get('depends_on'))) or 'None'}")
        print(f"   risk: {risk.get('level', 'Unspecified')}")
        print("   exact docs:")
        for doc in as_list(docs.get("source")):
            print(f"     - {doc}")
        sync_targets = [target for key in SYNC_DOC_KEYS for target in as_list(docs.get(key))]
        print("   sync targets:")
        for target in sync_targets or ["None"]:
            print(f"     - {target}")
        print("   draft task split:")
        for task in as_list(feature.get("task_split")):
            if isinstance(task, dict):
                print(f"     - {task.get('id', 'unknown')}: {task.get('title', '')}")
                for validation in as_list(task.get("validation")):
                    print(f"       validation: {validation}")
    return 0


def run_changes_generate(root: Path, args: argparse.Namespace) -> int:
    if args.force and not args.write:
        print("v2 change generate: --force requires --write")
        return 1
    errors, records, _ = collect_changes(root, args.file)
    if errors:
        print("v2 change generate: doctor failed")
        for error in errors:
            print(f"- {error}")
        return 1
    filter_errors, selected = filter_feature_records(records, args.feature)
    if filter_errors:
        print("v2 change generate: selection failed")
        for error in filter_errors:
            print(f"- {error}")
        return 1
    output_root = Path(args.out_dir) if args.out_dir else root / DEFAULT_DRAFT_ROOT
    if not output_root.is_absolute():
        output_root = root / output_root
    artifacts = draft_artifacts(root, output_root, selected)
    if not args.write:
        print_artifacts(root, artifacts)
        return 0
    try:
        written = write_artifacts(artifacts, force=args.force)
    except FileExistsError as exc:
        print(f"v2 change generate: {exc}")
        return 1
    print("v2 change generate: wrote draft files")
    print(f"- root: {output_root}")
    print(f"- files: {len(written)}")
    for path in written:
        print(f"  - {path}")
    return 0
