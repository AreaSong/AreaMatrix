#!/usr/bin/env python3
"""Record per-file provenance for binary brand artifacts and controlled copies."""

from __future__ import annotations

import hashlib
import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any


AUDIT_DIR = Path(__file__).resolve().parent
ROOT = AUDIT_DIR.parents[2]
INVENTORY = AUDIT_DIR / "inventory.jsonl"
GENERATED = AUDIT_DIR / "generated-artifacts.jsonl"
DECISIONS = AUDIT_DIR / "review-decisions.jsonl"
MANIFEST_PATH = ROOT / "assets/brand/brand-manifest.json"
PACKAGE_PREFIX = "assets/brand/final/"
GENERATOR_PATHS = (
    "assets/brand/brand-manifest.json",
    "scripts/brand/assets.py",
    "scripts/brand/export_assets.py",
    "scripts/brand/validate_assets.py",
)


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def input_fingerprint(paths: list[str]) -> str:
    digest = hashlib.sha256()
    for relative in sorted(dict.fromkeys([*paths, *GENERATOR_PATHS])):
        absolute = ROOT / relative
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256(absolute).encode("ascii") if absolute.is_file() else b"MISSING")
        digest.update(b"\n")
    return digest.hexdigest()


def package_path(relative: str) -> str:
    return f"{PACKAGE_PREFIX}{relative}"


def replace_tokens(value: str, theme: str, size: int) -> str:
    return value.replace("{theme}", theme).replace("{size}", str(size))


def add(
    mapping: dict[str, dict[str, Any]],
    path: str,
    sources: list[str],
    producer: str,
    verification: str,
) -> None:
    mapping[path] = {
        "source_paths": sources,
        "producer": producer,
        "verification": verification,
    }


def final_asset_mapping(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    mapping: dict[str, dict[str, Any]] = {}
    verification = "python3 scripts/brand/validate_assets.py (not executed before manual coverage closure)"

    for family in manifest["themedSquareFamilies"]:
        for theme in manifest["themes"]:
            for size in family["sizes"]:
                source_pattern = family["source"]
                if size in family.get("smallSizes", []):
                    source_pattern = family.get("smallSource", source_pattern)
                source = package_path(replace_tokens(source_pattern, theme, size))
                output = package_path(replace_tokens(family["output"], theme, size))
                add(mapping, output, [source], "render_svg/raster_jobs", verification)

    for item in manifest["fixedRasterExports"]:
        add(
            mapping,
            package_path(item["output"]),
            [package_path(item["source"])],
            "render_svg/fixedRasterExports",
            verification,
        )

    favicon = manifest["favicon"]
    favicon_outputs: list[str] = []
    for size in favicon["sizes"]:
        output = package_path(favicon["output"].replace("{size}", str(size)))
        favicon_outputs.append(output)
        add(mapping, output, [package_path(favicon["source"])], "render_svg/favicon", verification)
    add(mapping, package_path(favicon["ico"]), favicon_outputs, "export_favicon/build_ico", verification)

    native = manifest["native"]
    macos_source = package_path(native["macosSource"])
    iconset_outputs: list[str] = []
    for size in (16, 32, 128, 256, 512):
        for suffix, pixels in (("", size), ("@2x", size * 2)):
            output = package_path(f"native/macos/AreaMatrix.iconset/icon_{size}x{size}{suffix}.png")
            iconset_outputs.append(output)
            add(mapping, output, [macos_source], f"export_macos/resize_png({pixels})", verification)
    add(
        mapping,
        package_path("native/macos/AreaMatrix.icns"),
        iconset_outputs,
        "export_macos/iconutil",
        verification,
    )

    ios_source = package_path(native["iosSource"])
    ios_specs = (
        ("iphone", "20x20", "2x"), ("iphone", "20x20", "3x"),
        ("iphone", "29x29", "2x"), ("iphone", "29x29", "3x"),
        ("iphone", "40x40", "2x"), ("iphone", "40x40", "3x"),
        ("iphone", "60x60", "2x"), ("iphone", "60x60", "3x"),
        ("ipad", "20x20", "1x"), ("ipad", "20x20", "2x"),
        ("ipad", "29x29", "1x"), ("ipad", "29x29", "2x"),
        ("ipad", "40x40", "1x"), ("ipad", "40x40", "2x"),
        ("ipad", "76x76", "1x"), ("ipad", "76x76", "2x"),
        ("ipad", "83.5x83.5", "2x"), ("ios-marketing", "1024x1024", "1x"),
    )
    for idiom, size, scale in ios_specs:
        filename = f"areamatrix-{idiom}-{size.replace('.', '_')}-{scale}.png"
        output = package_path(f"native/ios/AreaMatrixAppIcon.appiconset/{filename}")
        add(mapping, output, [ios_source], "export_ios/resize_png", verification)

    android_source = package_path(native["androidForegroundSource"])
    add(
        mapping,
        package_path("native/android/res/drawable-nodpi/areamatrix_adaptive_foreground.png"),
        [android_source],
        "export_android/Pillow composite",
        verification,
    )
    add(
        mapping,
        package_path("native/android/res/drawable-nodpi/areamatrix_adaptive_background.png"),
        ["assets/brand/brand-manifest.json#native.androidBackground"],
        "export_android/Pillow solid background",
        verification,
    )
    add(
        mapping,
        package_path("native/windows/AreaMatrix.ico"),
        [package_path(native["windowsSource"])],
        "export_windows/build_ico",
        verification,
    )

    for label, source_key in (("light-background", "printLightSource"), ("dark-background", "printDarkSource")):
        source = package_path(native[source_key])
        add(mapping, package_path(f"print/areamatrix-logo-{label}.pdf"), [source], "export_print/sips PDF", verification)
        add(
            mapping,
            package_path(f"print/areamatrix-logo-{label}-cmyk.tiff"),
            [source, "assets/brand/brand-manifest.json#native.printDpi"],
            "export_print/Pillow CMYK TIFF",
            verification,
        )

    overview_sources = [
        package_path("app-icon/areamatrix-app-icon-light-256.png"),
        package_path("app-icon/areamatrix-app-icon-dark-256.png"),
        package_path("symbol/areamatrix-logo-symbol-dark-256.png"),
        package_path("symbol/areamatrix-logo-symbol-light-256.png"),
        package_path("lockup/areamatrix-logo-lockup-light-1600x520.png"),
        package_path("lockup/areamatrix-logo-lockup-mono-light-1600x520.png"),
        package_path("stacked/areamatrix-logo-stacked-dark-1024.png"),
        package_path("stacked/areamatrix-logo-stacked-light-1024.png"),
        package_path("social/areamatrix-social-preview-dark.png"),
    ]
    add(
        mapping,
        package_path(manifest["overview"]["output"]),
        overview_sources,
        "export_overview/Pillow composition",
        verification,
    )

    for item in manifest["runtimeCopies"]:
        add(
            mapping,
            item["output"],
            [package_path(item["source"])],
            "sync_runtime_copies/shutil.copyfile",
            verification,
        )
    return mapping


def git_last_change(path: str) -> dict[str, str | None]:
    result = subprocess.run(
        ["git", "log", "-1", "--format=%H%x09%cI", "--", path],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.strip()
    if not result:
        return {"commit": None, "committed_at": None}
    commit, committed_at = result.split("\t", 1)
    return {"commit": commit, "committed_at": committed_at}


def main() -> int:
    inventory = {row["path"]: row for row in read_jsonl(INVENTORY)}
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    mapping = final_asset_mapping(manifest)
    binary_paths = sorted(
        path
        for path, row in inventory.items()
        if row["file_type"] == "binary"
        and (
            path.startswith("assets/brand/")
            or path in {item["output"] for item in manifest["runtimeCopies"]}
        )
    )
    records: list[dict[str, Any]] = []
    decisions = {
        row["path"]: row
        for row in read_jsonl(DECISIONS)
        if row.get("path")
    }
    now = datetime.now().astimezone().isoformat(timespec="seconds")
    generator_sha = sha256(ROOT / "scripts/brand/export_assets.py")

    for path in binary_paths:
        absolute = ROOT / path
        current_sha = sha256(absolute)
        metadata = mapping.get(path)
        if metadata is None and path.startswith("assets/brand/archive/"):
            sibling_svg = str(Path(path).with_suffix(".svg"))
            sources = [sibling_svg] if (ROOT / sibling_svg).is_file() else []
            metadata = {
                "source_paths": sources,
                "producer": "historical design export (original exporter not recorded)",
                "verification": "current SHA-256 and binary inventory only; historical generator unavailable",
            }
            generator = None
            generator_command = None
            limitation = "历史归档未嵌入原始 generator、版本或输入 fingerprint；不得据此声称可重现。"
        elif metadata is not None:
            generator = "scripts/brand/export_assets.py"
            generator_command = "python3 scripts/brand/export_assets.py --refresh"
            limitation = "制品未嵌入 generator version/input fingerprint；本记录仅计算当前快照 fingerprint，未执行重生成。"
        else:
            raise RuntimeError(f"unmapped binary brand artifact: {path}")

        source_paths = metadata["source_paths"]
        fingerprint_paths = [source for source in source_paths if "#" not in source and (ROOT / source).is_file()]
        record = {
            "record_type": "generated_artifact",
            "audit_id": "docs-api-bridge-drift-audit-20260820",
            "path": path,
            "artifact_kind": absolute.suffix.lower().lstrip(".") or "binary",
            "sha256": current_sha,
            "size_bytes": absolute.stat().st_size,
            "source_paths": source_paths,
            "generator": generator,
            "generator_command": generator_command,
            "producer_step": metadata["producer"],
            "generator_version": {"script_sha256": generator_sha} if generator else None,
            "computed_input_fingerprint": input_fingerprint(fingerprint_paths) if generator else None,
            "embedded_input_fingerprint": None,
            "verification_method": metadata["verification"],
            "verification_executed": False,
            "last_git_change": git_last_change(path),
            "provenance_limitations": limitation,
            "line_review_rationale": "二进制无可逐行文本；按用户规则逐项记录来源、生成器、hash、关联输入与验证边界。",
        }
        records.append(record)
        decisions[path] = {
            "path": path,
            "status": "NOT_APPLICABLE",
            "auditor": "root",
            "auditor_role": "binary_provenance_auditor",
            "reviewer": "root",
            "reviewer_role": "audit_owner_recheck",
            "started_at": now,
            "completed_at": now,
            "reviewed_sha256": current_sha,
            "reviewed_line_ranges": [],
            "evidence": [
                f"generated-artifacts.jsonl path={path} 逐项记录 source/generator/hash/verification。",
                f"当前 SHA-256={current_sha}；关联输入={source_paths or ['unrecorded historical source']}。",
            ],
            "notes": f"二进制不适用逐行阅读。{limitation}",
        }

    existing = [row for row in read_jsonl(GENERATED) if row.get("record_type") != "generated_artifact"]
    merged_records = existing + sorted(records, key=lambda row: row["path"])
    GENERATED.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in merged_records),
        encoding="utf-8",
    )
    DECISIONS.write_text(
        "".join(json.dumps(decisions[path], ensure_ascii=False, sort_keys=True) + "\n" for path in sorted(decisions)),
        encoding="utf-8",
    )
    print(json.dumps({"artifact_records": len(records), "decision_total": len(decisions)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
