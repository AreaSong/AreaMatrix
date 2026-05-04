"""V2 workflow change tracking checks and previews."""

from __future__ import annotations

import argparse
import ast
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence


CHANGE_ROOT = Path("workflow/versions/v2/changes")
ALLOWED_STATUS = {"draft", "planned", "ready", "blocked", "archived"}
ALLOWED_RISK = {"Low", "Medium", "High", "Mission-Critical"}
SYNC_DOC_KEYS = ("update", "api", "udl")


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


def change_files(root: Path, file_arg: str | None) -> list[Path]:
    if file_arg:
        path = Path(file_arg)
        return [path if path.is_absolute() else root / path]
    directory = root / CHANGE_ROOT
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


def validate_loaded_change(root: Path, path: Path, data: dict[str, Any]) -> tuple[list[str], list[FeatureRecord]]:
    errors: list[str] = []
    features: list[FeatureRecord] = []
    for key in ["id", "title", "version", "status", "features"]:
        if key not in data:
            errors.append(f"{path}: missing top-level field: {key}")
    if data.get("version") != "v2":
        errors.append(f"{path}: version must be v2")
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
        validate_feature(root, path, index, raw_feature, errors)
        features.append(FeatureRecord(file=path, change_id=change_id, feature=raw_feature))
    return errors, features


def validate_feature(root: Path, path: Path, index: int, feature: dict[str, Any], errors: list[str]) -> None:
    prefix = f"{path}: feature #{index}"
    for key in ["id", "module", "intent", "docs", "risk", "task_split"]:
        if key not in feature:
            errors.append(f"{prefix}: missing field: {key}")
    if not isinstance(feature.get("id"), str) or not str(feature.get("id")).strip():
        errors.append(f"{prefix}: id must be a non-empty string")
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
        for task_index, task in enumerate(task_split, start=1):
            if not isinstance(task, dict):
                errors.append(f"{prefix}: task_split #{task_index} must be a mapping")
                continue
            for task_key in ["id", "title"]:
                if not isinstance(task.get(task_key), str) or not str(task.get(task_key)).strip():
                    errors.append(f"{prefix}: task_split #{task_index} missing {task_key}")
            if "validation" in task and not isinstance(task.get("validation"), list):
                errors.append(f"{prefix}: task_split #{task_index} validation must be a list")


def collect_changes(root: Path, file_arg: str | None = None) -> tuple[list[str], list[FeatureRecord], list[Path]]:
    errors: list[str] = []
    records: list[FeatureRecord] = []
    files = change_files(root, file_arg)
    if not files:
        errors.append(f"no v2 change files found under {CHANGE_ROOT}")
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
        file_errors, file_records = validate_loaded_change(root, path, data)
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
