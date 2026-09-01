"""Shared fixture for CoreSDK artifact validation tests."""

from __future__ import annotations

import json
import plistlib
from pathlib import Path

from scripts.dev_tools import core_sdk


def write_core_sdk_artifact(root: Path, fingerprint: str) -> Path:
    artifact = root / ".build/core-sdk" / fingerprint
    (artifact / "Sources/AreaMatrixCoreSDK").mkdir(parents=True)
    (artifact / "Sources/AreaMatrixCoreSDK/area_matrix.swift").write_text(
        "// binding\n", encoding="utf-8"
    )
    (artifact / "Package.swift").write_text("// package\n", encoding="utf-8")
    xcframework = artifact / core_sdk.CORE_SDK_NAME
    libraries = [
        ("macos-arm64_x86_64", "macos", None, ["arm64", "x86_64"], "libmacos.a"),
        ("ios-arm64", "ios", None, ["arm64"], "libios.a"),
        (
            "ios-arm64_x86_64-simulator",
            "ios",
            "simulator",
            ["arm64", "x86_64"],
            "libsimulator.a",
        ),
    ]
    plist_entries = []
    for identifier, platform, variant, architectures, library_name in libraries:
        slice_root = xcframework / identifier
        (slice_root / "Headers").mkdir(parents=True)
        (slice_root / library_name).write_bytes(b"archive")
        (slice_root / "Headers/area_matrixFFI.h").write_text("// header\n", encoding="utf-8")
        (slice_root / "Headers/module.modulemap").write_text(
            "module Carea_matrixFFI {}\n", encoding="utf-8"
        )
        entry = {
            "LibraryIdentifier": identifier,
            "LibraryPath": library_name,
            "HeadersPath": "Headers",
            "SupportedArchitectures": architectures,
            "SupportedPlatform": platform,
        }
        if variant:
            entry["SupportedPlatformVariant"] = variant
        plist_entries.append(entry)
    with (xcframework / "Info.plist").open("wb") as handle:
        plistlib.dump({"AvailableLibraries": plist_entries}, handle)
    outputs, errors = core_sdk.core_sdk_output_records(artifact)
    if errors:
        raise AssertionError(f"invalid CoreSDK test fixture: {errors}")
    (artifact / "manifest.json").write_text(
        json.dumps(
            {
                "schema_version": core_sdk.CORE_SDK_SCHEMA_VERSION,
                "fingerprint": fingerprint,
                "xcframework": core_sdk.CORE_SDK_NAME,
                "outputs": outputs,
            }
        ),
        encoding="utf-8",
    )
    return artifact
