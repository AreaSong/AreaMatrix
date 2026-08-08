"""Checks behind ./dev check."""

from __future__ import annotations

import ast
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote, urlparse

from .build import run_core_build
from .common import fail, project_root, require_command, require_file, run_step
from .execution_paths import manifest_root, prompt_pipeline_path, shared_root, task_root
from .macos import run_macos_tests
from .skills import SimpleYAMLError, parse_frontmatter, parse_simple_yaml
from .wording import run_wording_audit


V1_LEGACY_CAPABILITY_TEST_TARGETS = {
    "search-query-files": (
        "search_query_files_contract_api",
        "search_query_files_implementation",
        "search_query_files_failure_recovery",
        "search_query_files_validation",
    ),
    "search-filters": (
        "search_filters_contract_api",
        "search_filters_implementation",
        "search_filters_failure_recovery",
        "search_filters_validation",
    ),
    "saved-search-core": (
        "saved_search_contract_api",
        "saved_search_implementation",
        "saved_search_failure_recovery",
        "saved_search_validation",
    ),
    "smart-list": (
        "smart_list_contract_api",
        "smart_list_implementation",
        "smart_list_failure_recovery",
    ),
}

V1_LEGACY_CAPABILITY_KEYWORDS = {
    "search-query-files": ("search query files",),
    "search-filters": ("search filters",),
    "saved-search-core": ("saved search",),
    "smart-list": ("smart list", "smart-list", "smart-lists"),
}

V1_LEGACY_CAPABILITY_IDS = {
    ("2", "01"): "search-query-files",
    ("2", "02"): "search-filters",
    ("2", "03"): "saved-search-core",
    ("2", "04"): "smart-list",
}

ALLOW_FULL_TASK_FALLBACK_ENV = "AREAMATRIX_TASK_CHECK_FULL_FALLBACK"

FILE_SAFETY_GATE_KEYWORDS = (
    "adopt",
    "database",
    "delete",
    "db",
    "fsevents",
    "icloud",
    "import",
    "migration",
    "move",
    "recovery",
    "reindex",
    "rename",
    "rollback",
    "staging",
    "sync",
    "transactional",
    "trash",
    "user file",
    "用户文件",
    "删除",
    "回滚",
    "恢复",
    "接管",
    "移动",
    "迁移",
    "导入",
    "同步",
)

AI_RUNTIME_ENV_CONTRACT = {
    "AREAMATRIX_AI_CLASSIFICATION_LOCAL_RUNTIME": "external",
    "AREAMATRIX_AI_CLASSIFICATION_REMOTE_RUNTIME": "external",
    "AREAMATRIX_AI_SEMANTIC_REMOTE_RUNTIME": "external",
    "AREAMATRIX_AI_SUMMARY_LOCAL_RUNTIME": "external",
    "AREAMATRIX_AI_SUMMARY_REMOTE_RUNTIME": "external",
    "AREAMATRIX_AI_TAGS_LOCAL_RUNTIME": "external",
    "AREAMATRIX_AI_TAGS_REMOTE_RUNTIME": "external",
}

# GitHub Actions accepts this fixed set of token permission scopes. Keep the
# list local so workflow validation catches unsupported keys before GitHub
# rejects the workflow file.
GITHUB_ACTIONS_PERMISSION_KEYS = frozenset(
    {
        "actions",
        "attestations",
        "checks",
        "contents",
        "deployments",
        "discussions",
        "id-token",
        "issues",
        "models",
        "packages",
        "pages",
        "pull-requests",
        "security-events",
        "statuses",
    }
)
GITHUB_ACTIONS_PERMISSION_VALUES = frozenset({"read", "write", "none"})


@dataclass(frozen=True)
class TaskManifestEntry:
    raw: str
    risk: str
    exact_docs: tuple[str, ...]
    existing_code: tuple[str, ...]
    expected_new_paths: tuple[str, ...]
    forbidden_touches: tuple[str, ...]
    validation: tuple[str, ...]


class FailureCollector:
    def __init__(self) -> None:
        self.count = 0

    def fail(self, message: str) -> None:
        self.count += 1
        print(f"ERROR: {message}", file=os.sys.stderr)


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _check_file(root: Path, failures: FailureCollector, rel_path: str) -> None:
    if not (root / rel_path).is_file():
        failures.fail(f"missing file: {rel_path}")


def _require_text(root: Path, failures: FailureCollector, rel_path: str, pattern: str, label: str) -> None:
    path = root / rel_path
    if not path.is_file():
        failures.fail(f"missing file for text check: {rel_path}")
        return
    if not re.search(pattern, _read(path), flags=re.MULTILINE):
        failures.fail(f"{rel_path} missing: {label}")


def _forbid_text(root: Path, failures: FailureCollector, rel_path: str, pattern: str, label: str) -> None:
    path = root / rel_path
    if path.is_file() and re.search(pattern, _read(path), flags=re.MULTILINE):
        failures.fail(f"{rel_path} contains forbidden text: {label}")


def _markdown_link_targets(text: str) -> list[str]:
    targets: list[str] = []
    in_fence = False
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        line = re.sub(r"`[^`]*`", "", line)
        for match in re.finditer(r"!?(?:\[[^\]]*\])\((?P<body>[^)]+)\)", line):
            body = match.group("body").strip()
            if body.startswith("<") and ">" in body:
                target = body[1 : body.index(">")]
            else:
                target = body.split(maxsplit=1)[0]
            if target:
                targets.append(target)
    return targets


def _local_markdown_target(root: Path, source: Path, target: str) -> Path | None:
    parsed = urlparse(target)
    if parsed.scheme or target.startswith(("#", "//")):
        return None
    decoded = unquote(parsed.path)
    if not decoded:
        return None
    if decoded.startswith("/"):
        return (root / decoded.lstrip("/")).resolve()
    return (source.parent / decoded).resolve()


def _check_markdown_structure(path: Path, text: str, failures: FailureCollector) -> None:
    relative = path.as_posix()
    in_fence = False
    fence_marker = ""
    h1_lines: list[int] = []
    related_found = False

    for line_number, line in enumerate(text.splitlines(), start=1):
        stripped = line.lstrip()
        marker = "```" if stripped.startswith("```") else "~~~" if stripped.startswith("~~~") else ""
        if marker:
            if in_fence and marker == fence_marker:
                in_fence = False
                fence_marker = ""
            elif not in_fence:
                if not stripped[len(marker) :].strip():
                    failures.fail(f"{relative}:{line_number} opening code fence is missing a language")
                in_fence = True
                fence_marker = marker
            continue
        if in_fence:
            continue
        if re.match(r"^#\s+\S", line):
            h1_lines.append(line_number)
        if line.strip() == "## Related":
            related_found = True

    if in_fence:
        failures.fail(f"{relative} has an unclosed code fence")
    if len(h1_lines) != 1:
        failures.fail(f"{relative} must contain exactly one H1 outside code fences, found {len(h1_lines)}")
    else:
        lines = text.splitlines()
        first_content = next(
            (line.strip() for line in lines[h1_lines[0] :] if line.strip()),
            "",
        )
        if not first_content.startswith(">"):
            failures.fail(f"{relative} must place a blockquote summary immediately after its H1")
    if not related_found:
        failures.fail(f"{relative} is missing a top-level ## Related section")
    if not text.endswith("\n"):
        failures.fail(f"{relative} must end with a newline")
    elif text.endswith("\n\n"):
        failures.fail(f"{relative} has a blank line at EOF")


def run_docs_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    failures = FailureCollector()
    roots = [root / "README.md", root / "README.zh-CN.md", root / "docs/README.md"]
    for path in roots:
        if not path.is_file():
            failures.fail(f"missing documentation entry point: {path.relative_to(root)}")

    markdown_files = sorted(path for path in (root / "docs").rglob("*.md") if path.is_file())
    for path in markdown_files:
        _check_markdown_structure(path.relative_to(root), _read(path), failures)
    checked_files = [path for path in roots if path.is_file()] + markdown_files
    local_links: dict[Path, set[Path]] = {}
    for source in checked_files:
        local_links[source] = set()
        for target in _markdown_link_targets(_read(source)):
            resolved = _local_markdown_target(root, source, target)
            if resolved is None:
                continue
            try:
                resolved.relative_to(root)
            except ValueError:
                failures.fail(f"{source.relative_to(root)} links outside repository: {target}")
                continue
            if not resolved.exists():
                failures.fail(f"{source.relative_to(root)} has broken link: {target}")
                continue
            if resolved.is_file() and resolved.suffix.lower() == ".md":
                local_links[source].add(resolved)

    reachable: set[Path] = set()
    pending = [path for path in roots if path.is_file()]
    while pending:
        source = pending.pop()
        if source in reachable:
            continue
        reachable.add(source)
        pending.extend(local_links.get(source, ()))
    for path in markdown_files:
        if path not in reachable:
            failures.fail(f"documentation page is not reachable from README entries: {path.relative_to(root)}")

    forbidden_root_terms = {
        r"\.codex/": "Codex runtime detail",
        r"\btask-loop\b": "task-loop detail",
        r"tasks/(?:active|backlog|done)": "task state detail",
        r"workflow/residuals/": "residual ledger detail",
    }
    for path in roots[:2]:
        if not path.is_file():
            continue
        text = _read(path)
        for pattern, label in forbidden_root_terms.items():
            if re.search(pattern, text, flags=re.IGNORECASE):
                failures.fail(f"{path.relative_to(root)} contains internal {label}")

    if failures.count:
        print(f"docs check: FAILED ({failures.count} issue(s))", file=os.sys.stderr)
        return 1
    print(f"docs check: OK ({len(markdown_files)} page(s))")
    return 0


def _git_text(root: Path, *args: str) -> str | None:
    result = subprocess.run(
        ["git", *args],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def _check_feature_evolution_evidence(root: Path, failures: FailureCollector) -> None:
    rel_path = "workflow/versions/v1-mvp/evidence/feature-evolution-evidence.json"
    path = root / rel_path
    if not path.is_file():
        failures.fail(f"missing file: {rel_path}")
        return
    try:
        data = json.loads(_read(path))
    except json.JSONDecodeError as error:
        failures.fail(f"{rel_path} is not valid JSON: {error}")
        return

    if data.get("schema_version") != 1:
        failures.fail(f"{rel_path} schema_version must be 1")
    baseline = data.get("baseline_commit")
    if not isinstance(baseline, str) or not re.fullmatch(r"[0-9a-f]{40}", baseline):
        failures.fail(f"{rel_path} baseline_commit must be a full Git hash")
        return
    baseline_rules = _git_text(root, "show", f"{baseline}:apps/macos/AGENTS.md")
    if baseline_rules is None or "新功能先判断 feature owner" not in baseline_rules:
        failures.fail(f"{rel_path} baseline must contain the feature owner rule")

    batches = data.get("batches")
    if not isinstance(batches, list) or len(batches) < 3:
        failures.fail(f"{rel_path} must record at least three evolution batches")
        return
    seen_commits: set[str] = set()
    seen_dates: set[str] = set()
    for batch in batches:
        if not isinstance(batch, dict):
            failures.fail(f"{rel_path} contains a non-object batch")
            continue
        commit = batch.get("commit")
        if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
            failures.fail(f"{rel_path} batch commit must be a full Git hash")
            continue
        if commit in seen_commits:
            failures.fail(f"{rel_path} repeats batch commit {commit}")
        seen_commits.add(commit)
        if _git_text(root, "merge-base", "--is-ancestor", baseline, commit) is None:
            failures.fail(f"{rel_path} batch {commit} is not after the governance baseline")
        commit_date = _git_text(root, "show", "-s", "--format=%cs", commit)
        if commit_date is None:
            failures.fail(f"{rel_path} batch commit does not exist: {commit}")
            continue
        seen_dates.add(commit_date)
        changed_text = _git_text(root, "diff-tree", "--no-commit-id", "--name-only", "-r", commit)
        if changed_text is None:
            failures.fail(f"{rel_path} cannot inspect batch commit: {commit}")
            continue
        changed_paths = set(changed_text.splitlines())
        owners = batch.get("owners")
        feature_paths = batch.get("feature_paths")
        if not isinstance(owners, list) or not owners or not all(isinstance(owner, str) for owner in owners):
            failures.fail(f"{rel_path} batch {commit} must declare owners")
            continue
        if not isinstance(feature_paths, list) or not feature_paths:
            failures.fail(f"{rel_path} batch {commit} must declare feature_paths")
            continue
        for feature_path in feature_paths:
            if feature_path not in changed_paths:
                failures.fail(f"{rel_path} batch {commit} did not change {feature_path}")
                continue
            if not any(feature_path.startswith(f"apps/macos/AreaMatrix/Features/{owner}/") for owner in owners):
                failures.fail(f"{rel_path} batch {commit} feature path has no declared owner: {feature_path}")
        for boundary_path in batch.get("boundary_paths", []):
            if boundary_path not in changed_paths:
                failures.fail(f"{rel_path} batch {commit} did not change boundary path {boundary_path}")
            if not boundary_path.startswith(
                (
                    "apps/macos/AreaMatrix/App/",
                    "apps/macos/AreaMatrix/Bridge/",
                    "apps/macos/AreaMatrix/PlatformServices/",
                    "apps/macos/AreaMatrix.xcodeproj/",
                )
            ):
                failures.fail(f"{rel_path} batch {commit} has an invalid boundary path: {boundary_path}")
        for test_path in batch.get("test_paths", []):
            if test_path not in changed_paths or not test_path.startswith("apps/macos/AreaMatrixTests/"):
                failures.fail(f"{rel_path} batch {commit} has invalid test evidence: {test_path}")
    if len(seen_dates) < 3:
        failures.fail(f"{rel_path} must cover at least three distinct evolution dates")


def _check_workflow_has_no_paths_filter(root: Path, failures: FailureCollector, rel_path: str) -> None:
    _check_file(root, failures, rel_path)
    path = root / rel_path
    if path.is_file() and re.search(r"^[ \t]+paths:", _read(path), flags=re.MULTILINE):
        failures.fail(f"{rel_path} must not use PR/push paths filters; enterprise CI runs on every PR")


def _check_workflow_permissions(root: Path, failures: FailureCollector) -> None:
    """Reject unsupported or malformed GitHub Actions permission scopes."""

    workflow_root = root / ".github/workflows"
    if not workflow_root.is_dir():
        failures.fail(".github/workflows directory is missing")
        return

    permission_line = re.compile(r"^(?P<indent> *)permissions:\s*(?P<value>.*)$")
    for path in sorted((*workflow_root.glob("*.yml"), *workflow_root.glob("*.yaml"))):
        lines = path.read_text(encoding="utf-8").splitlines()
        block_scalar_indent: int | None = None
        for index, raw_line in enumerate(lines):
            stripped_line = raw_line.strip()
            indent = len(raw_line) - len(raw_line.lstrip(" "))
            if block_scalar_indent is not None:
                if stripped_line and indent <= block_scalar_indent:
                    block_scalar_indent = None
                else:
                    continue
            if re.search(r":\s*[|>]\s*[+-]?\d*\s*(?:#.*)?$", raw_line):
                block_scalar_indent = indent
                continue
            match = permission_line.match(raw_line)
            if match is None:
                continue
            line_no = index + 1
            inline_value = match.group("value").split(" #", 1)[0].strip()
            if inline_value:
                _check_inline_workflow_permissions(path, line_no, inline_value, failures)
                continue

            base_indent = len(match.group("indent"))
            _check_mapped_workflow_permissions(path, lines, index, base_indent, failures)


def _check_inline_workflow_permissions(
    path: Path,
    line_no: int,
    value: str,
    failures: FailureCollector,
) -> None:
    if value in {"read-all", "write-all", "{}"}:
        return
    if not (value.startswith("{") and value.endswith("}")):
        failures.fail(f"{path}:{line_no} has unsupported permissions value: {value}")
        return

    mapping_line = re.compile(r"^(?P<key>[\"']?[A-Za-z][A-Za-z0-9_-]*[\"']?):(?:\s*(?P<value>.*))?$")
    entries = [entry.strip() for entry in value[1:-1].split(",") if entry.strip()]
    for entry in entries:
        entry_match = mapping_line.match(entry)
        if entry_match is None:
            failures.fail(f"{path}:{line_no} has malformed inline permission: {entry}")
            continue
        _validate_workflow_permission_entry(
            path,
            line_no,
            entry_match.group("key"),
            entry_match.group("value") or "",
            failures,
        )


def _check_mapped_workflow_permissions(
    path: Path,
    lines: list[str],
    permission_index: int,
    base_indent: int,
    failures: FailureCollector,
) -> None:
    mapping_line = re.compile(r"^(?P<key>[\"']?[A-Za-z][A-Za-z0-9_-]*[\"']?):(?:\s*(?P<value>.*))?$")
    child_indent: int | None = None
    for child_index in range(permission_index + 1, len(lines)):
        child_line = lines[child_index]
        if not child_line.strip() or child_line.lstrip().startswith("#"):
            continue
        indent = len(child_line) - len(child_line.lstrip(" "))
        if indent <= base_indent:
            break
        if child_indent is None:
            child_indent = indent
        if indent != child_indent:
            continue
        child_match = mapping_line.match(child_line.strip())
        child_line_no = child_index + 1
        if child_match is None:
            failures.fail(f"{path}:{child_line_no} has malformed permission entry")
            continue
        _validate_workflow_permission_entry(
            path,
            child_line_no,
            child_match.group("key"),
            child_match.group("value") or "",
            failures,
        )


def _validate_workflow_permission_entry(
    path: Path,
    line_no: int,
    key: str,
    value: str,
    failures: FailureCollector,
) -> None:
    key = _normalize_workflow_scalar(key)
    if key not in GITHUB_ACTIONS_PERMISSION_KEYS:
        failures.fail(f"{path}:{line_no} uses unsupported GitHub Actions permission key: {key}")
    normalized_value = _normalize_workflow_scalar(value.split(" #", 1)[0].strip())
    if normalized_value not in GITHUB_ACTIONS_PERMISSION_VALUES:
        failures.fail(f"{path}:{line_no} uses invalid GitHub Actions permission value for {key}: {value}")


def _normalize_workflow_scalar(value: str) -> str:
    """Match YAML's plain scalar value for the small workflow subset we inspect."""

    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def _pbx_object_body(project_text: str, object_id: str) -> str | None:
    match = re.search(
        rf"(?ms)^(?P<indent>[ \t]*){re.escape(object_id)} /\*[^\n]*?\*/ = \{{"
        rf"(?P<body>.*?)^(?P=indent)\}};",
        project_text,
    )
    return match.group("body") if match else None


def _macos_test_target_source_build_file_ids(project_text: str) -> set[str] | None:
    target_match = re.search(
        r"(?m)^[ \t]*([A-F0-9]{24}) /\* AreaMatrixTests \*/ = \{\s*isa = PBXNativeTarget;",
        project_text,
    )
    if not target_match:
        return None
    target_body = _pbx_object_body(project_text, target_match.group(1))
    if target_body is None:
        return None
    phases_match = re.search(r"buildPhases = \((.*?)\);", target_body, flags=re.DOTALL)
    if not phases_match:
        return None

    source_build_files: set[str] = set()
    for phase_id in re.findall(r"([A-F0-9]{24}) /\*", phases_match.group(1)):
        phase_body = _pbx_object_body(project_text, phase_id)
        if phase_body is None or "isa = PBXSourcesBuildPhase;" not in phase_body:
            continue
        files_match = re.search(r"files = \((.*?)\);", phase_body, flags=re.DOTALL)
        if files_match:
            source_build_files.update(re.findall(r"([A-F0-9]{24}) /\*", files_match.group(1)))
    return source_build_files


def _check_macos_governance_test_membership(root: Path, failures: FailureCollector) -> None:
    tests_dir = root / "apps/macos/AreaMatrixTests"
    project_file = root / "apps/macos/AreaMatrix.xcodeproj/project.pbxproj"
    governance_files = sorted(
        {
            path
            for pattern in ("*GovernanceTests.swift", "MacOSGovernance*TestSupport.swift")
            for path in tests_dir.glob(pattern)
            if path.is_file()
        }
    )
    if not governance_files:
        failures.fail("no macOS governance XCTest files found for Xcode target membership audit")
        return
    if not project_file.is_file():
        failures.fail(f"missing Xcode project file for governance test membership: {project_file}")
        return

    project_text = _read(project_file)
    target_source_ids = _macos_test_target_source_build_file_ids(project_text)
    if target_source_ids is None:
        failures.fail("AreaMatrixTests PBXSourcesBuildPhase could not be resolved")
        return

    for source_file in governance_files:
        source_path = source_file.relative_to(root / "apps/macos").as_posix()
        file_ref_match = re.search(
            rf"(?m)^[ \t]*([A-F0-9]{{24}}) /\*.*?\*/ = \{{isa = PBXFileReference;"
            rf"[^\n]*path = \"?{re.escape(source_path)}\"?;",
            project_text,
        )
        if not file_ref_match:
            failures.fail(f"macOS governance test missing PBXFileReference: {source_path}")
            continue

        file_ref_id = file_ref_match.group(1)
        build_file_ids = set(
            re.findall(
                rf"(?m)^[ \t]*([A-F0-9]{{24}}) /\*.*?\*/ = \{{isa = PBXBuildFile;"
                rf" fileRef = {file_ref_id}\b",
                project_text,
            )
        )
        if not build_file_ids:
            failures.fail(f"macOS governance test missing PBXBuildFile: {source_path}")
        elif build_file_ids.isdisjoint(target_source_ids):
            failures.fail(f"macOS governance test missing AreaMatrixTests Sources membership: {source_path}")


MACOS_TEST_PLANS = {
    "apps/macos/AreaMatrix-Unit.xctestplan": "Unit",
    "apps/macos/AreaMatrix-Feature.xctestplan": "Feature",
    "apps/macos/AreaMatrix-Integration.xctestplan": "Integration",
    "apps/macos/AreaMatrix-Performance.xctestplan": "Performance",
    "apps/macos/AreaMatrix-Release.xctestplan": "Release",
}


def _check_macos_test_plans(root: Path, failures: FailureCollector) -> None:
    target_identifier = "0A0000000000000000000041"
    for relative_path, expected_name in MACOS_TEST_PLANS.items():
        path = root / relative_path
        if not path.is_file():
            failures.fail(f"missing macOS XCTest plan: {relative_path}")
            continue
        try:
            payload = json.loads(_read(path))
        except json.JSONDecodeError as error:
            failures.fail(f"invalid macOS XCTest plan JSON: {relative_path}: {error}")
            continue

        configurations = payload.get("configurations", [])
        if not configurations or configurations[0].get("name") != expected_name:
            failures.fail(f"macOS XCTest plan has unexpected configuration name: {relative_path}")
        targets = payload.get("testTargets", [])
        if len(targets) != 1:
            failures.fail(f"macOS XCTest plan must contain exactly one test target: {relative_path}")
            continue
        target = targets[0].get("target", {})
        if target.get("name") != "AreaMatrixTests" or target.get("identifier") != target_identifier:
            failures.fail(f"macOS XCTest plan must target AreaMatrixTests: {relative_path}")
        selected = targets[0].get("selectedTests", [])
        if not selected or any(not isinstance(item, str) or "/" not in item for item in selected):
            failures.fail(f"macOS XCTest plan must list concrete class/test identifiers: {relative_path}")
        if len(selected) != len(set(selected)):
            failures.fail(f"macOS XCTest plan contains duplicate selected tests: {relative_path}")


MACOS_DISPLAY_ARGUMENT_NAMES = (
    "accessibilityHint",
    "accessibilityLabel",
    "alternative",
    "blockedReason",
    "blockedHelpSuffix",
    "caption",
    "description",
    "detail",
    "disabledReason",
    "emptyMessage",
    "fallbackMessage",
    "fallbackRecovery",
    "fallback",
    "fieldError",
    "hint",
    "label",
    "loadMoreTitle",
    "message",
    "prefix",
    "prompt",
    "reasonLabel",
    "recovery",
    "suggestedAction",
    "statusText",
    "subtitle",
    "title",
    "toast",
    "userMessage",
    "warning",
    "defaultHelp",
)


def _localization_placeholders_match(
    source_value: str,
    translated_value: str,
    placeholder_pattern: re.Pattern[str],
) -> bool:
    source_placeholders = placeholder_pattern.findall(source_value.replace("%%", ""))
    translated_placeholders = placeholder_pattern.findall(translated_value.replace("%%", ""))
    all_placeholders = source_placeholders + translated_placeholders
    if all_placeholders and all(re.match(r"%\d+\$", item) for item in all_placeholders):
        return sorted(source_placeholders) == sorted(translated_placeholders)
    return source_placeholders == translated_placeholders


MACOS_L10N_KEY_FUNCTIONS = (
    "display",
    "editableDefault",
    "format",
    "message",
    "plural",
    "pluralMessage",
    "string",
)


def _swift_l10n_calls(source: str) -> list[tuple[int, str, str | None]]:
    """Returns L10n calls with a decoded static first argument, or None for a dynamic key."""
    function_names = "|".join(map(re.escape, MACOS_L10N_KEY_FUNCTIONS))
    pattern = re.compile(rf"\bL10n\.(?P<function>{function_names})\s*\(")
    calls: list[tuple[int, str, str | None]] = []
    for match in pattern.finditer(source):
        cursor = match.end()
        while cursor < len(source) and source[cursor].isspace():
            cursor += 1
        line = source.count("\n", 0, match.start()) + 1
        if cursor >= len(source) or source[cursor] != '"':
            calls.append((line, match.group("function"), None))
            continue

        end = cursor + 1
        escaped = False
        while end < len(source):
            character = source[end]
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                break
            elif character in "\r\n":
                break
            end += 1
        if end >= len(source) or source[end] != '"':
            calls.append((line, match.group("function"), None))
            continue

        raw_literal = source[cursor:end + 1]
        if "\\(" in raw_literal:
            calls.append((line, match.group("function"), None))
            continue
        try:
            key = json.loads(raw_literal)
        except json.JSONDecodeError:
            key = None
        calls.append((line, match.group("function"), key if isinstance(key, str) else None))
    return calls


def _swift_raw_display_string_violations(source: str) -> list[tuple[int, str]]:
    argument_names = "|".join(map(re.escape, MACOS_DISPLAY_ARGUMENT_NAMES))
    pattern = re.compile(
        rf'(?<![A-Za-z0-9_\".])(?P<name>{argument_names})\s*:\s*'
        rf'(?P<literal>\"\"\".*?\"\"\"|\"(?:\\.|[^\"\\])*\")',
        re.DOTALL,
    )
    violations: list[tuple[int, str]] = []
    for match in pattern.finditer(source):
        name = match.group("name")
        literal = match.group("literal")
        if literal in {'""', '""""""'}:
            continue
        prefix = source[max(0, match.start() - 120):match.start()]
        if name == "message" and re.search(r"\bCoreError\.[A-Za-z][A-Za-z0-9_]*\s*\(\s*$", prefix):
            continue
        if name == "label" and literal.startswith('"tag:\\('):
            continue
        without_interpolation = re.sub(r"\\\([^)]*\)", "", literal)
        visible_remainder = without_interpolation.strip('" \t\r\n:|/.,;!?-=>()[]{}')
        if not visible_remainder:
            continue
        line = source.count("\n", 0, match.start()) + 1
        violations.append((line, name))
    return violations


def _swift_raw_localized_error_violations(source: str) -> list[int]:
    block_pattern = re.compile(
        r"var\s+errorDescription\s*:\s*String\?\s*\{(?P<body>.*?)(?=^\s*\})",
        re.DOTALL | re.MULTILINE,
    )
    literal_pattern = re.compile(
        r'^\s*(?:return\s+)?(?:""".*?"""|"(?:\\.|[^"\\])*")\s*$',
        re.DOTALL | re.MULTILINE,
    )
    violations: list[int] = []
    for block in block_pattern.finditer(source):
        body = block.group("body")
        for literal in literal_pattern.finditer(body):
            line = source.count("\n", 0, block.start("body") + literal.start()) + 1
            violations.append(line)
    return violations


def _swift_unlocalized_dynamic_display_violations(source: str) -> list[tuple[int, str]]:
    violations: list[tuple[int, str]] = []
    lines = source.splitlines()
    for index, line in enumerate(lines, start=1):
        if "Text(" in line and re.search(r"\.status\.tag\b", line) and "L10n." not in line:
            violations.append((index, "status.tag"))
        if "L10n." in line or "\\(" not in line:
            continue
        context = "\n".join(lines[max(0, index - 12):index])
        property_match = re.findall(
            r"\bvar\s+(statusDisplay|searchFiltersAccessibilityLabel)\s*:\s*String\s*\{",
            context,
        )
        if property_match:
            violations.append((index, property_match[-1]))

    state_pattern = re.compile(
        r"\b(?P<name>namingPrefix|replaceConfirmationDiagnosticsMessage)\s*=\s*"
        r'(?P<literal>""".*?"""|"(?:\\.|[^"\\])*"|\[\s*"(?:\\.|[^"\\])*\")',
        re.DOTALL,
    )
    for match in state_pattern.finditer(source):
        line = source.count("\n", 0, match.start()) + 1
        violations.append((line, match.group("name")))
    return violations


def _swift_concatenated_localized_call_violations(source: str) -> list[tuple[int, str]]:
    api_names = (
        "Text|Button|Label|Toggle|Picker|Menu|Section|GroupBox|TextField|SecureField|Link|"
        "SettingsLink|TableColumn|LabeledContent|DisclosureGroup|ProgressView"
    )
    pattern = re.compile(
        rf"\b(?P<api>{api_names})\s*\(\s*"
        r'"(?:\\.|[^"\\])*"\s*\+',
        re.MULTILINE,
    )
    return [
        (source.count("\n", 0, match.start()) + 1, match.group("api"))
        for match in pattern.finditer(source)
    ]


def _xcstringstool_help(tool: str) -> str:
    result = subprocess.run(
        [tool, "xcstringstool", "extract", "--help"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return ""
    return f"{result.stdout}\n{result.stderr}"


def _xcstringstool_supports_option(help_text: str, option: str) -> bool:
    return (
        re.search(rf"(?m)^\s+{re.escape(option)}(?:\s|$)", help_text) is not None
    )


def _xcstringstool_supports_swiftui(tool: str) -> bool:
    """Return whether the installed xcstringstool exposes the modern SwiftUI flag."""
    return _xcstringstool_supports_option(_xcstringstool_help(tool), "--SwiftUI")


def _xcstringstool_extract_command(
    tool: str,
    output_dir: Path,
    swift_files: list[Path],
    *,
    supports_swiftui: bool,
    supports_modern_localizable_strings: bool = True,
    supports_swiftui_text: bool = False,
    supports_legacy_localizable_strings: bool = False,
) -> list[str]:
    command = [tool, "xcstringstool", "extract"]
    if supports_modern_localizable_strings:
        command.append("--modern-localizable-strings")
    elif supports_legacy_localizable_strings:
        command.append("--legacy-localizable-strings")
    if supports_swiftui:
        command.append("--SwiftUI")
    elif supports_swiftui_text:
        command.append("--SwiftUI-Text")
    command.extend(
        [
            "-s", "L10n.string", "-s", "L10n.format", "-s", "L10n.plural",
            "-s", "L10n.message", "-s", "L10n.pluralMessage", "-s", "L10n.display",
            "-s", "L10n.editableDefault",
            "--output-format", "xcstrings", "--output-directory", str(output_dir),
            *map(str, swift_files),
        ]
    )
    return command


def _check_macos_localization_contract(root: Path, failures: FailureCollector) -> None:
    catalog_path = root / "apps/macos/AreaMatrix/Localizations/Localizable.xcstrings"
    project_path = root / "apps/macos/AreaMatrix.xcodeproj/project.pbxproj"
    source_root = root / "apps/macos/AreaMatrix"
    if not catalog_path.is_file():
        failures.fail("missing macOS String Catalog: apps/macos/AreaMatrix/Localizations/Localizable.xcstrings")
        return

    try:
        catalog = json.loads(_read(catalog_path))
    except (OSError, json.JSONDecodeError) as error:
        failures.fail(f"invalid macOS String Catalog: {error}")
        return

    if catalog.get("sourceLanguage") != "en":
        failures.fail("macOS String Catalog sourceLanguage must be en")
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        failures.fail("macOS String Catalog strings must be an object")
        return

    placeholder_pattern = re.compile(r"%(?:\d+\$)?(?:[-+#0 ]*\d*(?:\.\d+)?)?(?:ll|l|h)?[@a-zA-Z]|%arg")

    def translated_units(localization: object) -> dict[str, str] | None:
        if not isinstance(localization, dict):
            return None
        unit = localization.get("stringUnit")
        if isinstance(unit, dict):
            value = unit.get("value")
            if unit.get("state") == "translated" and isinstance(value, str):
                return {"other": value}
            return None
        plural = localization.get("variations", {}).get("plural")
        if not isinstance(plural, dict) or "other" not in plural:
            return None
        values: dict[str, str] = {}
        for category, variation in plural.items():
            variation_unit = variation.get("stringUnit", {}) if isinstance(variation, dict) else {}
            value = variation_unit.get("value")
            if variation_unit.get("state") != "translated" or not isinstance(value, str):
                return None
            values[category] = value
        return values

    for key, entry in strings.items():
        localizations = entry.get("localizations") if isinstance(entry, dict) else None
        if not isinstance(localizations, dict) or set(localizations) != {"en", "zh-Hans"}:
            failures.fail(f"macOS localization key must have exactly en and zh-Hans: {key!r}")
            continue
        values: dict[str, dict[str, str]] = {}
        for locale in ("en", "zh-Hans"):
            units = translated_units(localizations.get(locale))
            if units is None:
                failures.fail(f"macOS localization key is not translated for {locale}: {key!r}")
                continue
            values[locale] = units
        if len(values) == 2:
            for category, en_value in values["en"].items():
                zh_value = values["zh-Hans"].get(category, values["zh-Hans"].get("other", ""))
                if not _localization_placeholders_match(en_value, zh_value, placeholder_pattern):
                    failures.fail(
                        f"macOS localization placeholders differ between en and zh-Hans: {key!r} ({category})"
                    )

    project_text = _read(project_path) if project_path.is_file() else ""
    for required in ("Localizable.xcstrings in Resources", '"zh-Hans"'):
        if required not in project_text:
            failures.fail(f"macOS project localization contract missing: {required}")
    for forbidden in ("Localizable.strings in Resources", '"zh-Hant"'):
        if forbidden in project_text:
            failures.fail(f"macOS project localization contract contains obsolete value: {forbidden}")

    swift_files = sorted(
        path for path in source_root.rglob("*.swift")
        if "UniFFI" not in path.parts and "Generated" not in path.parts
    )
    forbidden_api_pattern = re.compile(r"\b(?:String\s*\(\s*localized:|NSLocalizedString\s*\()")
    cjk_literal_pattern = re.compile(r'"(?:\\.|[^"\\])*[\u3400-\u9fff](?:\\.|[^"\\])*"')
    auto_localized_call_pattern = re.compile(
        r"\b(?:Text|Button|Label|Toggle|Picker|Menu|Section|GroupBox|TextField|SecureField|Link|"
        r"SettingsLink|TableColumn|LabeledContent|DisclosureGroup|ProgressView)\s*\(|\.alert\s*\(|\.help\s*\("
    )
    for path in swift_files:
        source = _read(path)
        relative_path = path.relative_to(root)
        is_localization_runtime = relative_path in {
            Path("apps/macos/AreaMatrix/App/AppLanguage.swift"),
            Path("apps/macos/AreaMatrix/App/AppLocalizationText.swift"),
        }
        if forbidden_api_pattern.search(source):
            failures.fail(f"macOS source bypasses AppLocalizer: {relative_path}")
        if not is_localization_runtime:
            bypass_patterns = (
                (r"\bAppLanguageRuntime\.shared\.localizedString\s*\(", "AppLanguageRuntime lookup"),
                (r"\.localizedString\s*\(\s*forKey\s*:", "Bundle localization lookup"),
                (r"\bLocalizedMessage\s*\(", "direct LocalizedMessage construction"),
                (r"\bText\s*\(\s*verbatim\s*:", "direct Text(verbatim:)"),
                (r"(?<!L10n)\.verbatim\s*\(", "unreasoned verbatim construction"),
            )
            for pattern, label in bypass_patterns:
                if re.search(pattern, source):
                    failures.fail(f"macOS source bypasses the localization contract ({label}): {relative_path}")
        if re.search(r"\.id\s*\([^\n)]*(?:locale|language|Language)", source):
            failures.fail(f"macOS source rebuilds view identity for a language change: {relative_path}")
        for line, argument_name in _swift_raw_display_string_violations(source):
            failures.fail(
                "macOS source passes a raw string to a custom display argument; use L10n: "
                f"{relative_path}:{line} ({argument_name})"
            )
        for line in _swift_raw_localized_error_violations(source):
            failures.fail(
                "macOS LocalizedError.errorDescription contains a raw display string; use L10n: "
                f"{relative_path}:{line}"
            )
        for line, display_name in _swift_unlocalized_dynamic_display_violations(source):
            failures.fail(
                "macOS dynamic display state bypasses localization; use L10n at the display boundary: "
                f"{relative_path}:{line} ({display_name})"
            )
        for line, api_name in _swift_concatenated_localized_call_violations(source):
            failures.fail(
                "macOS compiler-localized SwiftUI text must not concatenate string literals; use a static L10n key: "
                f"{relative_path}:{line} ({api_name})"
            )
        for line, function_name, key in _swift_l10n_calls(source):
            if key is None:
                failures.fail(
                    "macOS L10n key must be a static string literal: "
                    f"{relative_path}:{line} (L10n.{function_name})"
                )
                continue
            if key not in strings:
                failures.fail(
                    "macOS explicit L10n key is missing from Localizable.xcstrings: "
                    f"{key!r} ({relative_path})"
                )
        lines = source.splitlines()
        for index, line in enumerate(lines):
            if not cjk_literal_pattern.search(line) or "L10n." in line:
                continue
            context = "\n".join(lines[max(0, index - 4):index + 1])
            if auto_localized_call_pattern.search(context):
                continue
            failures.fail(
                "macOS source contains a CJK string outside L10n or a compiler-localized SwiftUI API: "
                f"{relative_path}:{index + 1}"
            )

    forbidden_core_locale_tokens = ("set_app_interface_locale", "setAppInterfaceLocale")
    core_contract_paths = [root / "core/area_matrix.udl", *(root / "core/src").rglob("*.rs")]
    for path in core_contract_paths:
        if not path.is_file():
            continue
        source = _read(path)
        for token in forbidden_core_locale_tokens:
            if token in source:
                failures.fail(
                    "Core contains forbidden process-global interface locale state: "
                    f"{path.relative_to(root)} ({token})"
                )

    tool = shutil.which("xcrun")
    if tool is None:
        failures.fail("xcrun is required to validate the macOS localization extraction contract")
        return
    with tempfile.TemporaryDirectory(prefix="areamatrix-l10n-") as output_dir:
        tool_help = _xcstringstool_help(tool)
        supports_modern = _xcstringstool_supports_option(tool_help, "--modern-localizable-strings")
        supports_swiftui = _xcstringstool_supports_option(tool_help, "--SwiftUI")
        supports_swiftui_text = _xcstringstool_supports_option(tool_help, "--SwiftUI-Text")
        supports_legacy = _xcstringstool_supports_option(tool_help, "--legacy-localizable-strings")
        command = _xcstringstool_extract_command(
            tool,
            Path(output_dir),
            swift_files,
            supports_swiftui=supports_swiftui,
            supports_modern_localizable_strings=supports_modern,
            supports_swiftui_text=supports_swiftui_text,
            supports_legacy_localizable_strings=supports_legacy,
        )
        strict_extraction = supports_modern
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        extracted_path = Path(output_dir) / "Localizable.xcstrings"
        if result.returncode != 0 or not extracted_path.is_file():
            detail = result.stderr.strip() or result.stdout.strip() or "no catalog was produced"
            if strict_extraction:
                failures.fail(f"macOS localization extraction failed: {detail}")
            return
        try:
            extracted = json.loads(_read(extracted_path)).get("strings", {})
        except (OSError, json.JSONDecodeError) as error:
            failures.fail(f"invalid extracted macOS localization catalog: {error}")
            return
        if strict_extraction:
            for key in sorted(set(extracted) - set(strings)):
                failures.fail(f"macOS user-visible string is missing from Localizable.xcstrings: {key!r}")


def run_localization_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    failures = FailureCollector()
    _check_macos_localization_contract(root, failures)
    if failures.count:
        print(f"macOS localization contract: FAILED ({failures.count} issue(s))", file=os.sys.stderr)
        return 1
    print("macOS localization contract: OK")
    return 0


def _check_ai_runtime_environment_contract(root: Path, failures: FailureCollector) -> None:
    expected = set(AI_RUNTIME_ENV_CONTRACT)
    core_keys = {
        key
        for path in (root / "core/src").rglob("*.rs")
        if path.is_file()
        for key in re.findall(r'"(AREAMATRIX_[A-Z0-9_]+_RUNTIME)"', _read(path))
    }
    swift_keys = {
        key
        for path in (root / "apps/macos/AreaMatrix").rglob("*.swift")
        if path.is_file()
        for key in re.findall(r'"(AREAMATRIX_[A-Z0-9_]+_RUNTIME)"', _read(path))
    }

    if core_keys != expected:
        failures.fail(
            "AI runtime environment contract drift: "
            f"expected Core keys {sorted(expected)}, found {sorted(core_keys)}"
        )
    unexpected_swift_keys = swift_keys - expected
    if unexpected_swift_keys:
        failures.fail(
            "AI runtime environment contract drift: macOS references unknown keys "
            f"{sorted(unexpected_swift_keys)}"
        )
    installed_keys = {key for key, mode in AI_RUNTIME_ENV_CONTRACT.items() if mode == "installed-by-macos"}
    if not installed_keys.issubset(swift_keys):
        failures.fail(
            "AI runtime environment contract drift: macOS no longer installs declared keys "
            f"{sorted(installed_keys - swift_keys)}"
        )


def _check_enterprise_governance_baseline(root: Path, failures: FailureCollector) -> None:
    from .changes import ChangeYAMLError, parse_yaml_subset

    root = root.resolve()
    baseline_path = root / "docs/governance/enterprise-workflow-baseline.md"
    register_path = root / "docs/governance/governance-register.yaml"
    if not baseline_path.is_file() or not register_path.is_file():
        return

    baseline = _read(baseline_path)
    for gate in range(9):
        if not re.search(rf"\bG{gate}\b", baseline):
            failures.fail(f"enterprise governance baseline is missing G{gate}")
    applicability_rows = re.findall(r"(?m)^\|\s*(?:[1-9]|[12][0-9]|3[0-7])\s+[^|]+\|", baseline)
    if len(applicability_rows) != 37:
        failures.fail(f"enterprise governance applicability matrix must classify 37 domains, found {len(applicability_rows)}")

    try:
        register = parse_yaml_subset(_read(register_path), register_path)
    except ChangeYAMLError as exc:
        failures.fail(f"invalid enterprise governance register: {exc}")
        return
    if not isinstance(register, dict):
        failures.fail("enterprise governance register must be a mapping")
        return

    upstream = register.get("upstream")
    expected_upstream = {
        "spec_id": "ASW-EWF-001",
        "version": "1.0.0",
        "adoption": "adapted-complete",
    }
    if not isinstance(upstream, dict):
        failures.fail("enterprise governance register upstream must be a mapping")
    else:
        for key, value in expected_upstream.items():
            if str(upstream.get(key)) != value:
                failures.fail(f"enterprise governance register upstream.{key} must be {value}")
        source_path = upstream.get("source_path")
        source_hash = upstream.get("sha256")
        if not isinstance(source_path, str) or not source_path:
            failures.fail("enterprise governance register upstream.source_path must be repo-relative")
        else:
            source = Path(source_path)
            if source.is_absolute() or ".." in source.parts:
                failures.fail("enterprise governance register upstream.source_path must stay inside the repository")
            else:
                resolved = (root / source).resolve()
                try:
                    resolved.relative_to(root)
                except ValueError:
                    failures.fail("enterprise governance register upstream.source_path resolves outside the repository")
                else:
                    if not resolved.is_file():
                        failures.fail(f"enterprise governance upstream snapshot does not exist: {source_path}")
                    elif not isinstance(source_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", source_hash):
                        failures.fail("enterprise governance register upstream.sha256 must be a lowercase SHA-256")
                    else:
                        actual_hash = hashlib.sha256(resolved.read_bytes()).hexdigest()
                        if actual_hash != source_hash:
                            failures.fail(
                                "enterprise governance upstream snapshot hash mismatch: "
                                f"expected {source_hash}, found {actual_hash}"
                            )
                        baseline_hashes = re.findall(r"\b[0-9a-f]{64}\b", baseline)
                        if source_hash not in baseline_hashes:
                            failures.fail("enterprise governance baseline must state the upstream snapshot SHA-256")
                        for stated_hash in baseline_hashes:
                            if stated_hash != source_hash:
                                failures.fail(
                                    "enterprise governance baseline states a stale SHA-256: "
                                    f"{stated_hash}"
                                )

    raci = register.get("raci")
    if not isinstance(raci, dict) or raci.get("accountable") != "@AreaSong":
        failures.fail("enterprise governance register must declare @AreaSong accountable")
    else:
        independent = raci.get("independent_review")
        if not isinstance(independent, dict) or independent.get("missing_reviewer_behavior") != "blocked":
            failures.fail("enterprise governance independent review must fail closed")

    registered_document_paths: set[str] = set()
    documents = register.get("documents")
    if not isinstance(documents, list) or len(documents) < 3:
        failures.fail("enterprise governance register must contain at least three source documents")
    else:
        for entry in documents:
            if not isinstance(entry, dict):
                failures.fail("enterprise governance document entry must be a mapping")
                continue
            for key in ["id", "path", "authority", "owner", "status", "last_verified", "review_cycle", "review_triggers"]:
                if not entry.get(key):
                    failures.fail(f"enterprise governance document entry is missing {key}")
            path = entry.get("path")
            if isinstance(path, str):
                if path in registered_document_paths:
                    failures.fail(f"enterprise governance document is registered twice: {path}")
                registered_document_paths.add(path)
                if not (root / path).is_file():
                    failures.fail(f"enterprise governance document does not exist: {path}")

    docs_root = root / "docs"
    if docs_root.is_dir():
        for md_path in sorted(docs_root.rglob("*.md")):
            if not md_path.is_file():
                continue
            rel = md_path.relative_to(root).as_posix()
            if rel not in registered_document_paths:
                failures.fail(f"docs page is not registered in documents: {rel}")

    threat_model_rel = "docs/security/threat-model.md"
    threat_model_path = root / threat_model_rel
    if not threat_model_path.is_file():
        failures.fail(f"enterprise governance threat model is missing: {threat_model_rel}")
    else:
        threat_model = _read(threat_model_path)
        for anchor in ["信任边界", "威胁主体", "数据分类", "控制映射", "复审触发"]:
            if anchor not in threat_model:
                failures.fail(f"enterprise governance threat model is missing section: {anchor}")
        if threat_model_rel not in registered_document_paths:
            failures.fail("enterprise governance threat model must be registered in documents")

    domains = register.get("document_domains")
    if not isinstance(domains, list) or not domains:
        failures.fail("enterprise governance register document_domains must be non-empty")
    else:
        covered_domains: set[str] = set()
        for entry in domains:
            if not isinstance(entry, dict):
                failures.fail("enterprise governance document domain entry must be a mapping")
                continue
            for key in ["domain", "owner", "status", "review_cycle", "review_triggers"]:
                if not entry.get(key):
                    failures.fail(f"enterprise governance document domain entry is missing {key}")
            domain = entry.get("domain")
            if not isinstance(domain, str) or not domain:
                continue
            if domain in covered_domains:
                failures.fail(f"enterprise governance document domain repeats {domain}")
            covered_domains.add(domain)
            if not (root / domain).is_dir():
                failures.fail(f"enterprise governance document domain does not exist: {domain}")
        docs_root = root / "docs"
        if docs_root.is_dir():
            actual_domains = {
                f"docs/{child.name}" for child in docs_root.iterdir() if child.is_dir()
            }
            for missing_domain in sorted(actual_domains - covered_domains):
                failures.fail(f"enterprise governance document domain is unregistered: {missing_domain}")

    raid = register.get("raid")
    if not isinstance(raid, list) or not raid:
        failures.fail("enterprise governance register RAID must be non-empty")
    else:
        expected_entries = {
            "AM-RISK-001": ("risk", "open"),
            "AM-DEP-001": ("dependency", "blocked-external"),
            "AM-DEP-002": ("dependency", "blocked-external"),
            "AM-DEP-003": ("dependency", "deferred"),
            "AM-DEP-004": ("dependency", "deferred"),
        }
        by_id: dict[str, dict[str, object]] = {}
        for entry in raid:
            if not isinstance(entry, dict):
                failures.fail("enterprise governance RAID entry must be a mapping")
                continue
            entry_id = entry.get("id")
            if not isinstance(entry_id, str) or not entry_id:
                failures.fail("enterprise governance RAID entry is missing id")
                continue
            if entry_id in by_id:
                failures.fail(f"enterprise governance RAID repeats id {entry_id}")
                continue
            by_id[entry_id] = entry

        for entry_id, (expected_type, expected_status) in expected_entries.items():
            entry = by_id.get(entry_id)
            if not isinstance(entry, dict):
                failures.fail(f"enterprise governance RAID is missing {entry_id}")
                continue
            for key in [
                "type",
                "status",
                "severity",
                "probability",
                "impact",
                "impact_scope",
                "owner",
                "summary",
                "mitigation",
                "due",
                "escalation",
                "close_evidence",
            ]:
                if not entry.get(key):
                    failures.fail(f"enterprise governance RAID {entry_id} is missing {key}")
            if entry.get("type") != expected_type or entry.get("status") != expected_status:
                failures.fail(
                    f"enterprise governance RAID {entry_id} must remain "
                    f"{expected_type}/{expected_status}"
                )
            probability = entry.get("probability")
            if probability and probability not in {"low", "medium", "high"}:
                failures.fail(
                    f"enterprise governance RAID {entry_id}.probability "
                    "must be low, medium, or high"
                )
            for key in ["impact", "severity"]:
                value = entry.get(key)
                if value and value not in {"low", "medium", "high", "critical"}:
                    failures.fail(
                        f"enterprise governance RAID {entry_id}.{key} "
                        "must be low, medium, high, or critical"
                    )

    status_path = root / ".areaflow/status.json"
    try:
        status = json.loads(_read(status_path))
    except (OSError, json.JSONDecodeError) as exc:
        failures.fail(f"invalid AreaFlow status projection: {exc}")
        return
    compatibility = status.get("compatibility")
    compatibility = compatibility if isinstance(compatibility, dict) else {}
    if compatibility.get("shim_lifecycle_state") != "authoring_only_shim":
        failures.fail("AreaFlow shim lifecycle state must be authoring_only_shim")
    blocked_values = compatibility.get("blocked_commands")
    blocked = set(blocked_values) if isinstance(blocked_values, list) else set()
    required_blocked = {"./task-loop run", "promotion apply", "write execution"}
    if not required_blocked.issubset(blocked):
        failures.fail(f"AreaFlow status projection is missing blocked commands: {sorted(required_blocked - blocked)}")

    execution_root = root / "workflow/versions/v2/execution"
    execution_files = sorted(path.relative_to(execution_root) for path in execution_root.rglob("*") if path.is_file())
    if execution_files != [Path("README.md")]:
        failures.fail(f"v2 execution must remain README-only, found {[str(path) for path in execution_files]}")
    _require_text(root, failures, "workflow/versions/v2/promotion/promotion.yaml", r"live_mapping:\s+pending", "v2 pending live mapping")
    _require_text(root, failures, "workflow/versions/v2/promotion/approval.yaml", r"approved:\s+false", "v2 promotion approval block")


def _udl_namespace_functions(udl_text: str) -> list[str] | None:
    """Extract function names declared inside the leading namespace block."""

    if not udl_text.startswith("namespace area_matrix {"):
        return None
    end = udl_text.find("\n};")
    if end < 0:
        return None
    names: list[str] = []
    for line in udl_text[:end].splitlines():
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("["):
            continue
        match = re.match(
            r"^(?:[A-Za-z0-9_?<> ]+\s)?([a-z][a-z0-9_]*)\(",
            stripped.replace(" (", "("),
        )
        if match:
            names.append(match.group(1))
    return names


def _check_core_api_contract_sync(root: Path, failures: FailureCollector) -> None:
    """core-api.md embedded UDL and function inventory must match the real UDL."""

    api_path = root / "docs/api/core-api.md"
    udl_path = root / "core/area_matrix.udl"
    if not api_path.is_file() or not udl_path.is_file():
        return
    api_text = _read(api_path)
    udl_text = _read(udl_path)

    match = re.search(r"(?ms)^```idl\n(.*?)^```$", api_text)
    if match is None:
        failures.fail("core-api.md must embed the full UDL in an idl code block")
    elif match.group(1).rstrip("\n") != udl_text.rstrip("\n"):
        failures.fail("core-api.md embedded UDL differs from core/area_matrix.udl")

    udl_names = _udl_namespace_functions(udl_text)
    if udl_names is None:
        failures.fail("core/area_matrix.udl namespace block could not be parsed")
        return
    udl_set = set(udl_names)
    if len(udl_names) != len(udl_set):
        failures.fail("core/area_matrix.udl namespace declares duplicate function names")

    table_names = set(re.findall(r"(?m)^\|\s*`([a-z][a-z0-9_]*)\(", api_text))
    heading_names = set(re.findall(r"(?m)^###\s+`([a-z][a-z0-9_]*)\(", api_text))
    for name in sorted(udl_set - table_names):
        failures.fail(f"core-api.md function overview table is missing UDL function: {name}")
    for name in sorted(table_names - udl_set):
        failures.fail(f"core-api.md function overview table lists unknown function: {name}")
    for name in sorted(udl_set - heading_names):
        failures.fail(f"core-api.md has no contract section for UDL function: {name}")
    for name in sorted(heading_names - udl_set):
        failures.fail(f"core-api.md documents a function missing from the UDL: {name}")


def _check_data_model_schema_sync(root: Path, failures: FailureCollector) -> None:
    """Every table created in core/src must be documented in data-model.md and vice versa."""

    doc_path = root / "docs/architecture/data-model.md"
    src_root = root / "core/src"
    if not doc_path.is_file() or not src_root.is_dir():
        return
    doc_tables = set(re.findall(r"(?m)^\|\s*`([a-z][a-z0-9_]*)`\s*\|", _read(doc_path)))
    created_tables: set[str] = set()
    for rust_path in sorted(src_root.rglob("*.rs")):
        created_tables.update(
            re.findall(r"CREATE TABLE (?:IF NOT EXISTS )?([a-z][a-z0-9_]*)", _read(rust_path))
        )
    if not created_tables:
        failures.fail("no CREATE TABLE statements found under core/src")
        return
    for table in sorted(created_tables - doc_tables):
        failures.fail(f"data-model.md is missing a table created in core/src: {table}")
    for table in sorted(doc_tables - created_tables):
        failures.fail(f"data-model.md documents a table never created in core/src: {table}")


_REPO_DOMAIN_AUTHORITIES = {
    "source-fact",
    "contract",
    "code",
    "test",
    "generated-verified",
    "build-config",
    "adapter",
    "assets",
    "task-records",
    "archived-readonly",
    "meta",
}


def _check_repo_domain_coverage(root: Path, failures: FailureCollector) -> None:
    """Every tracked or prospective tracked file must resolve to one repo domain."""

    from .changes import ChangeYAMLError, parse_yaml_subset

    root = root.resolve()
    register_path = root / "docs/governance/governance-register.yaml"
    if not register_path.is_file():
        return
    try:
        register = parse_yaml_subset(_read(register_path), register_path)
    except ChangeYAMLError:
        # The enterprise baseline check already reports the parse failure.
        return
    if not isinstance(register, dict):
        return

    domains = register.get("repo_domains")
    if not isinstance(domains, list) or not domains:
        failures.fail("enterprise governance register repo_domains must be non-empty")
        return

    patterns: dict[str, str] = {}
    seen_domains: set[str] = set()
    for entry in domains:
        if not isinstance(entry, dict):
            failures.fail("repo domain entry must be a mapping")
            continue
        for key in ["domain", "owner", "status", "authority", "verification", "review_triggers", "paths"]:
            if not entry.get(key):
                failures.fail(f"repo domain entry is missing {key}")
        domain = entry.get("domain")
        if not isinstance(domain, str) or not domain:
            continue
        if domain in seen_domains:
            failures.fail(f"repo domain repeats {domain}")
            continue
        seen_domains.add(domain)
        authority = entry.get("authority")
        if authority and authority not in _REPO_DOMAIN_AUTHORITIES:
            failures.fail(f"repo domain {domain} has unknown authority: {authority}")
        paths = entry.get("paths")
        if not isinstance(paths, list):
            continue
        for pattern in paths:
            if not isinstance(pattern, str) or not pattern:
                failures.fail(f"repo domain {domain} has an empty path pattern")
                continue
            if pattern.startswith("/") or ".." in Path(pattern).parts:
                failures.fail(f"repo domain {domain} path must stay inside the repository: {pattern}")
                continue
            if pattern in patterns:
                failures.fail(f"repo domain path is registered twice: {pattern}")
                continue
            patterns[pattern] = domain

    inventory = _git_text(
        root,
        "-c",
        "core.quotepath=off",
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
    )
    if inventory is None:
        # Outside a git checkout only the schema above can be validated.
        return
    repository_files = sorted({line for line in inventory.splitlines() if line})
    winning_patterns: set[str] = set()
    unowned: list[str] = []
    for rel_path in repository_files:
        best: str | None = None
        for pattern in patterns:
            if pattern.endswith("/"):
                if not rel_path.startswith(pattern):
                    continue
            elif rel_path != pattern:
                continue
            if best is None or len(pattern) > len(best):
                best = pattern
        if best is None:
            unowned.append(rel_path)
        else:
            winning_patterns.add(best)

    for rel_path in unowned[:20]:
        failures.fail(f"repo domain coverage is missing an owner for {rel_path}")
    if len(unowned) > 20:
        failures.fail(f"repo domain coverage is missing owners for {len(unowned) - 20} more file(s)")
    for pattern in sorted(set(patterns) - winning_patterns):
        failures.fail(f"repo domain path matches no repository file: {pattern}")


def _registered_families(entries: list, key: str, failures: FailureCollector, label: str) -> list[str]:
    families: list[str] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        value = entry.get(key)
        if isinstance(value, str) and value:
            families.append(value)
        elif isinstance(value, list):
            families.extend(item for item in value if isinstance(item, str) and item)
    duplicates = {family for family in families if families.count(family) > 1}
    for family in sorted(duplicates):
        failures.fail(f"{label} registers test family twice: {family}")
    return families


def _check_code_correspondence(root: Path, failures: FailureCollector) -> None:
    """core/src modules and macOS Features must map to registered docs and test families."""

    from .changes import ChangeYAMLError, parse_yaml_subset

    register_path = root / "docs/governance/governance-register.yaml"
    lib_path = root / "core/src/lib.rs"
    if not register_path.is_file() or not lib_path.is_file():
        return
    try:
        register = parse_yaml_subset(_read(register_path), register_path)
    except ChangeYAMLError:
        return
    if not isinstance(register, dict):
        return

    modules_section = register.get("core_modules")
    if not isinstance(modules_section, list) or not modules_section:
        failures.fail("enterprise governance register core_modules must be non-empty")
        return
    features_section = register.get("macos_features")
    if not isinstance(features_section, list) or not features_section:
        failures.fail("enterprise governance register macos_features must be non-empty")
        return
    cross_section = register.get("cross_cutting_test_families")
    if not isinstance(cross_section, list):
        cross_section = []

    lib_modules = set(re.findall(r"(?m)^(?:pub )?mod ([a-z][a-z0-9_]*);", _read(lib_path)))
    registered_modules: set[str] = set()
    for entry in modules_section:
        if not isinstance(entry, dict):
            failures.fail("core module entry must be a mapping")
            continue
        module = entry.get("module")
        if not isinstance(module, str) or not module:
            failures.fail("core module entry is missing module")
            continue
        if module in registered_modules:
            failures.fail(f"core module is registered twice: {module}")
            continue
        registered_modules.add(module)
        if not entry.get("owner"):
            failures.fail(f"core module {module} is missing owner")
        docs = entry.get("authority_docs")
        docs = docs if isinstance(docs, list) else []
        for doc in docs:
            if not isinstance(doc, str) or not (root / doc).is_file():
                failures.fail(f"core module {module} references a missing authority doc: {doc}")
        if not docs and not entry.get("coverage_note"):
            failures.fail(f"core module {module} needs authority_docs or a coverage_note")
    for module in sorted(lib_modules - registered_modules):
        failures.fail(f"core/src module is not registered in core_modules: {module}")
    for module in sorted(registered_modules - lib_modules):
        failures.fail(f"core_modules registers a module missing from core/src/lib.rs: {module}")

    families = _registered_families(modules_section, "test_families", failures, "core_modules")
    families += _registered_families(cross_section, "family", failures, "cross_cutting_test_families")
    tests_dir = root / "core/tests"
    test_stems = sorted(path.stem for path in tests_dir.glob("*.rs")) if tests_dir.is_dir() else []
    if test_stems:
        for family in sorted(set(families)):
            if not any(stem.startswith(family) for stem in test_stems):
                failures.fail(f"registered test family matches no file in core/tests: {family}")
        for stem in test_stems:
            if not any(stem.startswith(family) for family in families):
                failures.fail(f"core/tests file has no registered capability family: {stem}.rs")

    features_dir = root / "apps/macos/AreaMatrix/Features"
    disk_features = (
        {path.name for path in features_dir.iterdir() if path.is_dir()} if features_dir.is_dir() else set()
    )
    registered_features: set[str] = set()
    for entry in features_section:
        if not isinstance(entry, dict):
            failures.fail("macos feature entry must be a mapping")
            continue
        feature = entry.get("feature")
        if not isinstance(feature, str) or not feature:
            failures.fail("macos feature entry is missing feature")
            continue
        if feature in registered_features:
            failures.fail(f"macos feature is registered twice: {feature}")
            continue
        registered_features.add(feature)
        if not entry.get("owner"):
            failures.fail(f"macos feature {feature} is missing owner")
        docs = entry.get("authority_docs")
        if not isinstance(docs, list) or not docs:
            failures.fail(f"macos feature {feature} must register authority_docs")
            continue
        for doc in docs:
            if not isinstance(doc, str) or not (root / doc).is_file():
                failures.fail(f"macos feature {feature} references a missing authority doc: {doc}")
    if disk_features:
        for feature in sorted(disk_features - registered_features):
            failures.fail(f"macOS feature directory is not registered in macos_features: {feature}")
        for feature in sorted(registered_features - disk_features):
            failures.fail(f"macos_features registers a directory missing from Features/: {feature}")


def _python_developer_scenario_ids(source: str) -> list[str]:
    tree = ast.parse(source)
    for node in tree.body:
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        if not any(isinstance(target, ast.Name) and target.id == "DEVELOPER_SCENARIOS" for target in targets):
            continue
        value = node.value
        if not isinstance(value, (ast.List, ast.Tuple)):
            return []
        return [
            item.value
            for item in value.elts
            if isinstance(item, ast.Constant) and isinstance(item.value, str)
        ]
    return []


def _swift_developer_scenario_ids(source: str) -> list[str]:
    declaration = re.search(r"\benum\s+AreaMatrixDeveloperScenario\b[^\{]*\{", source)
    if declaration is None:
        return []
    depth = 1
    end = declaration.end()
    while end < len(source) and depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    if depth:
        return []
    enum_source = source[declaration.end():end - 1]
    pattern = re.compile(
        r'^\s*case\s+(?P<name>[a-z][A-Za-z0-9_]*)(?:\s*=\s*"(?P<raw>[^"]+)")?\s*$',
        re.MULTILINE,
    )
    return [match.group("raw") or match.group("name") for match in pattern.finditer(enum_source)]


def _check_developer_workflow_contract(root: Path, failures: FailureCollector) -> None:
    developer_path = root / "scripts/dev_tools/developer.py"
    scenario_path = root / "apps/macos/AreaMatrix/App/AreaMatrixDeveloperScenario.swift"
    if not developer_path.is_file() or not scenario_path.is_file():
        failures.fail("developer workflow requires Python and Swift scenario inventories")
        return

    python_ids = _python_developer_scenario_ids(_read(developer_path))
    swift_ids = _swift_developer_scenario_ids(_read(scenario_path))
    if not python_ids:
        failures.fail("scripts/dev_tools/developer.py has no DEVELOPER_SCENARIOS inventory")
    if not swift_ids:
        failures.fail("AreaMatrixDeveloperScenario.swift has no scenario cases")
    if python_ids != swift_ids:
        failures.fail(
            "developer scenario inventories differ between Python and Swift: "
            f"python={python_ids}, swift={swift_ids}"
        )

    _require_text(
        root,
        failures,
        "scripts/dev_tools/cli.py",
        r'test_sub\.add_parser\("changed"',
        "changed-path test entry",
    )
    _require_text(
        root,
        failures,
        "scripts/dev_tools/cli.py",
        r'run_sub\.add_parser\("macos"',
        "macOS developer scenario entry",
    )
    _require_text(
        root,
        failures,
        "scripts/dev_tools/cli.py",
        r'doctor_sub\.add_parser\("build"',
        "build doctor entry",
    )
    _require_text(root, failures, "docs/development/build.md", r"\./dev doctor build", "build doctor docs")
    _require_text(root, failures, "docs/development/testing.md", r"\./dev test changed", "changed-path test docs")
    for scenario_id in python_ids:
        _require_text(
            root,
            failures,
            "docs/development/build.md",
            rf"\./dev run macos --scenario {re.escape(scenario_id)}",
            f"developer scenario docs for {scenario_id}",
        )


def _check_ios_core_sdk_package_contract(root: Path, failures: FailureCollector) -> None:
    package_path = root / "apps/ios/Package.swift"
    if not package_path.is_file():
        failures.fail("iOS package must exist for the CoreSDK consumer contract")
        return
    source = _read(package_path)
    if '.package(path: ".core-sdk")' not in source:
        failures.fail("apps/ios/Package.swift must consume the generated .core-sdk package")
    if '.product(name: "AreaMatrixCoreSDK", package: ".core-sdk")' not in source:
        failures.fail("apps/ios/Package.swift must depend on the AreaMatrixCoreSDK product")
    if ".binaryTarget(" in source or 'path: ".core-sdk/AreaMatrixCoreFFI.xcframework"' in source:
        failures.fail(
            "apps/ios/Package.swift must not redeclare the CoreSDK binary target; "
            "the generated package owns Carea_matrixFFI"
        )


def run_governance_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    failures = FailureCollector()
    required_files = [
        "CODE_REVIEW.md",
        "SECURITY.md",
        "CONTRIBUTING.md",
        ".cargo/config.toml",
        ".github/CODEOWNERS",
        ".github/PULL_REQUEST_TEMPLATE.md",
        ".github/ISSUE_TEMPLATE/bug_report.md",
        ".github/ISSUE_TEMPLATE/feature_request.md",
        ".github/workflows/core-ci.yml",
        ".github/workflows/macos-ci.yml",
        ".github/workflows/governance-ci.yml",
        "docs/development/coding-standards.md",
        "docs/development/testing.md",
        "docs/development/git-workflow.md",
        "docs/development/dependency-policy.md",
        "docs/development/ci-governance.md",
        "docs/governance/enterprise-workflow-baseline.md",
        "docs/governance/project-charter.md",
        "docs/governance/governance-register.yaml",
        "docs/governance/operations-lifecycle.md",
        "docs/security/threat-model.md",
        "workflow/versions/v2/discussion/decisions.yaml",
        "workflow/versions/v2/promotion/promotion.yaml",
        "workflow/versions/v2/promotion/approval.yaml",
        "workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md",
    ]
    for rel_path in required_files:
        _check_file(root, failures, rel_path)

    _check_macos_governance_test_membership(root, failures)
    _check_macos_test_plans(root, failures)
    _check_macos_localization_contract(root, failures)
    _check_ai_runtime_environment_contract(root, failures)
    _check_feature_evolution_evidence(root, failures)
    _check_enterprise_governance_baseline(root, failures)
    _check_repo_domain_coverage(root, failures)
    _check_code_correspondence(root, failures)
    _check_developer_workflow_contract(root, failures)
    _check_ios_core_sdk_package_contract(root, failures)
    _check_core_api_contract_sync(root, failures)
    _check_data_model_schema_sync(root, failures)

    _require_text(root, failures, "SECURITY.md", "GitHub Security Advisory", "private security advisory reporting")
    _forbid_text(root, failures, "SECURITY.md", "security@<your-domain>", "placeholder security email")
    _require_text(root, failures, ".github/CODEOWNERS", "@AreaSong", "AreaSong repository owner")
    placeholder_owner_pattern = "|".join((r"<your" r"-org>", r"@" r"AreaMatrix/[A-Za-z0-9_.-]+"))
    _forbid_text(root, failures, ".github/CODEOWNERS", placeholder_owner_pattern, "placeholder owner")
    _require_text(root, failures, ".github/PULL_REQUEST_TEMPLATE.md", "安全与风险|Security and Risk", "security and risk section")
    _require_text(
        root,
        failures,
        ".github/PULL_REQUEST_TEMPLATE.md",
        "依赖 / 许可证 / 供应链",
        "dependency/license/supply-chain section",
    )
    _require_text(root, failures, ".github/PULL_REQUEST_TEMPLATE.md", "Task-loop Evidence", "task-loop evidence section")
    _require_text(
        root,
        failures,
        ".github/PULL_REQUEST_TEMPLATE.md",
        "架构归属|Architecture Ownership",
        "architecture ownership section",
    )
    _require_text(
        root,
        failures,
        ".github/PULL_REQUEST_TEMPLATE.md",
        "Primary feature owner",
        "primary feature owner evidence",
    )
    _require_text(
        root,
        failures,
        ".github/PULL_REQUEST_TEMPLATE.md",
        "Cross-feature / shared paths and why",
        "cross-feature change justification",
    )
    _require_text(
        root,
        failures,
        ".github/PULL_REQUEST_TEMPLATE.md",
        r"Reuse evidence \(existing callers / new callers\)",
        "reuse caller evidence",
    )
    _require_text(root, failures, ".github/PULL_REQUEST_TEMPLATE.md", "CODEOWNERS", "CODEOWNERS checklist")
    _require_text(root, failures, ".github/PULL_REQUEST_TEMPLATE.md", "rollback|回滚", "rollback checklist")
    _require_text(root, failures, ".github/PULL_REQUEST_TEMPLATE.md", "ASW change level", "ASW change level field")
    _require_text(root, failures, ".github/PULL_REQUEST_TEMPLATE.md", "Current gate", "G0-G8 current gate field")
    _require_text(root, failures, ".github/PULL_REQUEST_TEMPLATE.md", "Retirement / deprecation impact", "retirement impact field")
    _require_text(root, failures, ".github/ISSUE_TEMPLATE/bug_report.md", "数据安全影响|Data Safety Impact", "bug data safety section")
    _require_text(root, failures, ".github/ISSUE_TEMPLATE/bug_report.md", "Security Advisory", "private security disclosure reminder")
    _require_text(root, failures, ".github/ISSUE_TEMPLATE/feature_request.md", "本地优先|Local-first", "feature local-first section")
    _require_text(
        root,
        failures,
        ".github/ISSUE_TEMPLATE/feature_request.md",
        "FSEvents|iCloud|staging|reindex",
        "feature filesystem risk prompts",
    )
    _require_text(root, failures, "CONTRIBUTING.md", "CODE_REVIEW.md", "code review entry")
    _require_text(root, failures, "CONTRIBUTING.md", "dependency-policy.md", "dependency policy entry")
    _require_text(root, failures, "CONTRIBUTING.md", "ci-governance.md", "CI governance entry")
    _require_text(
        root,
        failures,
        ".cargo/config.toml",
        r'target-dir\s*=\s*"\.build/cargo/validation"',
        "default local Cargo validation artifact lane",
    )
    _require_text(root, failures, "docs/README.md", "dependency-policy.md", "dependency policy docs navigation")
    _require_text(root, failures, "docs/README.md", "ci-governance.md", "CI governance docs navigation")
    _require_text(root, failures, ".ai-governance/README.md", "CODE_REVIEW.md", "code review governance entry")
    _require_text(root, failures, ".codex/references/index.md", "CODE_REVIEW.md", "code review Codex index entry")
    _require_text(
        root,
        failures,
        "workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md",
        "CODE_REVIEW.md",
        "enterprise review gate",
    )
    _require_text(
        root,
        failures,
        "workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md",
        "dependency-policy.md",
        "dependency gate",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-enterprise-governance/SKILL.md",
        "areamatrix-enterprise-governance",
        "enterprise governance skill",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-validation-driver/SKILL.md",
        "CODE_REVIEW.md",
        "validation driver enterprise references",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-git-checkpoint/SKILL.md",
        "CODE_REVIEW.md",
        "git checkpoint review references",
    )
    _check_workflow_permissions(root, failures)
    _check_workflow_has_no_paths_filter(root, failures, ".github/workflows/core-ci.yml")
    _check_workflow_has_no_paths_filter(root, failures, ".github/workflows/macos-ci.yml")
    for workflow in ("core-ci.yml", "macos-ci.yml", "governance-ci.yml"):
        _require_text(
            root,
            failures,
            f".github/workflows/{workflow}",
            r"^permissions:\n[ \t]+contents:[ \t]+read$",
            f"least-privilege contents permission ({workflow})",
        )
        _require_text(
            root,
            failures,
            f".github/workflows/{workflow}",
            r"(?s)^concurrency:\n[ \t]+group:[ \t]+areamatrix-\$\{\{ github\.workflow \}\}-\$\{\{ github\.ref \}\}\n[ \t]+cancel-in-progress:[ \t]+true",
            f"concurrency cancellation ({workflow})",
        )
    _require_text(
        root,
        failures,
        ".github/workflows/governance-ci.yml",
        r"(?s)^  governance:\n.*?^    permissions:\n\s+contents:\s+read\n\s+security-events:\s+write",
        "gitleaks security-events permission is scoped to the governance job",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"\./dev bindings verify",
        "tracked Swift bindings drift gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"\./dev build core-sdk",
        "reusable CoreSDK build gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"actions/upload-artifact@v4",
        "CoreSDK artifact upload gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"actions/download-artifact@v4",
        "CoreSDK artifact reuse gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"tar -czf core-sdk\.tar\.gz -C \.build core-sdk",
        "CoreSDK artifact archive gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"tar -xzf \.build/artifacts/core-sdk\.tar\.gz -C \.build",
        "CoreSDK artifact restore gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"\./dev build core-sdk --verify-only",
        "CoreSDK restored artifact integrity gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"(?s)^  ios-package:\n",
        "iOS CoreSDK consumer job",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"run: test -f apps/ios/Package\.swift$",
        "required iOS package gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"ln -s \.\./\.\./\.build/core-sdk/current apps/ios/\.core-sdk",
        "iOS CoreSDK pointer consumer setup",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"swift build --package-path apps/ios",
        "iOS Swift package build gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"swift test --package-path apps/ios",
        "iOS Swift package test gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"(?s)^  build:\n(?:(?!^  [A-Za-z0-9_-]+:).)*?^      - uses: dtolnay/rust-toolchain@stable$",
        "Xcode job Rust toolchain for source-bound CoreSDK verification",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r'AREAMATRIX_CORE_SDK_VERIFY_ONLY:\s*"1"',
        "Xcode restored CoreSDK verify-only mode",
    )
    _require_text(
        root,
        failures,
        "apps/macos/AreaMatrix.xcodeproj/project.pbxproj",
        r"AREAMATRIX_CORE_SDK_VERIFY_ONLY",
        "Xcode CoreSDK verify-only Build Phase branch",
    )
    _require_text(
        root,
        failures,
        "apps/macos/AreaMatrix.xcodeproj/project.pbxproj",
        r"alwaysOutOfDate = 0;",
        "Xcode CoreSDK Build Phase incremental execution",
    )
    _require_text(
        root,
        failures,
        "apps/macos/AreaMatrix.xcodeproj/project.pbxproj",
        r"basedOnDependencyAnalysis = 1;",
        "Xcode CoreSDK Build Phase dependency analysis",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"run: test -d apps/macos/AreaMatrix\.xcodeproj$",
        "required macOS project gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"run: test -d apps/macos/AreaMatrix$",
        "required macOS source gate",
    )
    _require_text(root, failures, ".github/workflows/macos-ci.yml", r"\./dev test macos", "macOS test gate")
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"\./dev test macos --build-for-testing",
        "single macOS build-for-testing gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"\./dev test macos --test-without-building",
        "reusable macOS test-without-building gate",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"\./dev test macos --build-for-testing[\s\S]*?--enable-code-coverage",
        "coverage instrumentation during macOS build-for-testing",
    )
    _require_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"--test-plan AreaMatrix-(?:Unit|Feature|Integration|Functional)",
        "layered macOS XCTest plans",
    )
    _require_text(root, failures, ".github/workflows/macos-ci.yml", r"--coverage-gate", "Swift coverage gate")
    _require_text(root, failures, ".github/workflows/macos-ci.yml", r"swiftlint lint --strict", "SwiftLint gate")
    _require_text(root, failures, ".github/workflows/macos-ci.yml", r"swiftformat --lint", "SwiftFormat gate")
    _require_text(
        root,
        failures,
        "apps/macos/AreaMatrix.xcodeproj/xcshareddata/xcschemes/AreaMatrix.xcscheme",
        r"AreaMatrix-Functional\.xctestplan",
        "shared macOS functional XCTestPlan",
    )
    _require_text(
        root,
        failures,
        "apps/macos/AreaMatrix-Functional.xctestplan",
        r'"name"\s*:\s*"AreaMatrixTests"',
        "functional XCTestPlan target",
    )
    for plan_name in ("Unit", "Feature", "Integration", "Performance", "Release"):
        _require_text(
            root,
            failures,
            "apps/macos/AreaMatrix.xcodeproj/xcshareddata/xcschemes/AreaMatrix.xcscheme",
            rf"AreaMatrix-{plan_name}\.xctestplan",
            f"shared macOS {plan_name.lower()} XCTestPlan",
        )
    _forbid_text(
        root,
        failures,
        ".github/workflows/macos-ci.yml",
        r"macos_(?:project|sources)\.outputs\.present|skipping (?:app|SwiftLint|SwiftFormat)",
        "conditional macOS project/source skip guard",
    )
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check governance", "governance check")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check docs", "documentation integrity")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check skills", "skill health")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check quality", "quality smoke")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check codex-os", "Codex OS health")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check wording", "wording audit")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check task-loop", "task-loop health")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check prompts", "prompt doctor")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check diff", "diff whitespace check")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"gitleaks/gitleaks-action", "secret scan action")
    _require_text(root, failures, "scripts/check-secrets.sh", r"AREAMATRIX_GITLEAKS_MODE", "local secret scan diff/history modes")
    _require_text(root, failures, "docs/development/ci-governance.md", "./dev check secrets", "local secret scan docs")
    _require_text(root, failures, "docs/development/ci-governance.md", "./dev check codex-os", "Codex OS local check docs")
    _require_text(root, failures, "docs/development/ci-governance.md", "./dev check docs", "documentation integrity docs")
    _require_text(
        root,
        failures,
        "docs/development/ci-governance.md",
        r"\./dev bindings verify",
        "local tracked bindings drift docs",
    )

    if failures.count:
        print(f"governance health: FAILED ({failures.count} issue(s))", file=os.sys.stderr)
        return 1
    print("governance health: OK")
    return 0


def run_secrets_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    script = root / "scripts" / "check-secrets.sh"
    if not script.is_file():
        print(f"secrets check: FAILED (missing {script})", file=os.sys.stderr)
        return 1
    proc = run_step(["bash", str(script)], cwd=root, check=False)
    if proc.returncode != 0:
        print("secrets check: FAILED", file=os.sys.stderr)
        return proc.returncode
    if "SKIP" in (proc.stderr or ""):
        print("secrets check: SKIP (gitleaks not installed locally)")
    else:
        print("secrets check: PASS")
    return 0


def _check_skill_file(failures: FailureCollector, path: Path) -> None:
    if not path.is_file():
        failures.fail(f"missing file: {path}")


def _check_skill_dir(failures: FailureCollector, path: Path) -> None:
    if not path.is_dir():
        failures.fail(f"missing directory: {path}")


SKILL_MD_MAX_LINES = 100


def _check_skill_markdown_links(root: Path, failures: FailureCollector, source: Path) -> None:
    for target in _markdown_link_targets(_read(source)):
        resolved = _local_markdown_target(root, source, target)
        if resolved is None:
            continue
        try:
            resolved.relative_to(root)
        except ValueError:
            failures.fail(f"{source.relative_to(root)} links outside repository: {target}")
            continue
        if not resolved.exists():
            failures.fail(f"{source.relative_to(root)} has broken link: {target}")


def _check_skill_routing_table(root: Path, failures: FailureCollector, names: list[str]) -> None:
    agents_file = root / "AGENTS.md"
    if not agents_file.is_file():
        failures.fail("missing file: AGENTS.md (skill routing table)")
        return
    text = _read(agents_file)
    for name in names:
        if name not in text:
            failures.fail(f"AGENTS.md skill routing table is missing {name}")


def run_skills_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    skill_root = root / ".codex/skills-src"
    discovery_root = root / ".agents/skills"
    failures = FailureCollector()
    _check_skill_dir(failures, skill_root)
    _check_skill_dir(failures, discovery_root)

    found = 0
    names: list[str] = []
    for skill_dir in sorted(skill_root.glob("areamatrix-*")) if skill_root.is_dir() else []:
        if not skill_dir.is_dir():
            continue
        found += 1
        name = skill_dir.name
        names.append(name)
        skill_file = skill_dir / "SKILL.md"
        openai_file = skill_dir / "agents/openai.yaml"
        references_dir = skill_dir / "references"

        _check_skill_file(failures, skill_file)
        _check_skill_file(failures, openai_file)
        _check_skill_dir(failures, references_dir)
        if references_dir.is_dir() and not any(references_dir.glob("*.md")):
            failures.fail(f"no reference markdown files for {name}")

        link = discovery_root / name
        expected = f"../../.codex/skills-src/{name}"
        if not link.is_symlink():
            failures.fail(f"missing symlink: {link}")
        else:
            actual = str(link.readlink())
            if actual != expected:
                failures.fail(f"bad symlink target for {link}: expected {expected} got {actual}")
            if not link.exists():
                failures.fail(f"broken symlink: {link}")

        if skill_file.is_file():
            try:
                data = parse_frontmatter(skill_file)
                if data.get("name") != name:
                    failures.fail(f"frontmatter name mismatch in {skill_file}: {data.get('name')!r}")
                description = data.get("description")
                if not isinstance(description, str) or not description.strip():
                    failures.fail(f"missing description in {skill_file}")
            except SimpleYAMLError as exc:
                failures.fail(f"invalid SKILL.md: {exc}")
            line_count = len(_read(skill_file).splitlines())
            if line_count > SKILL_MD_MAX_LINES:
                failures.fail(
                    f"{skill_file.relative_to(root)} has {line_count} lines; "
                    f"split content into references/ (max {SKILL_MD_MAX_LINES})"
                )
            _check_skill_markdown_links(root, failures, skill_file)
        if references_dir.is_dir():
            for reference_file in sorted(references_dir.glob("*.md")):
                _check_skill_markdown_links(root, failures, reference_file)

        if openai_file.is_file():
            try:
                data = parse_simple_yaml(openai_file.read_text(encoding="utf-8"), openai_file)
                if not isinstance(data, dict):
                    failures.fail(f"openai.yaml is not a mapping: {openai_file}")
                    continue
                interface = data.get("interface")
                if not isinstance(interface, dict):
                    failures.fail(f"missing interface in {openai_file}")
                    continue
                for key in ["display_name", "short_description", "default_prompt"]:
                    value = interface.get(key)
                    if not isinstance(value, str) or not value.strip():
                        failures.fail(f"missing interface.{key} in {openai_file}")
                default_prompt = interface.get("default_prompt")
                if isinstance(default_prompt, str) and f"${name}" not in default_prompt:
                    failures.fail(f"default_prompt must mention ${name} in {openai_file}")
                policy = data.get("policy")
                if not isinstance(policy, dict):
                    failures.fail(f"missing policy in {openai_file}")
                elif not isinstance(policy.get("allow_implicit_invocation"), bool):
                    failures.fail(f"policy.allow_implicit_invocation must be boolean in {openai_file}")
            except SimpleYAMLError as exc:
                failures.fail(f"invalid openai.yaml: {exc}")

    if found == 0:
        failures.fail(f"no AreaMatrix skills found under {skill_root}")
    else:
        _check_skill_routing_table(root, failures, names)

    if failures.count:
        print(f"skill health: FAILED ({failures.count} issue(s))", file=os.sys.stderr)
        return 1
    print(f"skill health: OK ({found} skill(s))")
    return 0


def run_quality_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    failures = FailureCollector()

    quality_files = [
        "docs/development/coding-standards.md",
        "CODE_REVIEW.md",
        "workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md",
        "scripts/dev_tools/swiftlint.yml",
        "scripts/dev_tools/swiftformat.conf",
        "core/AGENTS.md",
        "apps/macos/AGENTS.md",
        "docs/architecture/data-model.md",
        "docs/architecture/migration.md",
        "docs/development/release.md",
        "scripts/dev_tools/release.py",
        "scripts/dev_tools/release_status.py",
        ".codex/skills-src/README.md",
        ".codex/references/index.md",
        ".codex/references/codex-workflow-and-tools.md",
        "tasks/backlog/codex-operating-layer-boundary-regression.md",
    ]
    for rel_path in quality_files:
        _check_file(root, failures, rel_path)

    _require_text(root, failures, "docs/development/coding-standards.md", "注释解释 why", "comment policy")
    _require_text(root, failures, "docs/development/coding-standards.md", "单函数 ≤ 50 行", "function length policy")
    _require_text(root, failures, "docs/development/coding-standards.md", "嵌套 ≤ 3 层", "nesting policy")
    _require_text(root, failures, "docs/development/coding-standards.md", r"\./dev check quality", "quality smoke command")
    _require_text(root, failures, "CODE_REVIEW.md", "数据流、控制流、错误流", "control-flow review gate")
    _require_text(root, failures, "CODE_REVIEW.md", "阻断项", "review blockers")
    _require_text(
        root,
        failures,
        "workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md",
        "注释只解释 WHY",
        "prompt quality comment gate",
    )
    _require_text(
        root,
        failures,
        "workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md",
        "mock-only",
        "real implementation gate",
    )
    _require_text(root, failures, "scripts/dev_tools/swiftlint.yml", "function_body_length: 50", "Swift function length")
    _require_text(root, failures, "scripts/dev_tools/swiftlint.yml", "file_length: 500", "Swift file length")
    _require_text(root, failures, "scripts/dev_tools/swiftformat.conf", "--maxwidth 120", "SwiftFormat max width")

    _require_text(root, failures, "core/AGENTS.md", "平台无关", "Core platform boundary")
    _require_text(root, failures, "apps/macos/AGENTS.md", "CoreBridge", "macOS CoreBridge boundary")
    _require_text(root, failures, "apps/macos/AGENTS.md", "SwiftUI 视图只做展示", "SwiftUI view boundary")
    _require_text(root, failures, "docs/architecture/migration.md", "rollback|回滚", "DB migration rollback boundary")
    _require_text(
        root,
        failures,
        "docs/development/release.md",
        "notarization|notary|公证",
        "release notarization boundary",
    )
    _require_text(root, failures, "docs/development/release.md", r"\./dev release status", "release status boundary")
    _require_text(
        root,
        failures,
        "docs/development/release.md",
        r"\./dev release evidence-audit",
        "release evidence audit boundary",
    )
    _require_text(
        root,
        failures,
        "scripts/dev_tools/release_status.py",
        "closes_residual",
        "release status residual gate",
    )
    _require_text(
        root,
        failures,
        "scripts/dev_tools/release_status.py",
        "release_gate",
        "release status release gate",
    )
    _require_text(
        root,
        failures,
        "scripts/dev_tools/release_status.py",
        "residual_evidence_gate",
        "release status residual evidence gate",
    )
    _require_text(
        root,
        failures,
        "scripts/dev_tools/release_status.py",
        "release_evidence_audit",
        "release evidence audit gate",
    )
    _require_text(
        root,
        failures,
        "scripts/dev_tools/release_status.py",
        "any residual is closed",
        "release status read-only proof boundary",
    )

    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-validation-driver/SKILL.md",
        "macOS app",
        "macOS validation owner",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-doc-sync/SKILL.md",
        "Core API.*UDL|UDL.*Core API",
        "Core API / UDL owner",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-file-safety/SKILL.md",
        "DB metadata|migrations",
        "DB and migration safety owner",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-enterprise-governance/SKILL.md",
        "CI workflows",
        "CI governance owner",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-residual-ledger/SKILL.md",
        "release blockers",
        "release blocker owner",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-workflow-planning/SKILL.md",
        "v\\* workflow",
        "workflow planning owner",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-git-checkpoint/SKILL.md",
        "commit / push|checkpoint",
        "Git checkpoint owner",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-codex-os/SKILL.md",
        "Codex Operating System",
        "Codex OS skill owner",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/areamatrix-macos-ui/SKILL.md",
        "L10n|String Catalog",
        "macOS UI localization owner",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/README.md",
        "areamatrix-residual-ledger",
        "8th residual-ledger skill navigation",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/README.md",
        "areamatrix-codex-os",
        "Codex OS skill navigation",
    )
    _require_text(
        root,
        failures,
        ".codex/skills-src/README.md",
        "areamatrix-macos-ui",
        "macOS UI skill navigation",
    )
    _require_text(root, failures, ".codex/references/index.md", "./dev check quality", "quality smoke reference")
    _require_text(root, failures, ".codex/references/index.md", "./dev check wording", "wording audit reference")
    _require_text(root, failures, "docs/development/ci-governance.md", "./dev check quality", "CI quality smoke docs")
    _require_text(root, failures, "docs/development/ci-governance.md", "./dev check wording", "CI wording audit docs")
    _require_text(root, failures, "docs/development/ci-governance.md", "./dev governance status", "governance status dashboard docs")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check quality", "CI quality smoke step")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check wording", "CI wording audit step")

    stale_skill_count_patterns = (
        r"现有 " + r"7 个",
        r"已有 " + r"7 个",
        r"现有 " + r"8 个",
        r"已有 " + r"8 个",
        r"现有 " + r"9 个",
        r"已有 " + r"9 个",
        r"7 个 " + r"AreaMatrix skills",
        r"8 个 " + r"AreaMatrix skills",
        r"9 个 " + r"AreaMatrix skills",
        r"强化现有 " + r"7",
        r"强化现有 " + r"8",
        r"强化现有 " + r"9",
    )
    stale_count_pattern = "|".join(stale_skill_count_patterns)
    for rel_path in [
        ".codex/references/codex-workflow-and-tools.md",
        "tasks/backlog/codex-operating-layer-boundary-regression.md",
        ".codex/skills-src/README.md",
        ".codex/references/index.md",
    ]:
        _forbid_text(root, failures, rel_path, stale_count_pattern, "stale skill count")

    if failures.count:
        print(f"quality smoke: FAILED ({failures.count} issue(s))", file=os.sys.stderr)
        return 1
    print("quality smoke: OK")
    return 0


def run_prompts_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    return run_step(["python3", prompt_pipeline_path(root), "doctor"], cwd=root, check=False).returncode


def run_task_loop_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    task_loop = root / "task-loop"
    return run_step([task_loop if task_loop.exists() else "./task-loop", "check"], cwd=root, check=False).returncode


def run_codex_os_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    checks = [
        ["python3", "-m", "py_compile", *sorted(str(path.relative_to(root)) for path in (root / "scripts/dev_tools").glob("*.py"))],
        [root / "dev", "codex-os", "doctor"],
        [root / "dev", "codex-os", "preflight"],
        [root / "dev", "codex-os", "new", "--help"],
        [root / "dev", "codex-os", "context", "--help"],
        [root / "dev", "codex-os", "resume", "--help"],
        [root / "dev", "codex-os", "recommend-validation", "--help"],
        [root / "dev", "codex-os", "start-flow", "--help"],
        [root / "dev", "codex-os", "flow", "--help"],
        [root / "dev", "codex-os", "go", "--help"],
        [root / "dev", "codex-os", "run-validation", "--help"],
        [root / "dev", "codex-os", "run-validation", "--profile", "auto", "--help"],
        [root / "dev", "codex-os", "run-validation", "--profile", "full", "--help"],
        [root / "dev", "codex-os", "repair-plan", "--help"],
        [root / "dev", "codex-os", "close-flow", "--help"],
        [root / "dev", "codex-os", "close-flow", "--task-id", "AM-CHECK", "--status", "Done", "--from-latest-validation", "--help"],
        [root / "dev", "codex-os", "done", "--help"],
        [root / "dev", "codex-os", "ops-flow", "--help"],
        [root / "dev", "codex-os", "ops-flow", "--compact", "--help"],
        [root / "dev", "codex-os", "ops-flow", "--action-items", "--help"],
        [root / "dev", "codex-os", "todo", "--help"],
        [root / "dev", "codex-os", "now", "--help"],
        [root / "dev", "codex-os", "subagent-plan", "--help"],
        [root / "dev", "codex-os", "archive-review", "--help"],
        [root / "dev", "codex-os", "title-suggestions", "--help"],
        [root / "dev", "codex-os", "weekly", "--help"],
        [root / "dev", "codex-os", "diagnose", "--help"],
        [root / "dev", "codex-os", "health-score", "--help"],
        [root / "dev", "codex-os", "runbook", "--help"],
        [root / "dev", "codex-os", "lifecycle", "--help"],
        [root / "dev", "codex-os", "registry", "status", "--json"],
        [root / "dev", "codex-os", "task", "--help"],
        [root / "dev", "codex-os", "finish", "--help"],
        ["python3", "-m", "unittest", "scripts.dev_tools.test_codex_os"],
    ]
    for argv in checks:
        proc = run_step(argv, cwd=root, check=False)
        if proc.returncode != 0:
            return proc.returncode
    return 0


def _github_event_diff_base() -> str | None:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        return None
    try:
        event = json.loads(Path(event_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    pull_request = event.get("pull_request")
    if isinstance(pull_request, dict):
        base = pull_request.get("base")
        if isinstance(base, dict):
            sha = base.get("sha")
            if isinstance(sha, str) and sha:
                return sha
    before = event.get("before")
    if isinstance(before, str) and before and before != "0" * 40:
        return before
    return None


def _resolve_diff_base(root: Path) -> str | None:
    candidates = [
        os.environ.get("AREAMATRIX_DIFF_BASE"),
        _github_event_diff_base(),
    ]
    github_base_ref = os.environ.get("GITHUB_BASE_REF")
    if github_base_ref:
        candidates.append(f"origin/{github_base_ref}")
    candidates.append(os.environ.get("AREAMATRIX_DIFF_UPSTREAM", "origin/main"))

    for candidate in candidates:
        if not candidate:
            continue
        if _git_text(root, "rev-parse", "--verify", f"{candidate}^{{commit}}") is None:
            continue
        merge_base = _git_text(root, "merge-base", "HEAD", candidate)
        if merge_base:
            return merge_base
    return None


def run_diff_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    for argv in (["git", "diff", "--check"], ["git", "diff", "--cached", "--check"]):
        proc = run_step(argv, cwd=root, check=False)
        if proc.returncode != 0:
            return proc.returncode

    base = _resolve_diff_base(root)
    if base is None:
        print(
            "ERROR: unable to resolve committed diff base; set AREAMATRIX_DIFF_BASE or fetch origin/main.",
            file=os.sys.stderr,
        )
        return 1
    head = _git_text(root, "rev-parse", "HEAD")
    if head == base:
        return 0
    return run_step(["git", "diff", "--check", base], cwd=root, check=False).returncode


def _task_path(root: Path, label: str) -> Path:
    match = re.fullmatch(r"(\d+-\d+)/task-(\d+)", label)
    if not match:
        fail(f"task label must look like '4-1/task-15', got {label!r}.")
    batch, number = match.groups()
    matches = sorted(task_root(root).glob(f"phase-*/{batch}-*/task-{number}-*.md"))
    if not matches:
        fail(f"task prompt not found for {label}.")
    if len(matches) > 1:
        choices = ", ".join(path.relative_to(root).as_posix() for path in matches)
        fail(f"task label {label} matched multiple prompts: {choices}.")
    return matches[0]


def _task_text(root: Path, label: str) -> str:
    return _task_path(root, label).read_text(encoding="utf-8", errors="replace")


def _task_manifest_entry(root: Path, label: str) -> TaskManifestEntry:
    phase = label.split("-", 1)[0]
    path = manifest_root(root) / f"phase-{phase}.md"
    if not path.is_file():
        return TaskManifestEntry("", "Unspecified", (), (), (), (), ())
    text = _read(path)
    match = re.search(rf"(?ms)^## {re.escape(label)}\n(?P<body>.*?)(?=^## |\Z)", text)
    if not match:
        return TaskManifestEntry("", "Unspecified", (), (), (), (), ())
    raw = match.group(0).strip()
    sections = _manifest_sections(match.group("body"))
    return TaskManifestEntry(
        raw=raw,
        risk=_first_section_item(sections, "Risk Level", "Unspecified"),
        exact_docs=tuple(sections.get("Exact Docs", ())),
        existing_code=tuple(sections.get("Existing Code", ())),
        expected_new_paths=tuple(sections.get("Expected New Paths", ())),
        forbidden_touches=tuple(sections.get("Forbidden Touches", ())),
        validation=tuple(sections.get("Validation", ())),
    )


def _manifest_sections(body: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current = ""
    for line in body.splitlines():
        heading = re.match(r"^###\s+(.+?)\s*$", line)
        if heading:
            current = heading.group(1)
            sections.setdefault(current, [])
            continue
        if not current:
            continue
        value = _manifest_list_item(line)
        if value:
            sections[current].append(value)
    return sections


def _manifest_list_item(line: str) -> str:
    match = re.match(r"^\s*-\s+(.*?)\s*$", line)
    if not match:
        return ""
    value = match.group(1).strip()
    if value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def _first_section_item(sections: dict[str, list[str]], key: str, default: str) -> str:
    values = sections.get(key, [])
    return values[0] if values else default


def _task_contains(text: str, pattern: str) -> bool:
    return re.search(pattern, text, flags=re.IGNORECASE) is not None


def _task_capabilities(text: str) -> list[str]:
    lowered = text.lower()
    capabilities = set(re.findall(r"\b[a-z0-9]+(?:-[a-z0-9]+)*-core\b", lowered))
    for capability in V1_LEGACY_CAPABILITY_TEST_TARGETS:
        if capability in lowered:
            capabilities.add(capability)
    for capability, keywords in V1_LEGACY_CAPABILITY_KEYWORDS.items():
        if any(keyword in lowered for keyword in keywords):
            capabilities.add(capability)
    for group, number in re.findall(r"\bC([1-4])-(\d{2})\b", text):
        capability = V1_LEGACY_CAPABILITY_IDS.get((group, number))
        if capability:
            capabilities.add(capability)
    return sorted(capabilities)


def _is_legacy_closeout_task(text: str) -> bool:
    archived_group = "sta" + "ge"
    archived_acceptance = "阶" + "段"
    return _task_contains(
        text,
        rf"{archived_group}[- ]\d+.*integration[- ]verify|{archived_acceptance}.*验收",
    )


def _is_page_task(text: str) -> bool:
    return _task_contains(text, r"\bS(?:[1-3]-\d{2}|4-[A-Z]+-\d{2})\b|page[- ]integration|UX 页面")


def _is_core_task(text: str) -> bool:
    return bool(_task_capabilities(text)) and not _is_page_task(text)


def _is_core_integration_task(text: str) -> bool:
    return bool(_task_capabilities(text)) and _task_contains(
        text,
        r"integration[- ]verify|Core 步骤：能力集成验收",
    )


def _needs_core_quality_gate(text: str, entry: TaskManifestEntry) -> bool:
    if _is_core_integration_task(text):
        return True
    if entry.risk == "Mission-Critical" and _touches_file_safety_boundary(text, entry):
        return True
    if _manifest_requests_core_quality_gate(entry):
        return True
    return False


def _touches_file_safety_boundary(text: str, entry: TaskManifestEntry) -> bool:
    haystack = " ".join(
        [
            text,
            entry.raw,
            " ".join(entry.exact_docs),
            " ".join(entry.existing_code),
            " ".join(entry.expected_new_paths),
            " ".join(entry.forbidden_touches),
        ]
    ).lower()
    return any(keyword in haystack for keyword in FILE_SAFETY_GATE_KEYWORDS)


def _manifest_requests_core_quality_gate(entry: TaskManifestEntry) -> bool:
    validation = "\n".join(entry.validation).lower()
    return "cargo clippy" in validation or "cargo fmt" in validation or "./dev check all" in validation


def _run_common_task_checks(root: Path) -> int:
    for label, func in [
        ("prompt doctor", lambda: run_prompts_check(root)),
        ("diff check", lambda: run_diff_check(root)),
        ("secrets", lambda: run_secrets_check(root)),
    ]:
        print()
        print(f"==> ./dev check task: {label}", flush=True)
        rc = func()
        if rc != 0:
            return rc
    return 0


def _run_core_task_checks(root: Path, text: str, entry: TaskManifestEntry | None = None) -> int:
    core_dir = root / "core"
    require_command("cargo")
    entry = entry or TaskManifestEntry("", "Unspecified", (), (), (), (), ())
    if _needs_core_quality_gate(text, entry):
        print()
        print("==> ./dev check task: widened Core quality gate (fmt + clippy)", flush=True)
        for argv in [
            ["cargo", "fmt", "--all", "--", "--check"],
            ["cargo", "clippy", "--all-targets", "--all-features", "--", "-D", "warnings"],
        ]:
            proc = run_step(argv, cwd=core_dir, check=False)
            if proc.returncode != 0:
                return proc.returncode
    else:
        print()
        print("==> ./dev check task: fast Core gate (targeted tests only)", flush=True)

    commands = _core_task_test_commands(text, root)
    if not commands:
        print()
        if os.environ.get(ALLOW_FULL_TASK_FALLBACK_ENV) == "1":
            print(
                "==> ./dev check task: no targeted Core tests mapped; "
                f"{ALLOW_FULL_TASK_FALLBACK_ENV}=1 so using cargo test --workspace",
                flush=True,
            )
            commands = [["cargo", "test", "--workspace"]]
        else:
            capabilities = ", ".join(_task_capabilities(text)) or "unknown"
            print(
                "ERROR: ./dev check task found no targeted Core tests mapped "
                f"for capabilities: {capabilities}.",
                file=os.sys.stderr,
            )
            print(
                "ERROR: add v1 legacy capability test coverage in scripts/dev_tools/checks.py, "
                "or run ./dev check core/all explicitly when a broad gate is intended.",
                file=os.sys.stderr,
            )
            print(
                f"ERROR: set {ALLOW_FULL_TASK_FALLBACK_ENV}=1 only for an explicit emergency full fallback.",
                file=os.sys.stderr,
            )
            return 2
    for argv in commands:
        proc = run_step(argv, cwd=core_dir, check=False)
        if proc.returncode != 0:
            return proc.returncode
    return 0


def _core_task_test_commands(text: str, root: Path | None = None) -> list[list[str]]:
    commands: list[list[str]] = []
    for capability in _task_capabilities(text):
        for target in _capability_test_targets(capability, root):
            commands.append(["cargo", "test", "--test", target, "--", "--nocapture"])
    return _unique_commands(commands)


def _capability_test_targets(capability: str, root: Path | None) -> tuple[str, ...]:
    targets = list(V1_LEGACY_CAPABILITY_TEST_TARGETS.get(capability, ()))
    if root is not None:
        targets.extend(_discover_capability_test_targets(root, capability))
    return tuple(_unique_strings(targets))


def _discover_capability_test_targets(root: Path, capability: str) -> list[str]:
    tests_dir = root / "core/tests"
    if not tests_dir.is_dir():
        return []
    targets: list[str] = []
    for prefix in _capability_test_prefixes(root, capability):
        for path in sorted(tests_dir.glob(f"{prefix}_*.rs")):
            if path.is_file():
                targets.append(path.stem)
    return _unique_strings(targets)


def _capability_test_prefixes(root: Path, capability: str) -> list[str]:
    prefixes: list[str] = []
    for path in _capability_spec_paths(root, capability):
        slug = path.stem.removeprefix(f"{capability}-")
        prefix = _slug_to_test_prefix(slug)
        if prefix:
            prefixes.append(prefix)
    return _unique_strings(prefixes)


def _capability_spec_paths(root: Path, capability: str) -> list[Path]:
    paths: list[Path] = []
    versions_root = root / "workflow/versions"
    if versions_root.is_dir():
        for version_dir in sorted(path for path in versions_root.iterdir() if path.is_dir()):
            spec_root = version_dir / "source-docs/core/capability-specs"
            paths.extend(sorted(spec_root.glob(f"**/{capability}-*.md")))
    return paths


def _slug_to_test_prefix(slug: str) -> str:
    return re.sub(r"[^a-zA-Z0-9]+", "_", slug).strip("_").lower()


def _unique_commands(commands: list[list[str]]) -> list[list[str]]:
    result: list[list[str]] = []
    seen: set[tuple[str, ...]] = set()
    for command in commands:
        key = tuple(command)
        if key not in seen:
            result.append(command)
            seen.add(key)
    return result


def _unique_strings(values: list[str]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        if value not in seen:
            result.append(value)
            seen.add(value)
    return result


def _run_page_task_checks(root: Path) -> int:
    rc = run_localization_check(root)
    if rc != 0:
        return rc
    proc = run_step(
        [
            "xcodebuild",
            "-project",
            "apps/macos/AreaMatrix.xcodeproj",
            "-scheme",
            "AreaMatrix",
            "-destination",
            "platform=macOS,arch=arm64",
            "build",
            "CODE_SIGNING_ALLOWED=NO",
        ],
        cwd=root,
        check=False,
    )
    return proc.returncode


def run_task_check(label: str, root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    text = _task_text(root, label)
    entry = _task_manifest_entry(root, label)
    rc = _run_common_task_checks(root)
    if rc != 0:
        return rc
    if _is_legacy_closeout_task(text):
        print()
        print(f"==> ./dev check task {label}: v1 legacy closeout uses ./dev check all", flush=True)
        return run_all_check(root)
    if _is_page_task(text):
        return _run_page_task_checks(root)
    if _is_core_task(text):
        return _run_core_task_checks(root, text, entry)
    print()
    print(f"==> ./dev check task {label}: prompt/diff checks only", flush=True)
    return 0


def run_quick_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    rc = run_prompts_check(root)
    if rc != 0:
        return rc
    return run_task_loop_check(root)


def _run_core_checks(root: Path) -> int:
    core_dir = root / "core"
    require_command("cargo")
    if not (core_dir / "Cargo.toml").is_file():
        fail(f"core Cargo manifest not found at {core_dir / 'Cargo.toml'}.")
    for argv in [
        ["cargo", "fmt", "--all", "--", "--check"],
        ["cargo", "clippy", "--all-targets", "--all-features", "--", "-D", "warnings"],
        ["cargo", "test", "--workspace"],
    ]:
        proc = run_step(argv, cwd=core_dir, check=False)
        if proc.returncode != 0:
            return proc.returncode
    return 0


def _swiftformat_lint_args(root: Path) -> list[str | Path]:
    config = root / "scripts/dev_tools/swiftformat.conf"
    require_file(config, "SwiftFormat configuration")
    generated_excludes = "AreaMatrix/Bridge/Generated,AreaMatrix/Bridge/UniFFI,DerivedData"
    return [
        "swiftformat",
        "--lint",
        ".",
        "--config",
        config,
        "--exclude",
        generated_excludes,
        "--cache",
        "ignore",
    ]


def _swiftlint_lint_args(root: Path) -> list[str | Path]:
    config = root / "scripts/dev_tools/swiftlint.yml"
    require_file(config, "SwiftLint configuration")
    return ["swiftlint", "lint", "--strict", "--config", config, "--force-exclude", ".", "--no-cache"]


def _run_swift_checks(root: Path) -> int:
    macos_dir = root / "apps/macos"
    require_command("swiftformat")
    require_command("swiftlint")
    for argv in [_swiftformat_lint_args(root), _swiftlint_lint_args(root)]:
        proc = run_step(argv, cwd=macos_dir, check=False)
        if proc.returncode != 0:
            return proc.returncode
    return 0


def _missing_macos_rust_targets() -> list[str]:
    required_targets = ["aarch64-apple-darwin", "x86_64-apple-darwin"]
    if shutil.which("rustup") is None:
        return []
    proc = subprocess.run(
        ["rustup", "target", "list", "--installed"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        print("ERROR: unable to list installed Rust targets.", file=os.sys.stderr)
        if proc.stderr.strip():
            print(proc.stderr.strip(), file=os.sys.stderr)
        return required_targets
    installed = {line.strip() for line in proc.stdout.splitlines()}
    return [target for target in required_targets if target not in installed]


def _run_macos_prerequisites_check() -> int:
    failures = FailureCollector()
    missing_targets = _missing_macos_rust_targets()
    for target in missing_targets:
        failures.fail(f"missing Rust target '{target}'; install with: rustup target add {target}")

    for tool in ["swiftformat", "swiftlint"]:
        if shutil.which(tool) is None:
            failures.fail(f"missing command '{tool}' in PATH; install it before running macOS checks")

    if failures.count:
        print(
            f"macOS prerequisite check: FAILED ({failures.count} issue(s))",
            file=os.sys.stderr,
        )
        return 1
    print("macOS prerequisite check: OK")
    return 0


def _run_macos_checks(root: Path) -> int:
    macos_dir = root / "apps/macos"
    macos_project = macos_dir / "AreaMatrix.xcodeproj"
    if not macos_dir.is_dir():
        print(f"ERROR: required macOS source directory not found at {macos_dir}.", file=os.sys.stderr)
        return 1
    if not macos_project.is_dir():
        print(f"ERROR: required Xcode project not found at {macos_project}.", file=os.sys.stderr)
        return 1

    rc = _run_macos_prerequisites_check()
    if rc != 0:
        return rc
    out_dir = Path(os.environ.get("AREAMATRIX_CHECK_CORE_OUT_DIR", "/private/tmp/areamatrix-check-all/Bridge/UniFFI"))
    rc = run_core_build(root, out_dir=out_dir)
    if rc != 0:
        return rc
    rc = run_macos_tests(root)
    if rc != 0:
        return rc
    return _run_swift_checks(root)


def run_all_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    steps = [
        ("governance", lambda: run_governance_check(root)),
        ("docs", lambda: run_docs_check(root)),
        ("skills", lambda: run_skills_check(root)),
        ("quality smoke", lambda: run_quality_check(root)),
        ("codex-os", lambda: run_codex_os_check(root)),
        ("wording audit", lambda: run_wording_audit(root)),
        ("task-loop", lambda: run_task_loop_check(root)),
        ("prompt doctor", lambda: run_prompts_check(root)),
        ("diff check", lambda: run_diff_check(root)),
        ("secrets", lambda: run_secrets_check(root)),
        ("core checks", lambda: _run_core_checks(root)),
        ("macOS checks", lambda: _run_macos_checks(root)),
    ]
    for label, func in steps:
        print()
        print(f"==> ./dev check all: {label}", flush=True)
        rc = func()
        if rc != 0:
            return rc
    return 0
