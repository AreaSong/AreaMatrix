"""Validate fingerprinted AreaMatrix CoreSDK cache artifacts."""

from __future__ import annotations

import json
import plistlib
from pathlib import Path

from .common import fail

CORE_SDK_SCHEMA_VERSION = 1
CORE_SDK_NAME = "AreaMatrixCoreFFI.xcframework"
CORE_SDK_PACKAGE_NAME = "AreaMatrixCoreSDK"

EXPECTED_APPLE_SLICES = {
    ("macos", None): {"arm64", "x86_64"},
    ("ios", None): {"arm64"},
    ("ios", "simulator"): {"arm64", "x86_64"},
}


def _safe_descendant(root: Path, value: object, label: str) -> tuple[Path | None, str | None]:
    if not isinstance(value, str) or not value:
        return None, f"{label} must be a non-empty relative path"
    relative = Path(value)
    if relative.is_absolute() or ".." in relative.parts:
        return None, f"{label} escapes its artifact root: {value}"

    resolved_root = root.resolve()
    resolved = (root / relative).resolve()
    try:
        resolved.relative_to(resolved_root)
    except ValueError:
        return None, f"{label} escapes its artifact root: {value}"
    return resolved, None


def _required_artifact_path(
    artifact_dir: Path,
    relative: str,
    *,
    kind: str,
) -> tuple[Path | None, str | None]:
    path, error = _safe_descendant(artifact_dir, relative, relative)
    if error:
        return None, error
    assert path is not None
    exists = path.is_dir() if kind == "directory" else path.is_file()
    if not exists:
        return None, f"missing CoreSDK {kind}: {path}"
    return path, None


def sdk_artifact_errors(artifact_dir: Path, expected_fingerprint: str) -> list[str]:
    """Return every structural or boundary error in one CoreSDK cache entry."""

    errors: list[str] = []
    required = {
        CORE_SDK_NAME: "directory",
        "Package.swift": "file",
        "Sources/AreaMatrixCoreSDK/area_matrix.swift": "file",
        "manifest.json": "file",
    }
    resolved: dict[str, Path] = {}
    for relative, kind in required.items():
        path, error = _required_artifact_path(artifact_dir, relative, kind=kind)
        if error:
            errors.append(error)
        elif path is not None:
            resolved[relative] = path

    manifest: object = None
    sdk_manifest = resolved.get("manifest.json")
    if sdk_manifest is not None:
        try:
            manifest = json.loads(sdk_manifest.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            errors.append(f"invalid CoreSDK manifest: {error}")
    if isinstance(manifest, dict):
        if manifest.get("schema_version") != CORE_SDK_SCHEMA_VERSION:
            errors.append("CoreSDK manifest schema_version does not match the builder")
        if manifest.get("fingerprint") != expected_fingerprint:
            errors.append("CoreSDK manifest fingerprint does not match its cache directory")
        if manifest.get("xcframework") != CORE_SDK_NAME:
            errors.append("CoreSDK manifest xcframework name is invalid")
    elif manifest is not None:
        errors.append("CoreSDK manifest root must be an object")

    xcframework = resolved.get(CORE_SDK_NAME)
    if xcframework is None:
        return errors
    info_plist, plist_error = _required_artifact_path(
        xcframework,
        "Info.plist",
        kind="file",
    )
    if plist_error:
        errors.append(plist_error)
        return errors

    libraries: object = None
    try:
        assert info_plist is not None
        with info_plist.open("rb") as handle:
            info = plistlib.load(handle)
        libraries = info.get("AvailableLibraries")
    except (OSError, plistlib.InvalidFileException, AttributeError) as error:
        errors.append(f"invalid XCFramework Info.plist: {error}")

    actual_slices: dict[tuple[object, object], set[str]] = {}
    identifiers: set[str] = set()
    if isinstance(libraries, list):
        for library in libraries:
            if not isinstance(library, dict):
                errors.append("XCFramework library entry must be an object")
                continue
            key = (library.get("SupportedPlatform"), library.get("SupportedPlatformVariant"))
            architectures = library.get("SupportedArchitectures")
            if key in actual_slices:
                errors.append(f"XCFramework contains duplicate slice metadata: {key}")
            if not isinstance(architectures, list) or not all(
                isinstance(item, str) and item for item in architectures
            ):
                errors.append(f"XCFramework slice {key} has invalid architectures")
                continue
            actual_slices[key] = set(architectures)

            identifier = library.get("LibraryIdentifier")
            slice_root, identifier_error = _safe_descendant(
                xcframework,
                identifier,
                f"XCFramework slice {key} identifier",
            )
            if identifier_error:
                errors.append(identifier_error)
                continue
            assert slice_root is not None and isinstance(identifier, str)
            if identifier in identifiers:
                errors.append(f"XCFramework contains duplicate LibraryIdentifier: {identifier}")
            identifiers.add(identifier)

            for field, expected_kind in (("LibraryPath", "file"), ("HeadersPath", "directory")):
                path, path_error = _safe_descendant(
                    slice_root,
                    library.get(field),
                    f"XCFramework slice {key} {field}",
                )
                if path_error:
                    errors.append(path_error)
                    continue
                assert path is not None
                exists = path.is_file() if expected_kind == "file" else path.is_dir()
                if not exists:
                    errors.append(f"XCFramework slice {key} is missing its {field}")
    elif libraries is not None:
        errors.append("XCFramework AvailableLibraries must be an array")

    if actual_slices != EXPECTED_APPLE_SLICES:
        errors.append(
            f"XCFramework slices differ: expected {EXPECTED_APPLE_SLICES}, actual {actual_slices}"
        )
    return errors


def sdk_artifact_complete(artifact_dir: Path, expected_fingerprint: str) -> bool:
    return not sdk_artifact_errors(artifact_dir, expected_fingerprint)


def verify_core_sdk_pointer(
    root: Path,
    pointer: str | Path = ".build/core-sdk/current",
    *,
    expected_fingerprint: str | None = None,
) -> int:
    """Validate a cache pointer and optionally bind it to the current source fingerprint."""

    pointer_path = Path(pointer)
    if not pointer_path.is_absolute():
        pointer_path = root / pointer_path
    if not pointer_path.is_symlink():
        fail(f"CoreSDK pointer is not a symlink: {pointer_path}")
    artifact_dir = pointer_path.resolve()
    sdk_root = (root / ".build/core-sdk").resolve()
    if artifact_dir.parent != sdk_root:
        fail(f"CoreSDK pointer escapes the cache root: {pointer_path} -> {artifact_dir}")
    fingerprint = artifact_dir.name
    if len(fingerprint) != 64 or any(character not in "0123456789abcdef" for character in fingerprint):
        fail(f"CoreSDK cache directory is not a SHA-256 fingerprint: {artifact_dir}")
    if expected_fingerprint is not None and fingerprint != expected_fingerprint:
        fail(
            "CoreSDK artifact does not match the current source/tool fingerprint: "
            f"expected {expected_fingerprint[:12]}, restored {fingerprint[:12]}"
        )
    errors = sdk_artifact_errors(artifact_dir, fingerprint)
    if errors:
        fail("CoreSDK artifact validation failed:\n- " + "\n- ".join(errors))
    print(f"CoreSDK artifact: PASS ({fingerprint[:12]})")
    return 0
