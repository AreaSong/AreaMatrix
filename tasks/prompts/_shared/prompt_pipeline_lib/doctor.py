from __future__ import annotations

from pathlib import Path

from .contracts import validate_granularity
from .coverage import validate_core_task_coverage, validate_page_contract_coverage
from .contracts import task_detail_kind
from .paths import (
    AUDIT_RULES,
    CODING_STANDARDS,
    DEPENDENCY_GRAPH,
    ENGINEERING_QUALITY_RULES,
    EXTERNAL_LINK_RE,
    MANIFEST_ROOT,
    MARKDOWN_LINK_RE,
    REPO_LOCAL_SKILLS,
    ROOT,
    TASK_SLICING_RULES,
    VALIDATION_DRIVER_MATRIX,
    VALIDATION_DRIVER_REPORT,
    ManifestEntry,
    TaskFile,
    label_sort_key,
    rel,
)
from .repository import (
    discovery_skill_file,
    is_allowed_new_path,
    load_manifests,
    looks_high_risk,
    scan_task_files,
    skill_file,
)


REQUIRED_MANIFEST_SECTIONS = (
    "Exact Docs",
    "Existing Code",
    "Expected New Paths",
    "Forbidden Touches",
    "Risk Level",
    "Validation",
)


def validate_graph(tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]) -> list[str]:
    errors: list[str] = []
    visiting: set[str] = set()
    visited: set[str] = set()
    for label in sorted(tasks, key=label_sort_key):
        if label in manifests:
            visit_graph_label(label, tasks, manifests, errors, visiting, visited, [])
    return errors


def visit_graph_label(
    label: str,
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
    errors: list[str],
    visiting: set[str],
    visited: set[str],
    trail: list[str],
) -> None:
    if label in visited:
        return
    if label in visiting:
        errors.append("dependency cycle: " + " -> ".join([*trail, label]))
        return
    visiting.add(label)
    for dep in manifests[label].depends:
        visit_dependency(dep, label, tasks, manifests, errors, visiting, visited, trail)
    visiting.remove(label)
    visited.add(label)


def visit_dependency(
    dep: str,
    label: str,
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
    errors: list[str],
    visiting: set[str],
    visited: set[str],
    trail: list[str],
) -> None:
    if dep not in tasks:
        errors.append(f"{label}: unknown dependency {dep}")
        return
    visit_graph_label(dep, tasks, manifests, errors, visiting, visited, [*trail, label])


def markdown_link_audit_paths() -> list[Path]:
    paths = base_markdown_link_paths()
    paths.extend(sorted(MANIFEST_ROOT.glob("phase-*.md")))
    paths.extend(sorted((ROOT / "docs" / "ux" / "page-specs").glob("*.md")))
    paths.extend(sorted((ROOT / "docs" / "core" / "capability-specs").glob("*.md")))
    paths.extend(sorted((ROOT / "docs" / "architecture").glob("*control-map.md")))
    return unique_paths(paths)


def base_markdown_link_paths() -> list[Path]:
    from .paths import PROMPTS_ROOT, SHARED_ROOT

    return [
        PROMPTS_ROOT / "README.md",
        SHARED_ROOT / "README.md",
        AUDIT_RULES,
        TASK_SLICING_RULES,
        ENGINEERING_QUALITY_RULES,
        DEPENDENCY_GRAPH,
        CODING_STANDARDS,
        MANIFEST_ROOT / "README.md",
    ]


def unique_paths(paths: list[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        if path not in seen:
            result.append(path)
            seen.add(path)
    return result


def markdown_link_target(raw_target: str) -> str | None:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1].strip()
    if not target or target.startswith("#") or EXTERNAL_LINK_RE.match(target):
        return None
    if " " in target:
        target = target.split()[0].strip()
    target = target.split("#", 1)[0].strip()
    return target or None


def validate_markdown_links() -> list[str]:
    errors: list[str] = []
    for path in markdown_link_audit_paths():
        errors.extend(validate_markdown_file_links(path))
    return errors


def validate_markdown_file_links(path: Path) -> list[str]:
    if not path.exists():
        return [f"missing markdown audit path: {rel(path)}"]
    errors: list[str] = []
    in_fence = False
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        in_fence = update_fence_state(line, in_fence)
        if in_fence or line.strip().startswith("```"):
            continue
        errors.extend(validate_markdown_line_links(path, line_no, line))
    return errors


def update_fence_state(line: str, in_fence: bool) -> bool:
    return not in_fence if line.strip().startswith("```") else in_fence


def validate_markdown_line_links(path: Path, line_no: int, line: str) -> list[str]:
    errors: list[str] = []
    for raw_target in MARKDOWN_LINK_RE.findall(line):
        target = markdown_link_target(raw_target)
        if target:
            errors.extend(validate_markdown_target(path, line_no, raw_target, target))
    return errors


def validate_markdown_target(
    path: Path,
    line_no: int,
    raw_target: str,
    target: str,
) -> list[str]:
    resolved = (path.parent / target).resolve()
    try:
        resolved.relative_to(ROOT)
    except ValueError:
        return [f"{rel(path)}:{line_no} markdown link escapes repo: {raw_target}"]
    if not resolved.exists():
        return [f"{rel(path)}:{line_no} broken markdown link: {raw_target}"]
    return []


def collect_doctor_findings() -> tuple[list[str], list[str], dict[str, TaskFile], dict[str, ManifestEntry]]:
    tasks, manifests, errors = load_task_and_manifest_state()
    if errors:
        return errors, [], tasks, manifests
    warnings: list[str] = []
    append_shared_resource_errors(errors)
    append_task_manifest_errors(errors, tasks, manifests)
    append_orphan_manifest_warnings(warnings, tasks, manifests)
    errors.extend(validate_graph(tasks, manifests))
    errors.extend(validate_page_contract_coverage(tasks, manifests))
    errors.extend(validate_core_task_coverage(tasks, manifests))
    errors.extend(validate_markdown_links())
    return errors, warnings, tasks, manifests


def load_task_and_manifest_state() -> tuple[dict[str, TaskFile], dict[str, ManifestEntry], list[str]]:
    try:
        tasks = scan_task_files()
    except ValueError as exc:
        return {}, {}, [str(exc)]
    try:
        manifests = load_manifests()
    except ValueError as exc:
        return tasks, {}, [str(exc)]
    return tasks, manifests, []


def append_shared_resource_errors(errors: list[str]) -> None:
    for path, message in required_shared_resources():
        if not path.exists():
            errors.append(f"{message}: {rel(path)}")
    for name in REPO_LOCAL_SKILLS:
        append_skill_errors(errors, name)


def required_shared_resources() -> list[tuple[Path, str]]:
    return [
        (AUDIT_RULES, "missing audit rules"),
        (TASK_SLICING_RULES, "missing task slicing rules"),
        (ENGINEERING_QUALITY_RULES, "missing engineering quality rules"),
        (DEPENDENCY_GRAPH, "missing dependency graph"),
        (CODING_STANDARDS, "missing coding standards"),
        (VALIDATION_DRIVER_MATRIX, "missing validation-driver reference"),
        (VALIDATION_DRIVER_REPORT, "missing validation-driver reference"),
    ]


def append_skill_errors(errors: list[str], name: str) -> None:
    if not skill_file(name).exists():
        errors.append(f"missing repo-local skill: {rel(skill_file(name))}")
    if not discovery_skill_file(name).exists():
        errors.append(f"missing repo-local skill discovery entry: {rel(discovery_skill_file(name))}")


def append_task_manifest_errors(
    errors: list[str],
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> None:
    for label, task in sorted(tasks.items(), key=lambda item: label_sort_key(item[0])):
        entry = manifests.get(label)
        if not entry:
            errors.append(f"{label}: missing manifest entry")
            continue
        errors.extend(validate_task_manifest(task, entry))


def validate_task_manifest(task: TaskFile, entry: ManifestEntry) -> list[str]:
    errors: list[str] = []
    if entry.source_task and entry.source_task != rel(task.path):
        errors.append(f"{task.label}: source task mismatch: {entry.source_task} != {rel(task.path)}")
    append_exact_doc_errors(errors, task.label, entry)
    append_expected_path_errors(errors, task.label, entry)
    append_risk_errors(errors, task.label, entry)
    append_validation_strategy_errors(errors, task, entry)
    append_section_errors(errors, task.label, entry)
    errors.extend(validate_granularity(task, entry))
    return errors


def append_exact_doc_errors(errors: list[str], label: str, entry: ManifestEntry) -> None:
    for doc in entry.exact_docs:
        if not (ROOT / doc).exists():
            errors.append(f"{label}: missing Exact Docs path: {doc}")


def append_expected_path_errors(errors: list[str], label: str, entry: ManifestEntry) -> None:
    for value in entry.expected_new_paths:
        if not is_allowed_new_path(value):
            errors.append(f"{label}: Expected New Paths outside allowed roots: {value}")


def append_risk_errors(errors: list[str], label: str, entry: ManifestEntry) -> None:
    if looks_high_risk(entry) and entry.risk not in {"High", "Mission-Critical"}:
        errors.append(f"{label}: high-risk-looking task is not marked High/Mission-Critical")


def append_validation_strategy_errors(errors: list[str], task: TaskFile, entry: ManifestEntry) -> None:
    if task.phase != "phase-4":
        return
    validation = entry.validation
    detail_kind = task_detail_kind(task, entry)
    if detail_kind in {"stage-verify", "foundation-verify"}:
        if "./dev check all" not in validation:
            errors.append(f"{task.label}: phase-4 stage/foundation verify must keep './dev check all'")
        return
    expected = f"./dev check task {task.label}"
    if expected not in validation:
        errors.append(f"{task.label}: phase-4 task validation must use '{expected}'")
    if "./dev check all" in validation:
        errors.append(f"{task.label}: phase-4 non-stage task must not require './dev check all'")


def append_section_errors(errors: list[str], label: str, entry: ManifestEntry) -> None:
    for section in REQUIRED_MANIFEST_SECTIONS:
        if section not in entry.sections:
            errors.append(f"{label}: missing manifest section {section}")


def append_orphan_manifest_warnings(
    warnings: list[str],
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> None:
    for label in sorted(set(manifests) - set(tasks), key=label_sort_key):
        warnings.append(f"{label}: manifest entry has no task file")
