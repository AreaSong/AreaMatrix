"""High-frequency AreaMatrix developer feedback-loop commands."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from .artifacts import CARGO_ARTIFACT_LANES, cargo_lane_lock, cargo_target_dir
from .checks import run_docs_check, run_governance_check, run_localization_check
from .common import ToolError, fail, require_command, run_step
from .core_sdk_artifact import verify_core_sdk_pointer
from .macos import run_macos_tests

DEVELOPER_SCENARIOS = (
    "ui-catalog",
    "ui-catalog-dark",
    "onboarding",
    "onboarding-dark",
    "settings-language",
    "settings-language-dark",
)

PYTHON_DEVELOPER_TEST_MODULES = (
    "scripts.dev_tools.test_build_tools",
    "scripts.dev_tools.test_core_sdk",
    "scripts.dev_tools.test_developer",
    "scripts.dev_tools.test_macos_runner",
    "scripts.dev_tools.test_release_tools",
)


def _git_lines(root: Path, *args: str) -> list[str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode != 0:
        fail(f"git {' '.join(args)} failed: {proc.stderr.strip() or proc.returncode}")
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


def changed_paths(root: Path) -> list[str]:
    """Return tracked, staged, and untracked workspace paths once each."""

    paths = {
        *_git_lines(root, "diff", "--name-only"),
        *_git_lines(root, "diff", "--cached", "--name-only"),
        *_git_lines(root, "ls-files", "--others", "--exclude-standard"),
    }
    return sorted(paths)


def _changed_test_layers(paths: list[str]) -> list[str]:
    layers: list[str] = []
    if any(
        path.startswith(("scripts/", ".cargo/")) or path in {"dev", "task-loop"}
        for path in paths
    ):
        layers.append("developer-tools")
    if any(path.startswith("core/") for path in paths):
        layers.append("rust-core")
    if any(path.startswith("apps/macos/") for path in paths):
        layers.append("macos-client")
    if any(path.startswith("apps/ios/") for path in paths):
        layers.append("ios-client")
    if any(
        path.startswith(("docs/", "workflow/", ".ai-governance/", ".codex/", ".agents/"))
        or path in {"AGENTS.md", "CODE_REVIEW.md", "SECURITY.md"}
        for path in paths
    ):
        layers.append("docs-governance")
    return layers


def _print_changed_plan(paths: list[str], layers: list[str]) -> None:
    print("Changed-path validation plan")
    print(f"- paths: {len(paths)}")
    print(f"- layers: {', '.join(layers) if layers else 'none'}")
    if "developer-tools" in layers:
        print("- developer-tools: Python developer-tool regression suite")
    if "rust-core" in layers:
        print("- rust-core: cargo test --workspace in validation lane")
    if "macos-client" in layers:
        print("- macos-client: localization contract + persistent-DerivedData XCTest")
    if "ios-client" in layers:
        print("- ios-client: Swift Package build")
    if "docs-governance" in layers:
        print("- docs-governance: docs + governance checks")


def run_changed_tests(root: Path, *, list_only: bool = False) -> int:
    """Run the smallest complete layer gates implied by the dirty worktree."""

    paths = changed_paths(root)
    layers = _changed_test_layers(paths)
    _print_changed_plan(paths, layers)
    if list_only or not layers:
        return 0

    if "developer-tools" in layers:
        proc = run_step(
            ["python3", "-m", "unittest", *PYTHON_DEVELOPER_TEST_MODULES],
            cwd=root,
            check=False,
            env={"PYTHONDONTWRITEBYTECODE": "1"},
        )
        if proc.returncode != 0:
            return proc.returncode
    if "rust-core" in layers:
        with cargo_lane_lock(root, lane="validation", operation="changed-tests"):
            proc = run_step(
                ["cargo", "test", "--manifest-path", "core/Cargo.toml", "--workspace"],
                cwd=root,
                check=False,
                env={"CARGO_TARGET_DIR": str(cargo_target_dir(root, lane="validation"))},
            )
        if proc.returncode != 0:
            return proc.returncode
    if "macos-client" in layers:
        localization_rc = run_localization_check(root)
        if localization_rc != 0:
            return localization_rc
        macos_rc = run_macos_tests(root)
        if macos_rc != 0:
            return macos_rc
    if "ios-client" in layers:
        proc = run_step(
            ["swift", "build", "--package-path", "apps/ios"],
            cwd=root,
            check=False,
        )
        if proc.returncode != 0:
            return proc.returncode
    if "docs-governance" in layers:
        docs_rc = run_docs_check(root)
        if docs_rc != 0:
            return docs_rc
        governance_rc = run_governance_check(root)
        if governance_rc != 0:
            return governance_rc
    return 0


def run_build_doctor(root: Path) -> int:
    """Audit local build-lane isolation, Xcode incrementality, locks, and CoreSDK."""

    issues: list[str] = []
    lane_paths = {lane: cargo_target_dir(root, lane=lane) for lane in CARGO_ARTIFACT_LANES}
    if len(set(lane_paths.values())) != len(lane_paths):
        issues.append("Cargo artifact lanes do not resolve to distinct target directories")

    cargo_config = root / ".cargo/config.toml"
    config_text = cargo_config.read_text(encoding="utf-8") if cargo_config.is_file() else ""
    if 'target-dir = ".build/cargo/validation"' not in config_text:
        issues.append(".cargo/config.toml does not isolate ad-hoc Cargo commands in validation lane")

    project = root / "apps/macos/AreaMatrix.xcodeproj/project.pbxproj"
    project_text = project.read_text(encoding="utf-8") if project.is_file() else ""
    xcode_requirements = {
        'dependencyFile = "$(DERIVED_FILE_DIR)/AreaMatrixCoreSDK.d";': "dependency file",
        '"$(SRCROOT)/../../.build/core-sdk/current/manifest.json",': "manifest output",
        '"$(SRCROOT)/../../scripts/dev_tools/core_sdk_artifact.py",': "artifact validator input",
        "build core-sdk --dependency-file": "fingerprinted CoreSDK build command",
    }
    for term, label in xcode_requirements.items():
        if term not in project_text:
            issues.append(f"Xcode Prepare CoreSDK is missing {label}")
    if "alwaysOutOfDate = 1;" in project_text:
        issues.append("Xcode contains an Always Out Of Date script phase")

    locks_root = root / ".build/locks/cargo"
    lock_paths = sorted(locks_root.glob("*.lock")) if locks_root.is_dir() else []
    for lock_path in lock_paths:
        try:
            metadata = json.loads(lock_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            issues.append(f"invalid Cargo lock metadata at {lock_path}: {error}")
            continue
        if metadata.get("lane") != lock_path.stem:
            issues.append(f"Cargo lock metadata lane differs from its filename: {lock_path}")

    pointer = root / ".build/core-sdk/current"
    if pointer.is_symlink():
        try:
            verify_core_sdk_pointer(root)
        except ToolError as error:
            issues.append(str(error))
    else:
        print("Build doctor: CoreSDK pointer is absent; it will be created on the first SDK build.")

    print("Cargo artifact lanes")
    for lane, path in lane_paths.items():
        print(f"- {lane}: {path}")
    if issues:
        print("Build doctor: FAILED")
        for issue in issues:
            print(f"- {issue}")
        return 1
    print("Build doctor: PASS")
    return 0


def run_macos_developer_scenario(
    root: Path,
    *,
    scenario: str,
    derived_data_path: str | Path | None = None,
    no_build: bool = False,
    build_only: bool = False,
) -> int:
    """Build and launch one deterministic DEBUG-only macOS UI scenario."""

    if scenario not in DEVELOPER_SCENARIOS:
        fail(f"unknown developer scenario {scenario!r}; choose from {', '.join(DEVELOPER_SCENARIOS)}")
    derived_data = Path(derived_data_path) if derived_data_path else root / ".build/derived-data/macos-run"
    if not derived_data.is_absolute():
        derived_data = root / derived_data
    if not no_build:
        require_command("xcodebuild")
        proc = run_step(
            [
                "xcodebuild",
                "-project",
                "apps/macos/AreaMatrix.xcodeproj",
                "-scheme",
                "AreaMatrix",
                "-configuration",
                "Debug",
                "-destination",
                "platform=macOS",
                "-derivedDataPath",
                derived_data,
                "build",
                "CODE_SIGNING_ALLOWED=NO",
            ],
            cwd=root,
            check=False,
        )
        if proc.returncode != 0:
            return proc.returncode

    executable = derived_data / "Build/Products/Debug/AreaMatrix.app/Contents/MacOS/AreaMatrix"
    if not executable.is_file():
        fail(f"Debug AreaMatrix executable not found at {executable}")
    print(f"Developer scenario: READY ({scenario})")
    print(f"- executable: {executable}")
    if build_only:
        return 0
    env = os.environ.copy()
    env["AREAMATRIX_SCENARIO"] = scenario
    try:
        return subprocess.run([str(executable)], cwd=root, env=env, check=False).returncode
    except KeyboardInterrupt:
        print(f"Developer scenario: STOPPED ({scenario})")
        return 130
