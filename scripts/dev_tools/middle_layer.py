"""Middle-layer ledger checks for versioned workflow planning."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from .changes import (
    DEFAULT_VERSION,
    DraftArtifact,
    FeatureRecord,
    SLUG_RE,
    as_list,
    collect_changes,
    display_path,
    feature_id_matches_version,
    filter_feature_records,
    ordered_features,
    parse_yaml_subset,
    write_artifacts,
)
from .workflow_states import ARTIFACT_STATUSES, status_list


VERSION_ROOT = Path("workflow/versions")
MIDDLE_LAYER_ROOT_NAME = "middle-layer"
ALLOWED_STATUS = ARTIFACT_STATUSES


@dataclass(frozen=True)
class MiddleLayerRecord:
    file: Path
    data: dict[str, Any]

    @property
    def feature_id(self) -> str:
        return str(self.data.get("feature_id", ""))


def middle_layer_root(root: Path, version: str) -> Path:
    return root / VERSION_ROOT / version / MIDDLE_LAYER_ROOT_NAME


def middle_layer_files(root: Path, version: str, file_arg: str | None = None) -> list[Path]:
    if file_arg:
        path = Path(file_arg)
        return [path if path.is_absolute() else root / path]
    directory = middle_layer_root(root, version)
    return sorted(directory.glob("*.yaml")) if directory.is_dir() else []


def load_middle_layer(path: Path) -> dict[str, Any]:
    data = parse_yaml_subset(path.read_text(encoding="utf-8"), path)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: top-level YAML must be a mapping")
    return data


def validate_scalar_fields(root: Path, record: MiddleLayerRecord, version: str) -> list[str]:
    errors: list[str] = []
    prefix = f"{display_path(root, record.file)}"
    for key in ["id", "version", "feature_id", "module", "status"]:
        if not isinstance(record.data.get(key), str) or not str(record.data.get(key)).strip():
            errors.append(f"{prefix}: {key} must be a non-empty string")
    if record.data.get("version") != version:
        errors.append(f"{prefix}: version must be {version}")
    feature_id = record.feature_id
    if feature_id and not SLUG_RE.fullmatch(feature_id):
        errors.append(f"{prefix}: feature_id must be a lowercase slug")
    if feature_id and not feature_id_matches_version(feature_id, version):
        expected = "template-" if version == "v-template" else f"{version}-"
        errors.append(f"{prefix}: feature_id must start with {expected}")
    if record.data.get("status") not in ALLOWED_STATUS:
        errors.append(f"{prefix}: status must be one of {status_list(ALLOWED_STATUS)}")
    return errors


def selected_doc_text(root: Path, doc_ref: dict[str, Any], prefix: str) -> tuple[list[str], str]:
    errors: list[str] = []
    file_value = doc_ref.get("file")
    path = root / str(file_value) if isinstance(file_value, str) else None
    if not path or not path.is_file():
        return [f"{prefix}: doc file does not exist: {file_value}"], ""
    start = int_field(doc_ref.get("line_start"))
    end = int_field(doc_ref.get("line_end"))
    if start is None or end is None:
        return [f"{prefix}: line_start and line_end must be integers"], ""
    lines = path.read_text(encoding="utf-8").splitlines()
    if start < 1 or end < start or end > len(lines):
        return [f"{prefix}: line range is outside the file"], ""
    return errors, "\n".join(lines[start - 1 : end])


def validate_docs_refs(root: Path, record: MiddleLayerRecord) -> list[str]:
    errors: list[str] = []
    prefix = f"{display_path(root, record.file)}: feature {record.feature_id}"
    refs = record.data.get("docs_refs")
    if not isinstance(refs, list) or not refs:
        return [f"{prefix}: docs_refs must be a non-empty list"]
    for index, ref in enumerate(refs, start=1):
        ref_prefix = f"{prefix} docs_refs #{index}"
        if not isinstance(ref, dict):
            errors.append(f"{ref_prefix}: must be a mapping")
            continue
        for key in ["file", "line_start", "line_end", "heading", "excerpt"]:
            if key not in ref:
                errors.append(f"{ref_prefix}: missing field: {key}")
        ref_errors, selected = selected_doc_text(root, ref, ref_prefix)
        errors.extend(ref_errors)
        if not selected:
            continue
        heading = str(ref.get("heading", "")).strip()
        excerpt = str(ref.get("excerpt", "")).strip()
        if heading and heading not in selected:
            errors.append(f"{ref_prefix}: heading not found in selected line range")
        if excerpt and excerpt not in selected:
            errors.append(f"{ref_prefix}: excerpt not found in selected line range")
    return errors


def validate_named_list(root: Path, record: MiddleLayerRecord, key: str, required_fields: Sequence[str]) -> list[str]:
    errors: list[str] = []
    prefix = f"{display_path(root, record.file)}: feature {record.feature_id}"
    values = record.data.get(key)
    if not isinstance(values, list) or not values:
        return [f"{prefix}: {key} must be a non-empty list"]
    for index, value in enumerate(values, start=1):
        item_prefix = f"{prefix} {key} #{index}"
        if not isinstance(value, dict):
            errors.append(f"{item_prefix}: must be a mapping")
            continue
        for field in required_fields:
            if field not in value:
                errors.append(f"{item_prefix}: missing field: {field}")
    return errors


def validate_code_impacts(root: Path, record: MiddleLayerRecord) -> list[str]:
    errors: list[str] = []
    prefix = f"{display_path(root, record.file)}: feature {record.feature_id}"
    impacts = record.data.get("code_impacts")
    if not isinstance(impacts, dict):
        return [f"{prefix}: code_impacts must be a mapping"]
    for key in ["existing", "expected", "tests"]:
        if key not in impacts or not isinstance(impacts.get(key), list):
            errors.append(f"{prefix}: code_impacts.{key} must be a list")
    return errors


def validate_dependencies(root: Path, record: MiddleLayerRecord) -> list[str]:
    errors: list[str] = []
    prefix = f"{display_path(root, record.file)}: feature {record.feature_id}"
    deps = record.data.get("dependencies")
    if not isinstance(deps, dict):
        return [f"{prefix}: dependencies must be a mapping"]
    for key in ["features", "docs", "code", "tasks"]:
        if key not in deps or not isinstance(deps.get(key), list):
            errors.append(f"{prefix}: dependencies.{key} must be a list")
    return errors


def validate_slice_plan(root: Path, record: MiddleLayerRecord) -> list[str]:
    errors: list[str] = []
    prefix = f"{display_path(root, record.file)}: feature {record.feature_id}"
    values = record.data.get("slice_plan")
    if not isinstance(values, list) or not values:
        return [f"{prefix}: slice_plan must be a non-empty list"]
    seen: set[str] = set()
    for index, value in enumerate(values, start=1):
        item_prefix = f"{prefix} slice_plan #{index}"
        if not isinstance(value, dict):
            errors.append(f"{item_prefix}: must be a mapping")
            continue
        for key in ["id", "purpose", "inputs", "outputs", "acceptance"]:
            if key not in value:
                errors.append(f"{item_prefix}: missing field: {key}")
        task_id = str(value.get("id", ""))
        if task_id:
            if not SLUG_RE.fullmatch(task_id):
                errors.append(f"{item_prefix}: id must be a lowercase slug")
            if task_id in seen:
                errors.append(f"{item_prefix}: duplicate id: {task_id}")
            seen.add(task_id)
        for key in ["inputs", "outputs", "acceptance"]:
            if key in value and not isinstance(value.get(key), list):
                errors.append(f"{item_prefix}: {key} must be a list")
    return errors


def validate_record_shape(root: Path, record: MiddleLayerRecord, version: str) -> list[str]:
    errors: list[str] = []
    errors.extend(validate_scalar_fields(root, record, version))
    errors.extend(validate_docs_refs(root, record))
    errors.extend(validate_named_list(root, record, "insertions", ["target", "reason", "before", "after"]))
    errors.extend(validate_named_list(root, record, "links", ["feature", "relationship", "reason"]))
    errors.extend(validate_code_impacts(root, record))
    errors.extend(validate_dependencies(root, record))
    errors.extend(validate_slice_plan(root, record))
    prefix = f"{display_path(root, record.file)}: feature {record.feature_id}"
    if not isinstance(record.data.get("risk_boundaries"), list) or not record.data.get("risk_boundaries"):
        errors.append(f"{prefix}: risk_boundaries must be a non-empty list")
    return errors


def collect_middle_layers(root: Path, version: str, file_arg: str | None = None) -> tuple[list[str], list[MiddleLayerRecord], list[Path]]:
    errors: list[str] = []
    records: list[MiddleLayerRecord] = []
    files = middle_layer_files(root, version, file_arg)
    if not files:
        return [f"no {version} middle-layer files found under {VERSION_ROOT / version / MIDDLE_LAYER_ROOT_NAME}"], records, files
    for path in files:
        if not path.is_file():
            errors.append(f"missing middle-layer file: {path}")
            continue
        try:
            data = load_middle_layer(path)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        record = MiddleLayerRecord(file=path, data=data)
        errors.extend(validate_record_shape(root, record, version))
        records.append(record)
    errors.extend(validate_feature_graph(root, records))
    return errors, records, files


def validate_feature_graph(root: Path, records: Sequence[MiddleLayerRecord]) -> list[str]:
    errors: list[str] = []
    by_id: dict[str, MiddleLayerRecord] = {}
    for record in records:
        if not record.feature_id:
            continue
        if record.feature_id in by_id:
            errors.append(f"duplicate middle-layer feature id: {record.feature_id} ({by_id[record.feature_id].file} and {record.file})")
        by_id[record.feature_id] = record
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(record: MiddleLayerRecord, stack: list[str]) -> None:
        feature_id = record.feature_id
        if feature_id in visited:
            return
        if feature_id in visiting:
            errors.append(f"middle-layer dependency cycle: {' -> '.join([*stack, feature_id])}")
            return
        visiting.add(feature_id)
        deps = record.data.get("dependencies") if isinstance(record.data.get("dependencies"), dict) else {}
        for dep in as_list(deps.get("features")):
            if not isinstance(dep, str) or not dep.strip():
                errors.append(f"{display_path(root, record.file)}: dependencies.features values must be strings")
                continue
            if dep == feature_id:
                errors.append(f"{display_path(root, record.file)}: feature {feature_id} cannot depend on itself")
            elif dep not in by_id:
                errors.append(f"{display_path(root, record.file)}: feature {feature_id} depends on unknown middle-layer feature {dep}")
            else:
                visit(by_id[dep], [*stack, feature_id])
        visiting.remove(feature_id)
        visited.add(feature_id)

    for record in records:
        if record.feature_id:
            visit(record, [])
    return errors


def int_field(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def values_as_set(values: Sequence[Any]) -> set[str]:
    return {str(value) for value in values if isinstance(value, str) and value.strip()}


def doc_ref_key(value: dict[str, Any]) -> tuple[str, int, int]:
    return (str(value.get("file", "")), int_field(value.get("line_start")) or -1, int_field(value.get("line_end")) or -1)


def validate_middle_layer_against_changes(root: Path, version: str, middle_records: Sequence[MiddleLayerRecord], change_records: Sequence[FeatureRecord]) -> list[str]:
    errors: list[str] = []
    middle_by_id = {record.feature_id: record for record in middle_records if record.feature_id}
    change_by_id = {record.feature_id: record for record in change_records if record.feature_id}
    for feature_id in sorted(set(middle_by_id) - set(change_by_id)):
        errors.append(f"middle-layer feature has no matching changes feature: {feature_id}")
    for feature_id in sorted(set(change_by_id) - set(middle_by_id)):
        errors.append(f"changes feature has no matching middle-layer feature: {feature_id}")
    for feature_id in sorted(set(middle_by_id) & set(change_by_id)):
        middle = middle_by_id[feature_id]
        change = change_by_id[feature_id]
        if middle.data.get("module") != change.feature.get("module"):
            errors.append(f"{feature_id}: module mismatch between middle-layer and changes")
        middle_deps = middle.data.get("dependencies") if isinstance(middle.data.get("dependencies"), dict) else {}
        if values_as_set(middle_deps.get("features", [])) != values_as_set(as_list(change.feature.get("depends_on"))):
            errors.append(f"{feature_id}: feature dependency mismatch between middle-layer dependencies.features and changes depends_on")
        middle_docs = {doc_ref_key(ref) for ref in as_list(middle.data.get("docs_refs")) if isinstance(ref, dict)}
        change_docs = {doc_ref_key(ref) for ref in as_list(change.feature.get("doc_changes")) if isinstance(ref, dict)}
        if middle_docs != change_docs:
            errors.append(f"{feature_id}: docs_refs must match changes doc_changes file/line ranges")
        middle_tasks = {str(item.get("id")) for item in as_list(middle.data.get("slice_plan")) if isinstance(item, dict) and item.get("id")}
        change_tasks = {str(item.get("id")) for item in as_list(change.feature.get("task_split")) if isinstance(item, dict) and item.get("id")}
        if middle_tasks != change_tasks:
            errors.append(f"{feature_id}: slice_plan ids must match changes task_split ids")
    return errors


def collect_middle_layer_workflow(root: Path, version: str, feature: str | None = None) -> tuple[list[str], list[MiddleLayerRecord], list[FeatureRecord]]:
    errors, middle_records, _ = collect_middle_layers(root, version)
    change_errors, change_records, _ = collect_changes(root, None, version)
    errors.extend(change_errors)
    errors.extend(validate_middle_layer_against_changes(root, version, middle_records, change_records))
    if feature:
        selected_middle = [record for record in middle_records if record.feature_id == feature]
        if not selected_middle:
            errors.append(f"unknown middle-layer feature id: {feature}")
    else:
        selected_middle = middle_records
    filter_errors, selected_changes = filter_feature_records(change_records, feature)
    errors.extend(filter_errors)
    return errors, selected_middle, selected_changes


def middle_layer_readme(version: str) -> str:
    return f"""# {version} Middle-layer

Middle-layer ledgers are feature-level implementation intent records.

They connect docs discussion to executable workflow planning:

```text
docs discussion
-> middle-layer/*.yaml
-> changes/*.yaml
-> plans
-> drafts
-> queue
-> promotion preview
```

Each feature ledger records Exact Docs line references, insertion points, related
feature links, code impact, dependencies, slice plan, risk boundaries, and
acceptance inputs. It is a review artifact and must not write live
`tasks/prompts/**` or `progress.json`.
"""


def example_ledger(version: str) -> str:
    feature_id = f"{version}-example-feature"
    return f"""id: {feature_id}-middle-layer
version: {version}
feature_id: {feature_id}
module: example
status: draft
docs_refs:
  - file: docs/README.md
    line_start: 1
    line_end: 1
    heading: AreaMatrix
    excerpt: AreaMatrix
insertions:
  - target: docs/README.md
    reason: Describe where the feature is inserted into existing behavior.
    before: Existing behavior that must remain true.
    after: New behavior that becomes available after the insertion.
links:
  - feature: {version}-related-feature
    relationship: coordinates-with
    reason: Explain how the two features interact.
code_impacts:
  existing:
    - docs/README.md
  expected:
    - apps/macos/AreaMatrix/Features/Example/**
  tests:
    - apps/macos/AreaMatrixTests/**
dependencies:
  features: []
  docs:
    - docs/README.md
  code: []
  tasks: []
slice_plan:
  - id: docs-contract
    purpose: Align docs and public contracts before implementation.
    inputs:
      - docs/README.md
    outputs:
      - workflow plan review artifact
    acceptance:
      - ./dev workflow doctor
risk_boundaries:
  - Do not write live tasks/prompts from middle-layer planning.
"""


def middle_layer_artifacts(root: Path, version: str, out_dir: str | None) -> list[DraftArtifact]:
    target = Path(out_dir) if out_dir else middle_layer_root(root, version)
    if not target.is_absolute():
        target = root / target
    return [
        DraftArtifact(target / "README.md", middle_layer_readme(version)),
        DraftArtifact(target / "example.yaml", example_ledger(version)),
    ]


def run_middle_layer_init(root: Path, args: argparse.Namespace) -> int:
    if args.force and not args.write:
        print("workflow middle init: --force requires --write")
        return 1
    artifacts = middle_layer_artifacts(root, args.version, args.out_dir)
    if not args.write:
        print("Workflow middle-layer init")
        print("- mode: preview only; no files written")
        print("- live queue: not modified")
        print("- progress file: not modified")
        for artifact in artifacts:
            print()
            print(f"--- {display_path(root, artifact.path)} ---")
            print(artifact.content.rstrip())
        return 0
    try:
        written = write_artifacts(artifacts, force=args.force, label="workflow middle-layer file")
    except FileExistsError as exc:
        print(f"workflow middle init: {exc}")
        return 1
    print("workflow middle init: wrote files")
    print(f"- files: {len(written)}")
    for path in written:
        print(f"  - {path}")
    return 0


def run_middle_layer_doctor(root: Path, args: argparse.Namespace) -> int:
    errors, records, changes = collect_middle_layer_workflow(root, args.version, args.feature)
    if errors:
        print("workflow middle doctor: FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("workflow middle doctor: OK")
    print(f"- version: {args.version}")
    print(f"- middle-layer features: {len(records)}")
    print(f"- changes features: {len(changes)}")
    return 0


def run_middle_layer_preview(root: Path, args: argparse.Namespace) -> int:
    errors, records, changes = collect_middle_layer_workflow(root, args.version, args.feature)
    if errors:
        print("workflow middle preview: doctor failed")
        for error in errors:
            print(f"- {error}")
        return 1
    changes_by_id = {record.feature_id: record for record in changes}
    print("Workflow middle-layer preview")
    print("- mode: preview only; no files written")
    print("- live queue: not modified")
    for index, record in enumerate(ordered_middle_layers(records), start=1):
        change = changes_by_id.get(record.feature_id)
        deps = record.data.get("dependencies") if isinstance(record.data.get("dependencies"), dict) else {}
        print()
        print(f"{index}. {record.feature_id} [{record.data.get('module', 'unknown')}]")
        print(f"   ledger: {display_path(root, record.file)}")
        print(f"   change: {display_path(root, change.file) if change else 'missing'}")
        print(f"   depends_on: {', '.join(values_as_set(deps.get('features', []))) or 'None'}")
        print("   docs:")
        for ref in as_list(record.data.get("docs_refs")):
            if isinstance(ref, dict):
                print(f"     - {ref.get('file')}:{ref.get('line_start')}-{ref.get('line_end')} {ref.get('heading')}")
        print("   slices:")
        for item in as_list(record.data.get("slice_plan")):
            if isinstance(item, dict):
                print(f"     - {item.get('id')}: {item.get('purpose')}")
    return 0


def ordered_middle_layers(records: Sequence[MiddleLayerRecord]) -> list[MiddleLayerRecord]:
    by_id = {record.feature_id: record for record in records if record.feature_id}
    result: list[MiddleLayerRecord] = []
    visited: set[str] = set()

    def visit(record: MiddleLayerRecord) -> None:
        if record.feature_id in visited:
            return
        deps = record.data.get("dependencies") if isinstance(record.data.get("dependencies"), dict) else {}
        for dep in as_list(deps.get("features")):
            if isinstance(dep, str) and dep in by_id:
                visit(by_id[dep])
        visited.add(record.feature_id)
        result.append(record)

    for record in records:
        visit(record)
    return result


def run_workflow_middle(root: Path, args: argparse.Namespace) -> int:
    if args.middle_command == "init":
        return run_middle_layer_init(root, args)
    if args.middle_command == "doctor":
        return run_middle_layer_doctor(root, args)
    if args.middle_command == "preview":
        return run_middle_layer_preview(root, args)
    print("workflow middle: unsupported command")
    return 2
