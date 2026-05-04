"""macOS XCTest runner with local sandbox fallback."""

from __future__ import annotations

import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Mapping, Sequence

from .common import fail, project_root, require_command


def _run_and_tee(argv: Sequence[str], log_path: Path, *, env: Mapping[str, str] | None = None) -> int:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    with log_path.open("w", encoding="utf-8") as log:
        proc = subprocess.Popen(
            [str(part) for part in argv],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=merged_env,
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            sys.stdout.write(line)
            log.write(line)
        return proc.wait()


def _sandbox_failure(log_path: Path) -> bool:
    text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    return bool(
        re.search(r"testmanagerd\.control|Failed to establish communication with the test runner", text)
        and re.search(r"sandbox", text, flags=re.IGNORECASE)
    )


def _find_test_bundle(derived_data_dir: Path, test_bundle_name: str) -> Path | None:
    products_dir = derived_data_dir / "Build/Products"
    default_bundle = products_dir / "Debug" / test_bundle_name
    if default_bundle.is_dir():
        return default_bundle
    if not products_dir.exists():
        return None
    for path in products_dir.rglob(test_bundle_name):
        if path.is_dir():
            return path
    return None


def _run_xctest_bundle(test_bundle: Path, scheme: str) -> int:
    products_dir = test_bundle.parent
    app_macos_dir = products_dir / f"{scheme}.app/Contents/MacOS"
    if not test_bundle.is_dir():
        fail(f"test bundle not found at {test_bundle}.")
    if not app_macos_dir.is_dir():
        fail(f"app binary directory not found at {app_macos_dir}.")

    env = os.environ.copy()
    env["DYLD_LIBRARY_PATH"] = f"{app_macos_dir}:{env.get('DYLD_LIBRARY_PATH', '')}"
    env["DYLD_FRAMEWORK_PATH"] = f"{products_dir}:{env.get('DYLD_FRAMEWORK_PATH', '')}"
    print()
    print(f"==> xcrun xctest {test_bundle}")
    return subprocess.run(["xcrun", "xctest", str(test_bundle)], env=env, check=False).returncode


def run_macos_tests(
    root: Path | None = None,
    *,
    scheme: str | None = None,
    test_bundle_name: str | None = None,
    destination: str | None = None,
    derived_data_path: str | Path | None = None,
    keep_derived_data: bool | None = None,
    test_log: str | Path | None = None,
    build_log: str | Path | None = None,
    result_bundle_path: str | Path | None = None,
) -> int:
    root = (root or project_root()).resolve()
    project_path = root / "apps/macos/AreaMatrix.xcodeproj"
    scheme = scheme or os.environ.get("XCODE_SCHEME", "AreaMatrix")
    test_bundle_name = test_bundle_name or os.environ.get("XCODE_TEST_BUNDLE_NAME", "AreaMatrixTests.xctest")
    destination = destination or os.environ.get("XCODE_DESTINATION", f"platform=macOS,arch={platform.machine()}")
    keep = keep_derived_data if keep_derived_data is not None else os.environ.get("KEEP_DERIVED_DATA", "0") == "1"
    created = False

    if derived_data_path or os.environ.get("DERIVED_DATA_PATH"):
        derived_data_dir = Path(derived_data_path or os.environ["DERIVED_DATA_PATH"])
    else:
        derived_data_dir = Path(tempfile.mkdtemp(prefix="areamatrix-xcode-tests.", dir=os.environ.get("TMPDIR", "/tmp")))
        created = True

    test_log_path = Path(test_log or os.environ.get("XCODEBUILD_TEST_LOG", derived_data_dir / "xcodebuild-test.log"))
    build_log_path = Path(build_log or os.environ.get("XCODEBUILD_BUILD_LOG", derived_data_dir / "xcodebuild-build-for-testing.log"))
    result_bundle = result_bundle_path or os.environ.get("XCODE_RESULT_BUNDLE_PATH")

    try:
        require_command("xcodebuild")
        require_command("xcrun")
        if not project_path.is_dir():
            fail(f"Xcode project not found at {project_path}.")
        derived_data_dir.mkdir(parents=True, exist_ok=True)

        base = [
            "-project",
            str(project_path),
            "-scheme",
            scheme,
            "-destination",
            destination,
            "-derivedDataPath",
            str(derived_data_dir),
        ]
        if result_bundle:
            base.extend(["-resultBundlePath", str(result_bundle)])
        base.append("CODE_SIGNING_ALLOWED=NO")
        build_base = [
            "-project",
            str(project_path),
            "-scheme",
            scheme,
            "-destination",
            destination,
            "-derivedDataPath",
            str(derived_data_dir),
            "CODE_SIGNING_ALLOWED=NO",
        ]
        print("==> xcodebuild test")
        rc = _run_and_tee(["xcodebuild", "test", *base], test_log_path)
        if rc == 0:
            print("macOS tests: xcodebuild test passed.")
            return 0
        if not _sandbox_failure(test_log_path):
            fail(f"xcodebuild test failed for a non-sandbox reason. See {test_log_path}.", rc)

        print()
        print("==> xcodebuild test was blocked by local sandboxed testmanagerd access.")
        print("    Reusing the built XCTest bundle for direct XCTest execution.")
        test_bundle = _find_test_bundle(derived_data_dir, test_bundle_name)
        if test_bundle is None:
            print()
            print("==> xcodebuild build-for-testing")
            rc = _run_and_tee(["xcodebuild", "build-for-testing", *build_base], build_log_path)
            if rc != 0:
                return rc
            test_bundle = _find_test_bundle(derived_data_dir, test_bundle_name)
        if test_bundle is None:
            fail(f"unable to locate {test_bundle_name} under {derived_data_dir}.")

        rc = _run_xctest_bundle(test_bundle, scheme)
        if rc == 0:
            print("macOS tests: xcrun xctest passed after xcodebuild test sandbox block.")
        return rc
    finally:
        if created and not keep:
            shutil.rmtree(derived_data_dir, ignore_errors=True)
