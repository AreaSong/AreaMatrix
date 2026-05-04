"""Checks behind ./dev check."""

from __future__ import annotations

import os
import re
from pathlib import Path

from .build import run_core_build
from .common import fail, project_root, require_command, run_step
from .macos import run_macos_tests
from .skills import SimpleYAMLError, parse_frontmatter, parse_simple_yaml


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


def _run_swift_checks(root: Path) -> int:
    macos_dir = root / "apps/macos"
    require_command("swiftformat")
    require_command("swiftlint")
    for argv in [["swiftformat", "--lint", "."], ["swiftlint", "--strict"]]:
        proc = run_step(argv, cwd=macos_dir, check=False)
        if proc.returncode != 0:
            return proc.returncode
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
        rc = run_core_build(root)
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
