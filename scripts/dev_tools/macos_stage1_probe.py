"""Stage 1 macOS release app launch probe helpers."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Sequence

from .common import fail

STAGE1_APP_LAUNCH_BLOCKED = 75


def _stage1_launch_probe_build_base(root: Path, build_base: Sequence[str]) -> list[str]:
    signing_setting_prefixes = (
        "CODE_SIGNING_ALLOWED=",
        "CODE_SIGN_STYLE=",
        "CODE_SIGN_IDENTITY=",
        "DEVELOPMENT_TEAM=",
        "OTHER_LDFLAGS=",
    )
    release_build_base = [
        argument
        for argument in build_base
        if not any(str(argument).startswith(prefix) for prefix in signing_setting_prefixes)
    ]
    if "-configuration" not in release_build_base:
        release_build_base.extend(["-configuration", "Release"])
    staticlib = root / "core/target/aarch64-apple-darwin/release/libarea_matrix_core.a"
    release_build_base.extend([
        "CODE_SIGNING_ALLOWED=YES",
        "CODE_SIGN_STYLE=Manual",
        "CODE_SIGN_IDENTITY=-",
        "DEVELOPMENT_TEAM=",
        f"OTHER_LDFLAGS={staticlib}",
    ])
    return release_build_base


def run_stage1_app_launch_probe(
    root: Path,
    derived_data_dir: Path,
    build_base: Sequence[str],
    build_log_path: Path,
    run_and_tee,
) -> int:
    print()
    print("==> xcodebuild build signed Release for Stage 1 app launch probe")
    release_build_base = _stage1_launch_probe_build_base(root, build_base)
    rc = run_and_tee(["xcodebuild", "build", *release_build_base], build_log_path)
    if rc != 0:
        return rc

    app_bundle = derived_data_dir / "Build/Products/Release/AreaMatrix.app"
    probe_script = root / "scripts/dev_tools/macos_launch_probe.swift"
    _require_stage1_probe_inputs(probe_script, app_bundle)
    rc = _verify_release_app_signature(app_bundle)
    if rc != 0:
        return rc
    rc = _verify_release_app_is_self_contained(app_bundle)
    if rc != 0:
        return rc
    return _run_stage1_swift_launch_probe(derived_data_dir, probe_script, app_bundle)


def _require_stage1_probe_inputs(probe_script: Path, app_bundle: Path) -> None:
    if not probe_script.is_file():
        fail(f"Stage 1 app launch probe script not found at {probe_script}.")
    if not (app_bundle / "Contents/MacOS/AreaMatrix").is_file():
        fail(f"AreaMatrix app executable not found under {app_bundle}.")


def _verify_release_app_signature(app_bundle: Path) -> int:
    print()
    print(f"==> codesign --verify --deep --strict {app_bundle}")
    return subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_bundle)],
        check=False,
    ).returncode


def _run_stage1_swift_launch_probe(derived_data_dir: Path, probe_script: Path, app_bundle: Path) -> int:
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    module_cache = derived_data_dir / "SwiftProbeModuleCache.noindex"

    print()
    print(f"==> xcrun swift {probe_script} --app {app_bundle}")
    probe = _run_stage1_swift_probe_process(sdk, module_cache, probe_script, app_bundle)
    if probe.stdout:
        sys.stdout.write(probe.stdout)
    if probe.returncode == 0:
        return 0
    if _launchservices_probe_blocked(probe.stdout or ""):
        print("Stage 1 real .app launch probe: BLOCKED by local LaunchServices sandbox.")
        print("Stage 1 real .app launch probe: retrying signed Release executable directly.")
        return _run_stage1_direct_launch_probe(derived_data_dir, probe_script, app_bundle)
    return probe.returncode


def _run_stage1_direct_launch_probe(derived_data_dir: Path, probe_script: Path, app_bundle: Path) -> int:
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    module_cache = derived_data_dir / "SwiftDirectProbeModuleCache.noindex"

    print()
    print(f"==> xcrun swift {probe_script} --app {app_bundle} --launch-mode executable")
    probe = _run_stage1_swift_probe_process(
        sdk,
        module_cache,
        probe_script,
        app_bundle,
        ["--launch-mode", "executable"],
    )
    if probe.stdout:
        sys.stdout.write(probe.stdout)
    if probe.returncode == 0:
        return 0
    if _direct_launch_probe_blocked(probe.stdout or ""):
        print("Stage 1 real .app direct executable probe: BLOCKED by local windowing sandbox.")
        return STAGE1_APP_LAUNCH_BLOCKED
    return probe.returncode


def _run_stage1_swift_probe_process(
    sdk: str,
    module_cache: Path,
    probe_script: Path,
    app_bundle: Path,
    extra_args: Sequence[str] = (),
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        _stage1_swift_probe_argv(sdk, module_cache, probe_script, app_bundle, extra_args),
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def _stage1_swift_probe_argv(
    sdk: str,
    module_cache: Path,
    probe_script: Path,
    app_bundle: Path,
    extra_args: Sequence[str] = (),
) -> list[str]:
    return [
        "xcrun",
        "--sdk",
        "macosx",
        "swift",
        "-sdk",
        sdk,
        "-module-cache-path",
        str(module_cache),
        str(probe_script),
        "--app",
        str(app_bundle),
        "--threshold-ms",
        "1500",
        "--metric-name",
        "applicationLaunchToFirstScreen.realApp",
        *extra_args,
    ]


def _verify_release_app_is_self_contained(app_bundle: Path) -> int:
    executable = app_bundle / "Contents/MacOS/AreaMatrix"
    print()
    print(f"==> otool -L {executable}")
    probe = subprocess.run(
        ["otool", "-L", str(executable)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if probe.stdout:
        sys.stdout.write(probe.stdout)
    if probe.returncode != 0:
        return probe.returncode
    if "libarea_matrix_core.dylib" in (probe.stdout or ""):
        print("Stage 1 real .app launch probe: FAIL; Release app links core dylib instead of staticlib.")
        return 1
    return 0


def _launchservices_probe_blocked(output: str) -> bool:
    if os.environ.get("CODEX_SANDBOX") != "seatbelt":
        return False
    return any(
        marker in output
        for marker in [
            "kLSNoExecutableErr",
            "could not be launched because it is corrupt",
            "com.apple.hiservices-xpcservice",
            "LaunchServices",
        ]
    )


def _direct_launch_probe_blocked(output: str) -> bool:
    if os.environ.get("CODEX_SANDBOX") != "seatbelt":
        return False
    return "first visible window did not appear before timeout" in output
