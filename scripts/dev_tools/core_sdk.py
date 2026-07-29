"""Build and cache the Apple CoreSDK XCFramework used by Swift clients."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from .artifacts import cargo_lane_lock, cargo_target_dir
from .build import run_core_build
from .common import fail, project_root, require_command, require_file, run_step
from .core_sdk_artifact import (
    CORE_SDK_NAME,
    CORE_SDK_PACKAGE_NAME,
    CORE_SDK_SCHEMA_VERSION,
    sdk_artifact_complete as _sdk_artifact_complete,
    sdk_artifact_errors as _sdk_artifact_errors,
    verify_core_sdk_pointer,
)
APPLE_TARGETS = (
    "aarch64-apple-darwin",
    "x86_64-apple-darwin",
    "aarch64-apple-ios",
    "aarch64-apple-ios-sim",
    "x86_64-apple-ios",
)


def _capture_version(argv: list[str]) -> str:
    proc = subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    if proc.returncode != 0:
        fail(f"unable to capture tool version: {' '.join(argv)}", proc.returncode)
    return proc.stdout.strip()


def _sdk_input_files(root: Path) -> list[Path]:
    core = root / "core"
    inputs = [
        root / "scripts/dev_tools/artifacts.py",
        root / "scripts/dev_tools/build.py",
        root / "scripts/dev_tools/core_sdk.py",
        root / "scripts/dev_tools/core_sdk_artifact.py",
        core / "Cargo.toml",
        core / "Cargo.lock",
        core / "build.rs",
        core / "area_matrix.udl",
        core / "uniffi.toml",
    ]
    for directory in (core / "src", core / "resources"):
        if directory.is_dir():
            inputs.extend(path for path in sorted(directory.rglob("*")) if path.is_file())
    return inputs


def core_sdk_fingerprint(
    root: Path,
    *,
    profile: str = "release",
    macos_deployment_target: str = "14.0",
    ios_deployment_target: str = "17.0",
) -> tuple[str, dict[str, object]]:
    """Hash every source/tool/configuration input that affects the Apple SDK."""

    metadata: dict[str, object] = {
        "schema_version": CORE_SDK_SCHEMA_VERSION,
        "profile": profile,
        "macos_deployment_target": macos_deployment_target,
        "ios_deployment_target": ios_deployment_target,
        "rustc": _capture_version(["rustc", "-vV"]),
        "xcodebuild": _capture_version(["xcodebuild", "-version"]),
        "targets": list(APPLE_TARGETS),
    }
    digest = hashlib.sha256(json.dumps(metadata, sort_keys=True).encode("utf-8"))
    input_records: list[dict[str, str]] = []
    for path in _sdk_input_files(root):
        relative = path.relative_to(root).as_posix()
        content_digest = hashlib.sha256(path.read_bytes()).hexdigest()
        input_records.append({"path": relative, "sha256": content_digest})
        digest.update(relative.encode("utf-8"))
        digest.update(bytes.fromhex(content_digest))
    metadata["inputs"] = input_records
    return digest.hexdigest(), metadata


def _profile_args(profile: str) -> tuple[list[str], str]:
    if profile == "release":
        return ["--release"], "release"
    if profile == "debug":
        return [], "debug"
    fail("CoreSDK profile must be 'release' or 'debug'.")
    raise AssertionError("unreachable")


def _build_ios_slices(
    root: Path,
    target_dir: Path,
    *,
    profile: str,
    ios_deployment_target: str,
) -> int:
    profile_args, _ = _profile_args(profile)
    env = {
        "CARGO_TARGET_DIR": str(target_dir),
        "IPHONEOS_DEPLOYMENT_TARGET": ios_deployment_target,
    }
    for target in APPLE_TARGETS[2:]:
        proc = run_step(
            ["cargo", "build", *profile_args, "--target", target],
            cwd=root / "core",
            env=env,
            check=False,
        )
        if proc.returncode != 0:
            return proc.returncode
    return 0


def _lipo(output: Path, *inputs: Path) -> None:
    for path in inputs:
        require_file(path, "CoreSDK static library slice")
    proc = run_step(["lipo", "-create", *inputs, "-output", output], check=False)
    if proc.returncode != 0:
        fail(f"unable to create universal CoreSDK slice: {output}", proc.returncode)


def _write_package(
    package_root: Path,
    generated_bindings: Path,
    *,
    macos_deployment_target: str = "14.0",
    ios_deployment_target: str = "17.0",
) -> None:
    sources = package_root / "Sources/AreaMatrixCoreSDK"
    sources.mkdir(parents=True, exist_ok=True)
    binding_source = (generated_bindings / "area_matrix.swift").read_text(encoding="utf-8")
    binding_source = binding_source.replace(
        "#if canImport(area_matrixFFI)\nimport area_matrixFFI\n#endif",
        "#if canImport(Carea_matrixFFI)\nimport Carea_matrixFFI\n#endif",
        1,
    )
    (sources / "area_matrix.swift").write_text(binding_source, encoding="utf-8")
    (package_root / "Package.swift").write_text(
        """// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AreaMatrixCoreSDK",
    platforms: [.macOS("__MACOS_TARGET__"), .iOS("__IOS_TARGET__")],
    products: [
        .library(name: "AreaMatrixCoreSDK", targets: ["AreaMatrixCoreSDK"])
    ],
    targets: [
        .binaryTarget(name: "Carea_matrixFFI", path: "AreaMatrixCoreFFI.xcframework"),
        .target(name: "AreaMatrixCoreSDK", dependencies: ["Carea_matrixFFI"])
    ]
)
""".replace("__MACOS_TARGET__", macos_deployment_target).replace(
            "__IOS_TARGET__", ios_deployment_target
        ),
        encoding="utf-8",
    )


def _replace_symlink(link: Path, target: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.exists() and not link.is_symlink():
        fail(f"CoreSDK pointer exists but is not a symlink: {link}")
    temporary = link.with_name(f".{link.name}.{os.getpid()}.tmp")
    if temporary.is_symlink():
        temporary.unlink()
    temporary.symlink_to(target, target_is_directory=True)
    os.replace(temporary, link)


def _publish_sdk_pointers(root: Path, artifact_dir: Path) -> None:
    sdk_root = root / ".build/core-sdk"
    _replace_symlink(sdk_root / "current", artifact_dir.relative_to(sdk_root))
    ios_pointer = root / "apps/ios/.core-sdk"
    _replace_symlink(ios_pointer, artifact_dir)


def _replace_artifact_atomically(staged_artifact: Path, artifact_dir: Path) -> None:
    if not artifact_dir.exists():
        os.replace(staged_artifact, artifact_dir)
        return
    backup = artifact_dir.with_name(f".{artifact_dir.name}.{os.getpid()}.backup")
    if backup.exists():
        fail(f"stale CoreSDK replacement backup exists: {backup}")
    os.replace(artifact_dir, backup)
    try:
        os.replace(staged_artifact, artifact_dir)
    except BaseException:
        os.replace(backup, artifact_dir)
        raise
    shutil.rmtree(backup)


def _escape_makefile_path(path: Path) -> str:
    return str(path).replace("\\", "\\\\").replace(" ", "\\ ").replace("#", "\\#").replace("$", "$$")


def _write_sdk_dependency_file(root: Path, dependency_file: str | Path, manifest: Path) -> None:
    path = Path(dependency_file)
    if not path.is_absolute():
        path = root / path
    path.parent.mkdir(parents=True, exist_ok=True)
    inputs = " ".join(_escape_makefile_path(item) for item in _sdk_input_files(root))
    path.write_text(f"{_escape_makefile_path(manifest)}: {inputs}\n", encoding="utf-8")


def _run_core_sdk_build_inner(
    root: Path,
    *,
    profile: str = "release",
    macos_deployment_target: str = "14.0",
    ios_deployment_target: str = "17.0",
    force: bool = False,
    dependency_file: str | Path | None = None,
    _lock_acquired: bool = False,
    _lock_wait_seconds: float = 0.0,
) -> tuple[int, str, float]:
    """Build a fingerprinted macOS/iOS XCFramework and generated Swift package."""

    for command in ("cargo", "rustc", "lipo", "xcodebuild"):
        require_command(command)
    fingerprint, metadata = core_sdk_fingerprint(
        root,
        profile=profile,
        macos_deployment_target=macos_deployment_target,
        ios_deployment_target=ios_deployment_target,
    )
    sdk_root = root / ".build/core-sdk"
    artifact_dir = sdk_root / fingerprint
    if not force and _sdk_artifact_complete(artifact_dir, fingerprint):
        _publish_sdk_pointers(root, artifact_dir)
        if dependency_file:
            _write_sdk_dependency_file(root, dependency_file, sdk_root / "current/manifest.json")
        cache = "hit-after-wait" if _lock_acquired else "hit"
        label = "HIT-AFTER-WAIT" if _lock_acquired else "HIT"
        print(f"CoreSDK cache: {label} ({fingerprint[:12]})")
        print(f"    package: {sdk_root / 'current'}")
        return 0, cache, _lock_wait_seconds

    if not _lock_acquired:
        with cargo_lane_lock(root, lane="sdk", operation="core-sdk") as lease:
            return _run_core_sdk_build_inner(
                root,
                profile=profile,
                macos_deployment_target=macos_deployment_target,
                ios_deployment_target=ios_deployment_target,
                force=force,
                dependency_file=dependency_file,
                _lock_acquired=True,
                _lock_wait_seconds=lease.wait_seconds,
            )

    target_dir = cargo_target_dir(root, lane="sdk")
    sdk_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="areamatrix-core-sdk-", dir=sdk_root) as temp:
        stage = Path(temp)
        generated = stage / "Generated"
        rc = run_core_build(
            root,
            profile=profile,
            out_dir=generated,
            deployment_target=macos_deployment_target,
            cargo_lane="sdk",
            acquire_cargo_lock=False,
        )
        if rc != 0:
            return rc, "miss", _lock_wait_seconds
        rc = _build_ios_slices(
            root,
            target_dir,
            profile=profile,
            ios_deployment_target=ios_deployment_target,
        )
        if rc != 0:
            return rc, "miss", _lock_wait_seconds

        _, target_profile = _profile_args(profile)
        libraries = stage / "Libraries"
        libraries.mkdir()
        macos_universal = libraries / "libarea_matrix_core-macos.a"
        simulator_universal = libraries / "libarea_matrix_core-ios-simulator.a"
        _lipo(
            macos_universal,
            target_dir / f"aarch64-apple-darwin/{target_profile}/libarea_matrix_core.a",
            target_dir / f"x86_64-apple-darwin/{target_profile}/libarea_matrix_core.a",
        )
        _lipo(
            simulator_universal,
            target_dir / f"aarch64-apple-ios-sim/{target_profile}/libarea_matrix_core.a",
            target_dir / f"x86_64-apple-ios/{target_profile}/libarea_matrix_core.a",
        )
        headers = stage / "Headers"
        headers.mkdir()
        shutil.copy2(generated / "area_matrixFFI.h", headers / "area_matrixFFI.h")
        generated_modulemap = generated / "module.modulemap"
        if not generated_modulemap.is_file():
            generated_modulemap = generated / "area_matrixFFI.modulemap"
        require_file(generated_modulemap, "generated CoreSDK module map")
        modulemap = generated_modulemap.read_text(encoding="utf-8")
        modulemap = modulemap.replace("module area_matrixFFI", "module Carea_matrixFFI", 1)
        (headers / "module.modulemap").write_text(modulemap, encoding="utf-8")

        package = stage / "Package"
        package.mkdir()
        xcframework = package / CORE_SDK_NAME
        proc = run_step(
            [
                "xcodebuild",
                "-create-xcframework",
                "-library",
                macos_universal,
                "-headers",
                headers,
                "-library",
                target_dir / f"aarch64-apple-ios/{target_profile}/libarea_matrix_core.a",
                "-headers",
                headers,
                "-library",
                simulator_universal,
                "-headers",
                headers,
                "-output",
                xcframework,
            ],
            check=False,
        )
        if proc.returncode != 0:
            return proc.returncode, "miss", _lock_wait_seconds
        _write_package(
            package,
            generated,
            macos_deployment_target=macos_deployment_target,
            ios_deployment_target=ios_deployment_target,
        )
        metadata["fingerprint"] = fingerprint
        metadata["xcframework"] = CORE_SDK_NAME
        (package / "manifest.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        staged_errors = _sdk_artifact_errors(package, fingerprint)
        if staged_errors:
            fail("staged CoreSDK validation failed:\n- " + "\n- ".join(staged_errors))
        _replace_artifact_atomically(package, artifact_dir)

    _publish_sdk_pointers(root, artifact_dir)
    if dependency_file:
        _write_sdk_dependency_file(root, dependency_file, sdk_root / "current/manifest.json")
    print(f"CoreSDK cache: MISS -> BUILT ({fingerprint[:12]})")
    print(f"    package: {sdk_root / 'current'}")
    print(f"    xcframework: {sdk_root / 'current' / CORE_SDK_NAME}")
    return 0, "miss", _lock_wait_seconds


def run_core_sdk_build(
    root: Path | None = None,
    *,
    profile: str = "release",
    macos_deployment_target: str = "14.0",
    ios_deployment_target: str = "17.0",
    force: bool = False,
    dependency_file: str | Path | None = None,
    verify_only: bool = False,
) -> int:
    """Build/reuse CoreSDK, or validate a restored cache pointer without invoking build tools."""

    root = (root or project_root()).resolve()
    if verify_only:
        if force:
            fail("--verify-only cannot be combined with --force.")
        for command in ("rustc", "xcodebuild"):
            require_command(command)
        fingerprint, _ = core_sdk_fingerprint(
            root,
            profile=profile,
            macos_deployment_target=macos_deployment_target,
            ios_deployment_target=ios_deployment_target,
        )
        return verify_core_sdk_pointer(root, expected_fingerprint=fingerprint)

    started_at = time.monotonic()
    result: int | None = None
    cache = "unknown"
    lock_wait_seconds = 0.0
    try:
        result, cache, lock_wait_seconds = _run_core_sdk_build_inner(
            root,
            profile=profile,
            macos_deployment_target=macos_deployment_target,
            ios_deployment_target=ios_deployment_target,
            force=force,
            dependency_file=dependency_file,
        )
        return result
    finally:
        print(
            "CoreSDK metrics: "
            f"status={result if result is not None else 'error'} cache={cache} "
            f"cargo_lane=sdk lock_wait_seconds={lock_wait_seconds:.3f} "
            f"duration_seconds={time.monotonic() - started_at:.3f}"
        )
