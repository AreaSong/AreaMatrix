#!/usr/bin/env python3
"""Generate AreaMatrix brand raster, native, social, and print deliverables."""

from __future__ import annotations

import argparse
import io
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT_HINT = Path(__file__).resolve().parents[2]
if str(ROOT_HINT) not in sys.path:
    sys.path.insert(0, str(ROOT_HINT))

from scripts.brand.assets import ROOT, load_manifest, package_root, raster_jobs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Rebuild existing generated files")
    args = parser.parse_args()
    manifest = load_manifest()
    root = package_root(manifest)

    for job in raster_jobs(manifest):
        output = root / job.output
        if args.refresh or not output.exists():
            render_svg(root / job.source, output, job.width, job.height, job.alpha, manifest)

    export_favicon(root, manifest, args.refresh)
    export_macos(root, manifest, args.refresh)
    export_ios(root, manifest, args.refresh)
    export_android(root, manifest, args.refresh)
    export_windows(root, manifest, args.refresh)
    export_print(root, manifest, args.refresh)
    export_overview(root, manifest, args.refresh)
    sync_runtime_copies(root, manifest)
    print(f"brand export complete: {len(raster_jobs(manifest))} raster jobs")
    return 0


def render_svg(
    source: Path,
    output: Path,
    width: int,
    height: int,
    alpha: bool,
    manifest: dict,
) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="areamatrix-brand-") as temporary:
        rendered = Path(temporary) / "rendered.png"
        subprocess.run(
            ["sips", "-s", "format", "png", "-z", str(height), str(width), str(source), "--out", str(rendered)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        with Image.open(rendered) as image:
            image.load()
            image = image.convert("RGBA")
            if not alpha:
                background = Image.new("RGB", image.size, manifest["native"]["androidBackground"])
                background.paste(image, mask=image.getchannel("A"))
                image = background
            image.save(output, format="PNG", optimize=True)


def export_favicon(root: Path, manifest: dict, refresh: bool) -> None:
    favicon = manifest["favicon"]
    output = root / favicon["ico"]
    if not refresh and output.exists():
        return
    images = [png_bytes(root / favicon["output"].replace("{size}", str(size))) for size in favicon["sizes"]]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(build_ico(favicon["sizes"], images))


def export_macos(root: Path, manifest: dict, refresh: bool) -> None:
    directory = root / "native/macos"
    iconset = directory / "AreaMatrix.iconset"
    icns = directory / "AreaMatrix.icns"
    if not refresh and icns.exists():
        return
    shutil.rmtree(iconset, ignore_errors=True)
    iconset.mkdir(parents=True, exist_ok=True)
    source = root / manifest["native"]["macosSource"]
    for size in (16, 32, 128, 256, 512):
        resize_png(source, iconset / f"icon_{size}x{size}.png", size, False, manifest)
        resize_png(source, iconset / f"icon_{size}x{size}@2x.png", size * 2, False, manifest)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)


def export_ios(root: Path, manifest: dict, refresh: bool) -> None:
    directory = root / "native/ios/AreaMatrixAppIcon.appiconset"
    contents = directory / "Contents.json"
    if not refresh and contents.exists():
        return
    directory.mkdir(parents=True, exist_ok=True)
    source = root / manifest["native"]["iosSource"]
    specs = (
        ("iphone", "20x20", "2x", 40), ("iphone", "20x20", "3x", 60),
        ("iphone", "29x29", "2x", 58), ("iphone", "29x29", "3x", 87),
        ("iphone", "40x40", "2x", 80), ("iphone", "40x40", "3x", 120),
        ("iphone", "60x60", "2x", 120), ("iphone", "60x60", "3x", 180),
        ("ipad", "20x20", "1x", 20), ("ipad", "20x20", "2x", 40),
        ("ipad", "29x29", "1x", 29), ("ipad", "29x29", "2x", 58),
        ("ipad", "40x40", "1x", 40), ("ipad", "40x40", "2x", 80),
        ("ipad", "76x76", "1x", 76), ("ipad", "76x76", "2x", 152),
        ("ipad", "83.5x83.5", "2x", 167), ("ios-marketing", "1024x1024", "1x", 1024),
    )
    images = []
    for idiom, size, scale, pixels in specs:
        filename = f"areamatrix-{idiom}-{size.replace('.', '_')}-{scale}.png"
        resize_png(source, directory / filename, pixels, False, manifest)
        images.append({"idiom": idiom, "size": size, "scale": scale, "filename": filename})
    contents.write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def export_android(root: Path, manifest: dict, refresh: bool) -> None:
    res = root / "native/android/res"
    drawable = res / "drawable-nodpi"
    values = res / "values"
    mipmap = res / "mipmap-anydpi-v26"
    foreground = drawable / "areamatrix_adaptive_foreground.png"
    if not refresh and foreground.exists():
        return
    for directory in (drawable, values, mipmap):
        directory.mkdir(parents=True, exist_ok=True)
    source = root / manifest["native"]["androidForegroundSource"]
    with Image.open(source) as image:
        symbol = image.convert("RGBA").resize((286, 286), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    canvas.alpha_composite(symbol, (73, 73))
    canvas.save(foreground, optimize=True)
    Image.new("RGB", (432, 432), manifest["native"]["androidBackground"]).save(
        drawable / "areamatrix_adaptive_background.png", optimize=True
    )
    values.joinpath("colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'  <color name="areamatrix_icon_background">{manifest["native"]["androidBackground"]}</color>\n'
        "</resources>\n"
    )
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <background android:drawable="@color/areamatrix_icon_background" />\n'
        '  <foreground android:drawable="@drawable/areamatrix_adaptive_foreground" />\n'
        "</adaptive-icon>\n"
    )
    mipmap.joinpath("ic_launcher.xml").write_text(xml)
    mipmap.joinpath("ic_launcher_round.xml").write_text(xml)


def export_windows(root: Path, manifest: dict, refresh: bool) -> None:
    output = root / "native/windows/AreaMatrix.ico"
    if not refresh and output.exists():
        return
    sizes = [16, 24, 32, 48, 64, 128, 256]
    source = root / manifest["native"]["windowsSource"]
    images = []
    for size in sizes:
        with Image.open(source) as image:
            buffer = io.BytesIO()
            image.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS).save(buffer, format="PNG")
            images.append(buffer.getvalue())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(build_ico(sizes, images))


def export_print(root: Path, manifest: dict, refresh: bool) -> None:
    directory = root / "print"
    directory.mkdir(parents=True, exist_ok=True)
    pairs = (
        ("light-background", root / manifest["native"]["printLightSource"], "#FFFFFF"),
        ("dark-background", root / manifest["native"]["printDarkSource"], manifest["native"]["androidBackground"]),
    )
    for label, source, background in pairs:
        svg = directory / f"areamatrix-logo-{label}.svg"
        pdf = directory / f"areamatrix-logo-{label}.pdf"
        tiff = directory / f"areamatrix-logo-{label}-cmyk.tiff"
        shutil.copyfile(source, svg)
        if refresh or not pdf.exists():
            with tempfile.TemporaryDirectory(prefix="areamatrix-print-pdf-") as temporary:
                composite = Path(temporary) / "print.svg"
                content = source.read_text(encoding="utf-8")
                content = re.sub(
                    r"(<svg\b[^>]*>)",
                    rf'\1<rect width="1600" height="520" fill="{background}"/>',
                    content,
                    count=1,
                )
                composite.write_text(content, encoding="utf-8")
                subprocess.run(
                    ["sips", "-s", "format", "pdf", str(composite), "--out", str(pdf)],
                    check=True,
                    stdout=subprocess.DEVNULL,
                )
        if refresh or not tiff.exists():
            with tempfile.TemporaryDirectory(prefix="areamatrix-print-") as temporary:
                png = Path(temporary) / "print.png"
                render_svg(source, png, 3600, 1170, True, manifest)
                with Image.open(png) as image:
                    rgba = image.convert("RGBA")
                    flattened = Image.new("RGB", rgba.size, background)
                    flattened.paste(rgba, mask=rgba.getchannel("A"))
                    dpi = manifest["native"]["printDpi"]
                    flattened.convert("CMYK").save(tiff, compression="tiff_lzw", dpi=(dpi, dpi))


def export_overview(root: Path, manifest: dict, refresh: bool) -> None:
    spec = manifest["overview"]
    output = root / spec["output"]
    if not refresh and output.exists():
        return
    canvas = Image.new("RGB", (spec["width"], spec["height"]), "#EEF7F3")
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 0, 1600, 126), fill="#0A201E")
    font = ImageFont.load_default(size=48)
    small = ImageFont.load_default(size=22)
    draw.text((62, 38), "AreaMatrix Brand System", fill="#F4FBF8", font=font)
    draw.text((1230, 52), "DIGITAL ASSET KIT", fill="#76DCCB", font=small)
    panels = ((50, 160, 750, 410, "#FFFFFF"), (800, 160, 1550, 410, "#0A201E"),
              (50, 450, 1010, 720, "#FFFFFF"), (1050, 450, 1550, 720, "#0A201E"),
              (50, 760, 750, 1140, "#FFFFFF"), (800, 760, 1550, 1140, "#0A201E"))
    for x1, y1, x2, y2, color in panels:
        draw.rounded_rectangle((x1, y1, x2, y2), radius=8, fill=color)
    draw.rounded_rectangle((90, 815, 390, 1120), radius=8, fill="#0A201E")
    composites = (
        ("app-icon/areamatrix-app-icon-light-256.png", (90, 225), (160, 160)),
        ("app-icon/areamatrix-app-icon-dark-256.png", (280, 225), (160, 160)),
        ("symbol/areamatrix-logo-symbol-dark-256.png", (500, 235), (140, 140)),
        ("symbol/areamatrix-logo-symbol-light-256.png", (990, 235), (140, 140)),
        ("app-icon/areamatrix-app-icon-dark-256.png", (1190, 225), (160, 160)),
        ("lockup/areamatrix-logo-lockup-light-1600x520.png", (260, 520), (620, 202)),
        ("lockup/areamatrix-logo-lockup-mono-light-1600x520.png", (1100, 550), (390, 127)),
        ("stacked/areamatrix-logo-stacked-dark-1024.png", (120, 850), (260, 260)),
        ("stacked/areamatrix-logo-stacked-light-1024.png", (430, 850), (260, 260)),
        ("social/areamatrix-social-preview-dark.png", (920, 850), (520, 273)),
    )
    for relative, position, size in composites:
        with Image.open(root / relative) as image:
            item = image.convert("RGBA")
            item.thumbnail(size, Image.Resampling.LANCZOS)
            canvas.paste(item, position, item)
    canvas.save(output, optimize=True)


def resize_png(source: Path, output: Path, size: int, alpha: bool, manifest: dict) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        image = image.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
        if not alpha:
            background = Image.new("RGB", image.size, manifest["native"]["androidBackground"])
            background.paste(image, mask=image.getchannel("A"))
            image = background
        image.save(output, format="PNG", optimize=True)


def sync_runtime_copies(root: Path, manifest: dict) -> None:
    for item in manifest["runtimeCopies"]:
        output = ROOT / item["output"]
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / item["source"], output)


def png_bytes(path: Path) -> bytes:
    return path.read_bytes()


def build_ico(sizes: list[int], images: list[bytes]) -> bytes:
    offset = 6 + len(sizes) * 16
    entries = []
    if len(sizes) != len(images):
        raise ValueError("ICO sizes and images must have the same length")
    for size, image in zip(sizes, images):
        dimension = 0 if size == 256 else size
        entries.append(struct.pack("<BBBBHHII", dimension, dimension, 0, 0, 1, 32, len(image), offset))
        offset += len(image)
    return struct.pack("<HHH", 0, 1, len(sizes)) + b"".join(entries) + b"".join(images)


if __name__ == "__main__":
    raise SystemExit(main())
