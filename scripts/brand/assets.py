"""Shared manifest helpers for AreaMatrix brand assets."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "assets/brand/brand-manifest.json"


@dataclass(frozen=True)
class RasterJob:
    source: str
    output: str
    width: int
    height: int
    alpha: bool


def load_manifest() -> dict[str, Any]:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def package_root(manifest: dict[str, Any]) -> Path:
    return ROOT / manifest["packageRoot"]


def raster_jobs(manifest: dict[str, Any]) -> list[RasterJob]:
    jobs: list[RasterJob] = []
    for family in manifest["themedSquareFamilies"]:
        for theme in manifest["themes"]:
            for size in family["sizes"]:
                source_pattern = family["source"]
                if size in family.get("smallSizes", []):
                    source_pattern = family.get("smallSource", source_pattern)
                jobs.append(
                    RasterJob(
                        source=_replace(source_pattern, theme, size),
                        output=_replace(family["output"], theme, size),
                        width=size,
                        height=size,
                        alpha=family["alpha"],
                    )
                )
    for item in manifest["fixedRasterExports"]:
        jobs.append(RasterJob(**item))
    favicon = manifest["favicon"]
    for size in favicon["sizes"]:
        jobs.append(
            RasterJob(
                source=favicon["source"],
                output=favicon["output"].replace("{size}", str(size)),
                width=size,
                height=size,
                alpha=True,
            )
        )
    return jobs


def _replace(value: str, theme: str, size: int) -> str:
    return value.replace("{theme}", theme).replace("{size}", str(size))
