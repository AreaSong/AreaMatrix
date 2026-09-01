"""Validate fingerprinted AreaMatrix CoreSDK cache artifacts."""

from __future__ import annotations

import hashlib
import json
import os
import plistlib
import stat
from pathlib import Path, PurePosixPath
from xml.parsers.expat import ExpatError

from .common import fail

CORE_SDK_SCHEMA_VERSION = 2
CORE_SDK_NAME = "AreaMatrixCoreFFI.xcframework"
CORE_SDK_PACKAGE_NAME = "AreaMatrixCoreSDK"
CORE_SDK_MANIFEST_NAME = "manifest.json"
CORE_SDK_MUTABLE_FILES = {".last-used"}

EXPECTED_APPLE_SLICES = {
    ("macos", None): {"arm64", "x86_64"},
    ("ios", None): {"arm64"},
    ("ios", "simulator"): {"arm64", "x86_64"},
}


def _entry_signature(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _entry_boundary_error(relative: str, metadata: os.stat_result) -> str | None:
    if hasattr(os, "getuid") and metadata.st_uid != os.getuid():
        return f"CoreSDK artifact entry is owned by another user: {relative}"
    if metadata.st_mode & 0o022:
        return f"CoreSDK artifact entry is group- or world-writable: {relative}"
    return None


def _open_verified_file(
    path: Path,
    artifact_root: Path,
    expected_metadata: os.stat_result,
) -> tuple[int | None, os.stat_result | None, str | None]:
    no_follow = getattr(os, "O_NOFOLLOW", None)
    if no_follow is None:
        return None, None, "this platform cannot verify CoreSDK files without following links"
    flags = os.O_RDONLY | no_follow | getattr(os, "O_CLOEXEC", 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        return None, None, f"unable to open CoreSDK output without following links: {path}: {error}"
    opened: os.stat_result | None = None
    try:
        opened = os.fstat(descriptor)
        if _entry_signature(opened) != _entry_signature(expected_metadata):
            return descriptor, opened, f"CoreSDK output changed before hashing: {path}"
        if not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1:
            return descriptor, opened, f"CoreSDK output is not a single-link regular file: {path}"
        resolved = path.resolve(strict=True)
        resolved.relative_to(artifact_root)
    except (OSError, ValueError) as error:
        return descriptor, opened, f"CoreSDK output escapes its artifact root: {path}: {error}"
    return descriptor, opened, None


def _finish_verified_file(
    descriptor: int,
    path: Path,
    opened: os.stat_result,
) -> str | None:
    try:
        after = os.fstat(descriptor)
        current = path.lstat()
    except OSError as error:
        return f"unable to recheck CoreSDK output after reading: {path}: {error}"
    expected = _entry_signature(opened)
    if _entry_signature(after) != expected or _entry_signature(current) != expected:
        return f"CoreSDK output changed while it was being read: {path}"
    return None


def _stable_sha256_file(
    path: Path,
    artifact_root: Path,
    expected_metadata: os.stat_result,
) -> tuple[str | None, str | None]:
    descriptor, opened, error = _open_verified_file(path, artifact_root, expected_metadata)
    if descriptor is None or opened is None or error is not None:
        if descriptor is not None:
            os.close(descriptor)
        return None, error
    digest = hashlib.sha256()
    try:
        while chunk := os.read(descriptor, 1024 * 1024):
            digest.update(chunk)
        error = _finish_verified_file(descriptor, path, opened)
    except OSError as read_error:
        error = f"unable to hash CoreSDK output {path}: {read_error}"
    finally:
        os.close(descriptor)
    return (None, error) if error else (digest.hexdigest(), None)


def _stable_read_file(
    path: Path,
    artifact_root: Path,
    *,
    max_bytes: int,
) -> tuple[bytes | None, str | None]:
    try:
        metadata = path.lstat()
    except OSError as error:
        return None, f"unable to inspect CoreSDK metadata file {path}: {error}"
    if metadata.st_size > max_bytes:
        return None, f"CoreSDK metadata file exceeds {max_bytes} bytes: {path}"
    descriptor, opened, error = _open_verified_file(path, artifact_root, metadata)
    if descriptor is None or opened is None or error is not None:
        if descriptor is not None:
            os.close(descriptor)
        return None, error
    content = bytearray()
    try:
        while chunk := os.read(descriptor, min(1024 * 1024, max_bytes + 1 - len(content))):
            content.extend(chunk)
            if len(content) > max_bytes:
                error = f"CoreSDK metadata file exceeds {max_bytes} bytes: {path}"
                break
        if error is None:
            error = _finish_verified_file(descriptor, path, opened)
    except OSError as read_error:
        error = f"unable to read CoreSDK metadata file {path}: {read_error}"
    finally:
        os.close(descriptor)
    return (None, error) if error else (bytes(content), None)


def core_sdk_output_records(artifact_dir: Path) -> tuple[list[dict[str, str]], list[str]]:
    """Hash every immutable regular file in a CoreSDK artifact."""

    records: list[dict[str, str]] = []
    errors: list[str] = []
    try:
        root_metadata = artifact_dir.lstat()
    except OSError as error:
        return records, [f"unable to inspect CoreSDK artifact root {artifact_dir}: {error}"]
    if stat.S_ISLNK(root_metadata.st_mode) or not stat.S_ISDIR(root_metadata.st_mode):
        return records, [f"CoreSDK artifact root must be a real directory: {artifact_dir}"]
    boundary_error = _entry_boundary_error(".", root_metadata)
    if boundary_error:
        errors.append(boundary_error)
    artifact_root = artifact_dir.resolve(strict=True)
    directory_signatures = {artifact_dir: _entry_signature(root_metadata)}

    def record_walk_error(error: OSError) -> None:
        errors.append(f"unable to traverse CoreSDK artifact: {error}")

    for directory, dirnames, filenames in os.walk(
        artifact_dir,
        topdown=True,
        onerror=record_walk_error,
        followlinks=False,
    ):
        directory_path = Path(directory)
        dirnames.sort()
        filenames.sort()

        retained_directories: list[str] = []
        for name in dirnames:
            path = directory_path / name
            relative = path.relative_to(artifact_dir).as_posix()
            try:
                metadata = path.lstat()
            except OSError as error:
                errors.append(f"unable to inspect CoreSDK path {relative}: {error}")
                continue
            if stat.S_ISLNK(metadata.st_mode):
                errors.append(f"CoreSDK artifact contains a symbolic link: {relative}")
                continue
            if not stat.S_ISDIR(metadata.st_mode):
                errors.append(f"CoreSDK artifact contains a non-directory entry: {relative}")
                continue
            boundary_error = _entry_boundary_error(relative, metadata)
            if boundary_error:
                errors.append(boundary_error)
            directory_signatures[path] = _entry_signature(metadata)
            retained_directories.append(name)
        dirnames[:] = retained_directories

        for name in filenames:
            path = directory_path / name
            relative = path.relative_to(artifact_dir).as_posix()
            try:
                metadata = path.lstat()
            except OSError as error:
                errors.append(f"unable to inspect CoreSDK path {relative}: {error}")
                continue
            if stat.S_ISLNK(metadata.st_mode):
                errors.append(f"CoreSDK artifact contains a symbolic link: {relative}")
                continue
            if not stat.S_ISREG(metadata.st_mode):
                errors.append(f"CoreSDK artifact contains a non-regular file: {relative}")
                continue
            if metadata.st_nlink != 1:
                errors.append(f"CoreSDK artifact contains a hard-linked file: {relative}")
                continue
            boundary_error = _entry_boundary_error(relative, metadata)
            if boundary_error:
                errors.append(boundary_error)
                continue
            if relative in CORE_SDK_MUTABLE_FILES:
                if metadata.st_size != 0:
                    errors.append(f"CoreSDK mutable marker must be empty: {relative}")
                continue
            if relative == CORE_SDK_MANIFEST_NAME:
                continue
            digest, hash_error = _stable_sha256_file(path, artifact_root, metadata)
            if hash_error:
                errors.append(hash_error)
                continue
            assert digest is not None
            records.append({"path": relative, "sha256": digest})

    for path, signature in sorted(directory_signatures.items(), key=lambda item: str(item[0])):
        try:
            current = path.lstat()
        except OSError as error:
            errors.append(f"unable to recheck CoreSDK directory {path}: {error}")
            continue
        if _entry_signature(current) != signature:
            errors.append(f"CoreSDK directory changed during inventory: {path}")

    records.sort(key=lambda record: record["path"])
    return records, errors


def _manifest_output_errors(
    outputs: object,
    actual_records: list[dict[str, str]],
) -> list[str]:
    errors: list[str] = []
    manifest_records: list[dict[str, str]] = []
    manifest_paths: list[str] = []
    if not isinstance(outputs, list):
        return ["CoreSDK manifest outputs must be an array"]

    for index, record in enumerate(outputs):
        if not isinstance(record, dict) or set(record) != {"path", "sha256"}:
            errors.append(f"CoreSDK manifest output {index} must contain only path and sha256")
            continue
        raw_path = record.get("path")
        digest = record.get("sha256")
        if not isinstance(raw_path, str) or not raw_path:
            errors.append(f"CoreSDK manifest output {index} has an invalid path")
            continue
        relative = PurePosixPath(raw_path)
        if (
            relative.is_absolute()
            or relative.as_posix() != raw_path
            or raw_path == "."
            or ".." in relative.parts
            or "\\" in raw_path
            or raw_path == CORE_SDK_MANIFEST_NAME
            or raw_path in CORE_SDK_MUTABLE_FILES
        ):
            errors.append(f"CoreSDK manifest output path is unsafe or mutable: {raw_path}")
            continue
        if not isinstance(digest, str) or len(digest) != 64 or any(
            character not in "0123456789abcdef" for character in digest
        ):
            errors.append(f"CoreSDK manifest output has an invalid SHA-256: {raw_path}")
            continue
        manifest_paths.append(raw_path)
        manifest_records.append({"path": raw_path, "sha256": digest})

    if len(manifest_paths) != len(set(manifest_paths)):
        errors.append("CoreSDK manifest outputs contain duplicate paths")
    if manifest_paths != sorted(manifest_paths):
        errors.append("CoreSDK manifest outputs must be sorted by path")

    manifest_by_path = {record["path"]: record["sha256"] for record in manifest_records}
    actual_by_path = {record["path"]: record["sha256"] for record in actual_records}
    for path in sorted(actual_by_path.keys() - manifest_by_path.keys()):
        errors.append(f"CoreSDK artifact contains an unlisted output: {path}")
    for path in sorted(manifest_by_path.keys() - actual_by_path.keys()):
        errors.append(f"CoreSDK manifest references a missing output: {path}")
    for path in sorted(actual_by_path.keys() & manifest_by_path.keys()):
        if actual_by_path[path] != manifest_by_path[path]:
            errors.append(f"CoreSDK output SHA-256 mismatch: {path}")
    return errors


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
    try:
        metadata = path.lstat()
    except OSError:
        return None, f"missing CoreSDK {kind}: {path}"
    if stat.S_ISLNK(metadata.st_mode):
        return None, f"CoreSDK required {kind} must not be a symbolic link: {path}"
    exists = stat.S_ISDIR(metadata.st_mode) if kind == "directory" else stat.S_ISREG(metadata.st_mode)
    if not exists:
        return None, f"missing CoreSDK {kind}: {path}"
    return path, None


def sdk_artifact_errors(artifact_dir: Path, expected_fingerprint: str) -> list[str]:
    """Return every structural or boundary error in one CoreSDK cache entry."""

    errors: list[str] = []
    actual_records, inventory_errors = core_sdk_output_records(artifact_dir)
    errors.extend(inventory_errors)
    required = {
        CORE_SDK_NAME: "directory",
        "Package.swift": "file",
        "Sources/AreaMatrixCoreSDK/area_matrix.swift": "file",
        CORE_SDK_MANIFEST_NAME: "file",
    }
    resolved: dict[str, Path] = {}
    for relative, kind in required.items():
        path, error = _required_artifact_path(artifact_dir, relative, kind=kind)
        if error:
            errors.append(error)
        elif path is not None:
            resolved[relative] = path

    if inventory_errors:
        return errors

    artifact_root = artifact_dir.resolve(strict=True)
    manifest: object = None
    sdk_manifest = resolved.get(CORE_SDK_MANIFEST_NAME)
    if sdk_manifest is not None:
        manifest_bytes, manifest_error = _stable_read_file(
            sdk_manifest,
            artifact_root,
            max_bytes=16 * 1024 * 1024,
        )
        if manifest_error:
            errors.append(manifest_error)
        else:
            try:
                assert manifest_bytes is not None
                manifest = json.loads(manifest_bytes.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                errors.append(f"invalid CoreSDK manifest: {error}")
    if isinstance(manifest, dict):
        if manifest.get("schema_version") != CORE_SDK_SCHEMA_VERSION:
            errors.append("CoreSDK manifest schema_version does not match the builder")
        if manifest.get("fingerprint") != expected_fingerprint:
            errors.append("CoreSDK manifest fingerprint does not match its cache directory")
        if manifest.get("xcframework") != CORE_SDK_NAME:
            errors.append("CoreSDK manifest xcframework name is invalid")
        errors.extend(_manifest_output_errors(manifest.get("outputs"), actual_records))
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
        info_bytes, info_error = _stable_read_file(
            info_plist,
            artifact_root,
            max_bytes=4 * 1024 * 1024,
        )
        if info_error:
            raise OSError(info_error)
        assert info_bytes is not None
        info_relative = f"{CORE_SDK_NAME}/Info.plist"
        actual_digests = {record["path"]: record["sha256"] for record in actual_records}
        if hashlib.sha256(info_bytes).hexdigest() != actual_digests.get(info_relative):
            raise OSError("Info.plist changed after the immutable output inventory")
        info = plistlib.loads(info_bytes)
        libraries = info.get("AvailableLibraries")
    except (OSError, plistlib.InvalidFileException, ExpatError, AttributeError) as error:
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
