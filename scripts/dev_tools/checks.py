"""Checks behind ./dev check."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
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
    "AREAMATRIX_AI_SUMMARY_LOCAL_RUNTIME": "external",
    "AREAMATRIX_AI_SUMMARY_REMOTE_RUNTIME": "external",
    "AREAMATRIX_AI_TAGS_LOCAL_RUNTIME": "external",
    "AREAMATRIX_AI_TAGS_REMOTE_RUNTIME": "external",
}


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


def run_docs_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    failures = FailureCollector()
    roots = [root / "README.md", root / "README.zh-CN.md", root / "docs/README.md"]
    for path in roots:
        if not path.is_file():
            failures.fail(f"missing documentation entry point: {path.relative_to(root)}")

    markdown_files = sorted(path for path in (root / "docs").rglob("*.md") if path.is_file())
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


def run_governance_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    failures = FailureCollector()
    required_files = [
        "CODE_REVIEW.md",
        "SECURITY.md",
        "CONTRIBUTING.md",
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
        "workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md",
    ]
    for rel_path in required_files:
        _check_file(root, failures, rel_path)

    _check_macos_governance_test_membership(root, failures)
    _check_ai_runtime_environment_contract(root, failures)
    _check_feature_evolution_evidence(root, failures)

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
    _check_workflow_has_no_paths_filter(root, failures, ".github/workflows/core-ci.yml")
    _check_workflow_has_no_paths_filter(root, failures, ".github/workflows/macos-ci.yml")
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
    _require_text(root, failures, ".github/workflows/macos-ci.yml", r"--coverage-gate", "Swift coverage gate")
    _require_text(root, failures, ".github/workflows/macos-ci.yml", r"swiftlint lint --strict", "SwiftLint gate")
    _require_text(root, failures, ".github/workflows/macos-ci.yml", r"swiftformat --lint", "SwiftFormat gate")
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


def run_skills_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    skill_root = root / ".codex/skills-src"
    discovery_root = root / ".agents/skills"
    failures = FailureCollector()
    _check_skill_dir(failures, skill_root)
    _check_skill_dir(failures, discovery_root)

    found = 0
    for skill_dir in sorted(skill_root.glob("areamatrix-*")) if skill_root.is_dir() else []:
        if not skill_dir.is_dir():
            continue
        found += 1
        name = skill_dir.name
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
    _require_text(root, failures, ".codex/references/index.md", "./dev check quality", "quality smoke reference")
    _require_text(root, failures, ".codex/references/index.md", "./dev check wording", "wording audit reference")
    _require_text(root, failures, "docs/development/ci-governance.md", "./dev check quality", "CI quality smoke docs")
    _require_text(root, failures, "docs/development/ci-governance.md", "./dev check wording", "CI wording audit docs")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check quality", "CI quality smoke step")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check wording", "CI wording audit step")

    stale_skill_count_patterns = (
        r"现有 " + r"7 个",
        r"已有 " + r"7 个",
        r"现有 " + r"8 个",
        r"已有 " + r"8 个",
        r"7 个 " + r"AreaMatrix skills",
        r"8 个 " + r"AreaMatrix skills",
        r"强化现有 " + r"7",
        r"强化现有 " + r"8",
    )
    stale_count_pattern = "|".join(stale_skill_count_patterns)
    for rel_path in [
        ".codex/references/codex-workflow-and-tools.md",
        "tasks/backlog/codex-operating-layer-boundary-regression.md",
        ".codex/skills-src/README.md",
        ".codex/references/index.md",
    ]:
        _forbid_text(root, failures, rel_path, stale_count_pattern, "stale 7-skill count")

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


def run_diff_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    return run_step(["git", "diff", "--check"], cwd=root, check=False).returncode


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
