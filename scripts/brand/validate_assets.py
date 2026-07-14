#!/usr/bin/env python3
"""Validate the complete AreaMatrix brand delivery contract."""

from __future__ import annotations

import hashlib
import json
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image

ROOT_HINT = Path(__file__).resolve().parents[2]
if str(ROOT_HINT) not in sys.path:
    sys.path.insert(0, str(ROOT_HINT))

from scripts.brand.assets import ROOT, load_manifest, package_root, raster_jobs


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
    with Image.open(path) as image:
        if image.size != (width, height):
            errors.append(f"wrong dimensions: {relative(path)} expected {width}x{height}, got {image.width}x{image.height}")
        has_alpha = image.mode in ("RGBA", "LA") or "transparency" in image.info
        if has_alpha != alpha:
            errors.append(f"wrong alpha mode: {relative(path)} expected alpha={alpha}, got {has_alpha}")


def validate_tiff(path: Path, expected_dpi: int, errors: list[str]) -> None:
    if not path.exists():
        return
    with Image.open(path) as image:
        if image.size != (3600, 1170) or image.mode != "CMYK":
            errors.append(f"invalid print TIFF: {relative(path)} expected 3600x1170 CMYK, got {image.size} {image.mode}")
        dpi = image.info.get("dpi")
        if dpi is None or any(abs(value - expected_dpi) > 0.5 for value in dpi):
            errors.append(f"wrong print TIFF density: {relative(path)} expected {expected_dpi} DPI, got {dpi}")
        if image.tag_v2.get(296) != 2:
            errors.append(f"wrong print TIFF resolution unit: {relative(path)} expected inch")


def validate_ico(path: Path, sizes: list[int], errors: list[str]) -> None:
    if not path.exists():
        errors.append(f"missing ICO: {relative(path)}")
        return
    data = path.read_bytes()
    if len(data) < 6 or struct.unpack_from("<H", data, 2)[0] != 1:
        errors.append(f"invalid ICO header: {relative(path)}")
        return
    count = struct.unpack_from("<H", data, 4)[0]
    actual = [data[6 + index * 16] or 256 for index in range(count)]
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
        source = root / item["source"]
        output = ROOT / item["output"]
        require(source, errors)
        require(output, errors)
        if source.exists() and output.exists() and digest(source) != digest(output):
            errors.append(f"runtime copy drift: {item['output']}")


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
