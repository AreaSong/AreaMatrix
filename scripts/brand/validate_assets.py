#!/usr/bin/env python3
"""Validate the complete AreaMatrix brand delivery contract."""

from __future__ import annotations

import hashlib
import json
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath

ROOT_HINT = Path(__file__).resolve().parents[2]
if str(ROOT_HINT) not in sys.path:
    sys.path.insert(0, str(ROOT_HINT))

from scripts.brand.assets import ROOT, load_manifest, package_root, raster_jobs
from scripts.brand.image_safety import (
    MAX_IMAGE_FILE_BYTES,
    MAX_IMAGE_PIXELS,
    PNG_MAGIC,
    UnsafeImageError,
    image_dimensions,
    open_image,
)


EXPECTED_INTER_INPUT_SHA256 = "2ad83f2446566c5ecf7c261cc07884a5d5f71965b5df8fd7bb809f83a42bf470"
EXPECTED_INTER_UPSTREAM_COMMIT = "0a5106e0bde18df09374066bf3a7998e3546307d"
EXPECTED_INTER_UPSTREAM_SOURCE = (
    "https://github.com/rsms/inter/commit/0a5106e0bde18df09374066bf3a7998e3546307d"
)
EXPECTED_INTER_SOURCE_ARTIFACT = {
    "type": "github-blob",
    "owner": "linagora",
    "repository": "tmail-flutter",
    "commit": "0e6c107f63e4fd35615605b718963ffa6b2897a4",
    "path": "assets/fonts/Inter/Inter-Bold.ttf",
    "sha256": EXPECTED_INTER_INPUT_SHA256,
    "url": (
        "https://github.com/linagora/tmail-flutter/blob/"
        "0e6c107f63e4fd35615605b718963ffa6b2897a4/assets/fonts/Inter/Inter-Bold.ttf"
    ),
}
ARCHIVE_ROOT = PurePosixPath("assets/brand/archive")


def main() -> int:
    manifest = load_manifest()
    root = package_root(manifest)
    errors: list[str] = []
    for job in raster_jobs(manifest):
        require(root / job.source, errors)
        validate_raster(root / job.output, job.width, job.height, job.alpha, errors)
    overview = manifest["overview"]
    validate_raster(root / overview["output"], overview["width"], overview["height"], False, errors)
    validate_ico(root / manifest["favicon"]["ico"], manifest["favicon"]["sizes"], errors)
    validate_native(root, manifest, errors)
    validate_runtime_copies(root, manifest, errors)
    validate_svg_sources(root, errors)
    validate_integrations(root, manifest, errors)
    validate_provenance(manifest, errors)
    validate_metadata(root, errors)
    if errors:
        print("\n".join(f"FAIL {error}" for error in errors))
        return 1
    print(f"brand assets valid: {len(raster_jobs(manifest))} raster exports, native, print, docs, and runtime copies")
    return 0


def validate_native(root: Path, manifest: dict, errors: list[str]) -> None:
    required = (
        "README.md", "native/README.md", "native/macos/AreaMatrix.icns",
        "native/ios/AreaMatrixAppIcon.appiconset/Contents.json",
        "native/android/res/drawable-nodpi/areamatrix_adaptive_foreground.png",
        "native/android/res/drawable-nodpi/areamatrix_adaptive_background.png",
        "native/android/res/values/colors.xml",
        "native/android/res/mipmap-anydpi-v26/ic_launcher.xml",
        "native/android/res/mipmap-anydpi-v26/ic_launcher_round.xml",
        "native/windows/AreaMatrix.ico", "print/README.md",
        "print/areamatrix-logo-light-background.svg", "print/areamatrix-logo-dark-background.svg",
        "print/areamatrix-logo-light-background.pdf", "print/areamatrix-logo-dark-background.pdf",
        "print/areamatrix-logo-light-background-cmyk.tiff", "print/areamatrix-logo-dark-background-cmyk.tiff",
    )
    for relative in required:
        require(root / relative, errors)
    for size in (16, 32, 128, 256, 512):
        validate_raster(root / f"native/macos/AreaMatrix.iconset/icon_{size}x{size}.png", size, size, False, errors)
        validate_raster(root / f"native/macos/AreaMatrix.iconset/icon_{size}x{size}@2x.png", size * 2, size * 2, False, errors)
    validate_magic(root / "native/macos/AreaMatrix.icns", b"icns", errors)
    validate_ios(root / "native/ios/AreaMatrixAppIcon.appiconset", errors)
    validate_raster(root / "native/android/res/drawable-nodpi/areamatrix_adaptive_foreground.png", 432, 432, True, errors)
    validate_raster(root / "native/android/res/drawable-nodpi/areamatrix_adaptive_background.png", 432, 432, False, errors)
    validate_ico(root / "native/windows/AreaMatrix.ico", [16, 24, 32, 48, 64, 128, 256], errors)
    for name in ("light-background", "dark-background"):
        validate_magic(root / f"print/areamatrix-logo-{name}.pdf", b"%PDF", errors)
        validate_tiff(
            root / f"print/areamatrix-logo-{name}-cmyk.tiff",
            manifest["native"]["printDpi"],
            errors,
        )


def validate_ios(directory: Path, errors: list[str]) -> None:
    contents = directory / "Contents.json"
    if not contents.exists():
        return
    images = json.loads(contents.read_text())["images"]
    if len(images) != 18:
        errors.append(f"iOS AppIcon expected 18 slots, got {len(images)}")
    for item in images:
        points = float(item["size"].split("x")[0])
        pixels = round(points * int(item["scale"][0]))
        validate_raster(directory / item["filename"], pixels, pixels, False, errors)


def validate_raster(path: Path, width: int, height: int, alpha: bool, errors: list[str]) -> None:
    if not path.exists():
        errors.append(f"missing raster: {relative(path)}")
        return
    try:
        with open_image(path, "PNG") as image:
            if image.size != (width, height):
                errors.append(f"wrong dimensions: {relative(path)} expected {width}x{height}, got {image.width}x{image.height}")
            has_alpha = image.mode in ("RGBA", "LA") or "transparency" in image.info
            if has_alpha != alpha:
                errors.append(f"wrong alpha mode: {relative(path)} expected alpha={alpha}, got {has_alpha}")
    except UnsafeImageError as error:
        errors.append(f"unsafe PNG: {relative(path)}: {error}")


def validate_tiff(path: Path, expected_dpi: int, errors: list[str]) -> None:
    if not path.exists():
        return
    try:
        with open_image(path, "TIFF") as image:
            if image.size != (3600, 1170) or image.mode != "CMYK":
                errors.append(f"invalid print TIFF: {relative(path)} expected 3600x1170 CMYK, got {image.size} {image.mode}")
            dpi = image.info.get("dpi")
            if dpi is None or any(abs(value - expected_dpi) > 0.5 for value in dpi):
                errors.append(f"wrong print TIFF density: {relative(path)} expected {expected_dpi} DPI, got {dpi}")
            if image.tag_v2.get(296) != 2:
                errors.append(f"wrong print TIFF resolution unit: {relative(path)} expected inch")
    except UnsafeImageError as error:
        errors.append(f"unsafe TIFF: {relative(path)}: {error}")


def validate_ico(path: Path, sizes: list[int], errors: list[str]) -> None:
    if not path.exists():
        errors.append(f"missing ICO: {relative(path)}")
        return
    data = path.read_bytes()
    if len(data) < 6 or struct.unpack_from("<H", data, 2)[0] != 1:
        errors.append(f"invalid ICO header: {relative(path)}")
        return
    count = struct.unpack_from("<H", data, 4)[0]
    directory_end = 6 + count * 16
    if count == 0 or directory_end > len(data):
        errors.append(f"truncated ICO directory: {relative(path)}")
        return
    actual: list[int] = []
    for index in range(count):
        entry_offset = 6 + index * 16
        width = data[entry_offset] or 256
        height = data[entry_offset + 1] or 256
        payload_size, payload_offset = struct.unpack_from("<II", data, entry_offset + 8)
        if height != width or payload_size == 0 or payload_offset < directory_end or payload_offset + payload_size > len(data):
            errors.append(f"invalid ICO entry bounds: {relative(path)}")
            return
        actual.append(width)
    if actual != sizes:
        errors.append(f"wrong ICO sizes: {relative(path)} expected {sizes}, got {actual}")


def validate_svg_sources(root: Path, errors: list[str]) -> None:
    for path in root.rglob("*.svg"):
        try:
            tree = ET.parse(path)
        except ET.ParseError as error:
            errors.append(f"invalid SVG XML: {relative(path)}: {error}")
            continue
        if "outlined" in path.name and any(element.tag.endswith("text") for element in tree.iter()):
            errors.append(f"outlined SVG contains text: {relative(path)}")


def validate_runtime_copies(root: Path, manifest: dict, errors: list[str]) -> None:
    for item in manifest["runtimeCopies"]:
        source = resolve_manifest_path(root, item.get("source"), root, errors, "runtime source")
        output = resolve_manifest_path(ROOT, item.get("output"), ROOT, errors, "runtime output")
        if source is None or output is None:
            continue
        require(source, errors)
        require(output, errors)
        if source.is_symlink() or output.is_symlink():
            errors.append(f"runtime copy must not use symlinks: {item.get('output')}")
            continue
        if source.exists() and output.exists() and digest(source) != digest(output):
            errors.append(f"runtime copy drift: {item['output']}")


def resolve_manifest_path(base: Path, value: object, containment_root: Path, errors: list[str], label: str) -> Path | None:
    if not isinstance(value, str) or not value or PurePosixPath(value).is_absolute() or ".." in PurePosixPath(value).parts:
        errors.append(f"invalid {label} path: {value}")
        return None
    candidate = base / Path(value)
    try:
        candidate.resolve(strict=False).relative_to(containment_root.resolve())
    except ValueError:
        errors.append(f"{label} path escapes repository boundary: {value}")
        return None
    return candidate


def validate_integrations(root: Path, manifest: dict, errors: list[str]) -> None:
    if manifest.get("schemaVersion") != 1 or manifest.get("brand") != "AreaMatrix":
        errors.append("brand manifest identity or schema version is invalid")
    if manifest.get("native", {}).get("printDpi") != 300:
        errors.append("brand manifest printDpi must be 300")
    required = (
        ROOT / "assets/brand/README.md",
        ROOT / "assets/brand/wordmark-outlines.json",
        ROOT / "docs/ux/brand-assets.md",
        ROOT / "scripts/brand/build_source_assets.py",
        ROOT / "scripts/brand/export_assets.py",
        ROOT / "scripts/brand/validate_assets.py",
    )
    for path in required:
        require(path, errors)
    for readme in (ROOT / "README.md", ROOT / "README.zh-CN.md"):
        require(readme, errors)
        if readme.exists():
            text = readme.read_text(encoding="utf-8")
            for name in ("areamatrix-logo-lockup-outlined-dark.svg", "areamatrix-logo-lockup-outlined-light.svg"):
                if name not in text:
                    errors.append(f"README brand header missing {name}: {relative(readme)}")
    windows_project = ROOT / "apps/windows/AreaMatrix/AreaMatrix.Windows.csproj"
    require(windows_project, errors)
    if windows_project.exists() and "<ApplicationIcon>Resources\\AreaMatrix.ico</ApplicationIcon>" not in windows_project.read_text(encoding="utf-8"):
        errors.append("Windows project does not reference Resources\\AreaMatrix.ico")
    expected_sources = (
        "areamatrix-app-icon-small-dark.svg", "areamatrix-app-icon-small-light.svg",
        "areamatrix-app-icon-opaque-dark.svg", "areamatrix-app-icon-opaque-light.svg",
        "areamatrix-app-icon-maskable-dark.svg", "areamatrix-app-icon-maskable-light.svg",
        "areamatrix-logo-symbol-dark.svg", "areamatrix-logo-symbol-light.svg",
        "areamatrix-logo-lockup-outlined.svg", "areamatrix-logo-lockup-outlined-dark.svg",
        "areamatrix-logo-lockup-outlined-light.svg", "areamatrix-logo-lockup-mono-dark.svg",
        "areamatrix-logo-lockup-mono-light.svg", "areamatrix-wordmark-dark.svg",
        "areamatrix-wordmark-light.svg", "areamatrix-logo-stacked-dark.svg",
        "areamatrix-logo-stacked-light.svg",
    )
    for name in expected_sources:
        require(root / name, errors)


def resolve_archive_asset(archive_path: object, errors: list[str]) -> Path | None:
    """Resolve one provenance entry without allowing traversal or symlink escape."""
    if not isinstance(archive_path, str):
        errors.append(f"invalid archive provenance path: {archive_path}")
        return None
    relative_path = PurePosixPath(archive_path)
    if relative_path.is_absolute() or ".." in relative_path.parts or relative_path.parent == ARCHIVE_ROOT.parent:
        errors.append(f"invalid archive provenance path: {archive_path}")
        return None
    try:
        relative_path.relative_to(ARCHIVE_ROOT)
    except ValueError:
        errors.append(f"invalid archive provenance path: {archive_path}")
        return None
    try:
        archive_root = (ROOT / ARCHIVE_ROOT).resolve(strict=True)
        file_path = (ROOT / relative_path).resolve(strict=True)
        file_path.relative_to(archive_root)
    except FileNotFoundError:
        errors.append(f"missing brand archive provenance file: {archive_path}")
        return None
    except (OSError, ValueError):
        errors.append(f"archive provenance path escapes assets/brand/archive: {archive_path}")
        return None
    if not file_path.is_file():
        errors.append(f"archive provenance path is not a file: {archive_path}")
        return None
    return file_path


def validate_provenance(manifest: dict, errors: list[str]) -> None:
    """Check that release boundaries and recorded brand evidence are current."""
    declaration = manifest.get("provenance")
    if not isinstance(declaration, dict):
        errors.append("brand manifest provenance declaration is missing")
        return
    if declaration.get("path") != "assets/brand/provenance.json":
        errors.append("brand manifest provenance path is invalid")
        return
    if declaration.get("releaseEligible") is not False:
        errors.append("brand provenance must remain release-ineligible")
    if declaration.get("includedRoot") != "assets/brand/final":
        errors.append("brand provenance includedRoot must be assets/brand/final")
    if declaration.get("excludedRoots") != ["assets/brand/archive"]:
        errors.append("brand provenance must exclude assets/brand/archive")

    path = ROOT / declaration["path"]
    if not path.is_file():
        errors.append(f"missing brand provenance: {relative(path)}")
        return
    try:
        provenance = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        errors.append(f"invalid brand provenance JSON: {relative(path)}: {error}")
        return
    if provenance.get("schemaVersion") != 1 or provenance.get("brand") != "AreaMatrix":
        errors.append("brand provenance identity or schema version is invalid")
    policy = provenance.get("releasePolicy", {})
    if policy.get("includedRoot") != "assets/brand/final":
        errors.append("brand provenance releasePolicy includedRoot is invalid")
    if policy.get("excludedRoots") != ["assets/brand/archive"]:
        errors.append("brand provenance releasePolicy must exclude archive")
    if provenance.get("releaseEligible") is not False:
        errors.append("brand provenance releaseEligible must be false")

    wordmark = provenance.get("wordmarkInput", {})
    if wordmark.get("sha256") != EXPECTED_INTER_INPUT_SHA256:
        errors.append("Inter input SHA-256 does not match recorded evidence")
    if (
        wordmark.get("source") != EXPECTED_INTER_UPSTREAM_SOURCE
        or wordmark.get("upstreamCommit") != EXPECTED_INTER_UPSTREAM_COMMIT
    ):
        errors.append("Inter upstream source or commit is not approved")
    if wordmark.get("sourceArtifact") != EXPECTED_INTER_SOURCE_ARTIFACT:
        errors.append("Inter source artifact coordinates are not approved")
    license_path = resolve_manifest_path(ROOT, wordmark.get("licenseFile"), ROOT, errors, "wordmark license")
    if license_path is not None:
        if license_path.is_symlink() or not license_path.is_file():
            errors.append("wordmark license file is not a regular repository file")
        elif wordmark.get("licenseSha256") != digest(license_path):
            errors.append("wordmark license SHA-256 does not match provenance")
    outline_path = ROOT / "assets/brand/wordmark-outlines.json"
    if wordmark.get("outlinePath") != "assets/brand/wordmark-outlines.json":
        errors.append("wordmark outline path is invalid")
    elif outline_path.is_file() and wordmark.get("outlineSha256") != digest(outline_path):
        errors.append("wordmark outline SHA-256 does not match provenance")

    archive_assets = provenance.get("archiveAssets")
    if not isinstance(archive_assets, list) or len(archive_assets) != 16:
        errors.append("brand provenance must inventory exactly 16 archive assets")
        return
    seen_paths: set[str] = set()
    for item in archive_assets:
        if not isinstance(item, dict):
            errors.append("brand archive provenance entry is not an object")
            continue
        archive_path = item.get("path", "")
        file_path = resolve_archive_asset(archive_path, errors)
        if file_path is None:
            continue
        assert isinstance(archive_path, str)
        if archive_path in seen_paths:
            errors.append(f"duplicate archive provenance path: {archive_path}")
            continue
        seen_paths.add(archive_path)
        if item.get("sha256") != digest(file_path):
            errors.append(f"archive provenance hash mismatch: {archive_path}")
        if item.get("status") != "evidence-blocked":
            errors.append(f"archive provenance status is not evidence-blocked: {archive_path}")
    actual_paths = {
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "assets/brand/archive").rglob("*")
        if path.is_file()
    }
    if seen_paths != actual_paths:
        errors.append("brand provenance archive inventory does not match repository files")


def validate_metadata(root: Path, errors: list[str]) -> None:
    for path in root.rglob("*"):
        if path.name in (".DS_Store", "Thumbs.db") or path.name.endswith("~"):
            errors.append(f"metadata file present: {relative(path)}")


def validate_magic(path: Path, magic: bytes, errors: list[str]) -> None:
    if path.exists() and not path.read_bytes().startswith(magic):
        errors.append(f"wrong file signature: {relative(path)}")


def require(path: Path, errors: list[str]) -> None:
    if not path.is_file():
        errors.append(f"missing file: {relative(path)}")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path: Path) -> str:
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


if __name__ == "__main__":
    raise SystemExit(main())
