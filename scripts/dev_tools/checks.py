"""Checks behind ./dev check."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .build import run_core_build
from .common import fail, project_root, require_command, require_file, run_step
from .macos import run_macos_tests
from .skills import SimpleYAMLError, parse_frontmatter, parse_simple_yaml


CAPABILITY_TEST_TARGETS = {
    "C2-01": (
        "search_query_files_contract_api",
        "search_query_files_implementation",
        "search_query_files_failure_recovery",
        "search_query_files_validation",
    ),
    "C2-02": (
        "search_filters_contract_api",
        "search_filters_implementation",
        "search_filters_failure_recovery",
        "search_filters_validation",
    ),
    "C2-03": (
        "saved_search_contract_api",
        "saved_search_implementation",
        "saved_search_failure_recovery",
        "saved_search_validation",
    ),
    "C2-04": (
        "smart_list_contract_api",
        "smart_list_implementation",
        "smart_list_failure_recovery",
    ),
}

CAPABILITY_KEYWORDS = {
    "C2-01": ("search query files",),
    "C2-02": ("search filters",),
    "C2-03": ("saved search",),
    "C2-04": ("smart list", "smart-list", "smart-lists"),
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


def _check_workflow_has_no_paths_filter(root: Path, failures: FailureCollector, rel_path: str) -> None:
    _check_file(root, failures, rel_path)
    path = root / rel_path
    if path.is_file() and re.search(r"^[ \t]+paths:", _read(path), flags=re.MULTILINE):
        failures.fail(f"{rel_path} must not use PR/push paths filters; enterprise CI runs on every PR")


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
        "tasks/prompts/_shared/engineering-quality-rules.md",
    ]
    for rel_path in required_files:
        _check_file(root, failures, rel_path)

    _require_text(root, failures, "SECURITY.md", "GitHub Security Advisory", "private security advisory reporting")
    _forbid_text(root, failures, "SECURITY.md", "security@<your-domain>", "placeholder security email")
    _require_text(root, failures, ".github/CODEOWNERS", "@AreaMatrix/maintainers", "AreaMatrix maintainers owner placeholder")
    _require_text(root, failures, ".github/CODEOWNERS", "TODO: Replace @AreaMatrix/maintainers", "replacement note for placeholder owner")
    _require_text(root, failures, ".github/PULL_REQUEST_TEMPLATE.md", "安全与风险|Security and Risk", "security and risk section")
    _require_text(
        root,
        failures,
        ".github/PULL_REQUEST_TEMPLATE.md",
        "依赖 / 许可证 / 供应链",
        "dependency/license/supply-chain section",
    )
    _require_text(root, failures, ".github/PULL_REQUEST_TEMPLATE.md", "Task-loop Evidence", "task-loop evidence section")
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
        "tasks/prompts/_shared/engineering-quality-rules.md",
        "CODE_REVIEW.md",
        "enterprise review gate",
    )
    _require_text(
        root,
        failures,
        "tasks/prompts/_shared/engineering-quality-rules.md",
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
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check governance", "governance check")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check skills", "skill health")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check task-loop", "task-loop health")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check prompts", "prompt doctor")
    _require_text(root, failures, ".github/workflows/governance-ci.yml", r"\./dev check diff", "diff whitespace check")

    if failures.count:
        print(f"governance health: FAILED ({failures.count} issue(s))", file=os.sys.stderr)
        return 1
    print("governance health: OK")
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


def run_prompts_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    return run_step(["python3", "tasks/prompts/_shared/prompt_pipeline.py", "doctor"], cwd=root, check=False).returncode


def run_task_loop_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    task_loop = root / "task-loop"
    return run_step([task_loop if task_loop.exists() else "./task-loop", "check"], cwd=root, check=False).returncode


def run_diff_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    return run_step(["git", "diff", "--check"], cwd=root, check=False).returncode


def _task_path(root: Path, label: str) -> Path:
    match = re.fullmatch(r"(\d+-\d+)/task-(\d+)", label)
    if not match:
        fail(f"task label must look like '4-1/task-15', got {label!r}.")
    batch, number = match.groups()
    matches = sorted((root / "tasks/prompts").glob(f"phase-*/{batch}-*/task-{number}-*.md"))
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
    path = root / "tasks/prompts/_shared/manifests" / f"phase-{phase}.md"
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
    return sorted(set(re.findall(r"\bC[1-4]-\d{2}\b", text)))


def _is_stage_closeout_task(text: str) -> bool:
    return _task_contains(text, r"stage[- ]\d+.*integration[- ]verify|阶段.*验收")


def _is_page_task(text: str) -> bool:
    return _task_contains(text, r"\bS(?:[1-3]-\d{2}|4-[A-Z]+-\d{2})\b|page[- ]integration|UX 页面")


def _is_core_task(text: str) -> bool:
    return bool(_task_capabilities(text)) and not _is_page_task(text)


def _is_core_integration_task(text: str) -> bool:
    return _task_contains(text, r"\bC[1-4]-\d{2}\b.*integration[- ]verify|Core 步骤：能力集成验收")


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
                "ERROR: add CAPABILITY_TEST_TARGETS coverage in scripts/dev_tools/checks.py, "
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
    lowered = text.lower()
    for capability in _task_capabilities(text):
        for target in _capability_test_targets(capability, root):
            commands.append(["cargo", "test", "--test", target, "--", "--nocapture"])
    for capability, keywords in CAPABILITY_KEYWORDS.items():
        if capability not in text and any(keyword in lowered for keyword in keywords):
            for target in _capability_test_targets(capability, root):
                commands.append(["cargo", "test", "--test", target, "--", "--nocapture"])
    return _unique_commands(commands)


def _capability_test_targets(capability: str, root: Path | None) -> tuple[str, ...]:
    targets = list(CAPABILITY_TEST_TARGETS.get(capability, ()))
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
    for path in sorted((root / "docs/core/capability-specs").glob(f"**/{capability}-*.md")):
        slug = path.stem.removeprefix(f"{capability}-")
        prefix = _slug_to_test_prefix(slug)
        if prefix:
            prefixes.append(prefix)
    return _unique_strings(prefixes)


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
    if _is_stage_closeout_task(text):
        print()
        print(f"==> ./dev check task {label}: stage closeout uses ./dev check all", flush=True)
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
    generated_excludes = "AreaMatrix/Bridge/Generated,AreaMatrix/Bridge/UniFFI"
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
        print()
        print("==> Skipping macOS checks")
        print(f"    {macos_dir} does not exist yet.")
        return 0
    if macos_project.is_dir():
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
    else:
        print()
        print("==> Skipping Xcode build and test")
        print(f"    {macos_project} does not exist yet.")
    return _run_swift_checks(root)


def run_all_check(root: Path | None = None) -> int:
    root = (root or project_root()).resolve()
    steps = [
        ("governance", lambda: run_governance_check(root)),
        ("skills", lambda: run_skills_check(root)),
        ("task-loop", lambda: run_task_loop_check(root)),
        ("prompt doctor", lambda: run_prompts_check(root)),
        ("diff check", lambda: run_diff_check(root)),
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
