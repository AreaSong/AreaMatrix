"""Security regression tests for brand image validation."""

from __future__ import annotations

import hashlib
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image

from scripts.brand import validate_assets
from scripts.brand import image_safety


class ValidateAssetsSecurityTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_provenance_fixture(self, archive_items: list[dict[str, str]]) -> dict[str, object]:
        outline = self.root / "assets/brand/wordmark-outlines.json"
        outline.parent.mkdir(parents=True, exist_ok=True)
        outline.write_text("{}\n")
        license_path = self.root / "licenses/OFL-1.1-Inter.txt"
        license_path.parent.mkdir(parents=True, exist_ok=True)
        license_path.write_text("OFL test license\n")
        provenance = {
            "schemaVersion": 1,
            "brand": "AreaMatrix",
            "releaseEligible": False,
            "releasePolicy": {
                "includedRoot": "assets/brand/final",
                "excludedRoots": ["assets/brand/archive"],
            },
            "wordmarkInput": {
                "sha256": validate_assets.EXPECTED_INTER_INPUT_SHA256,
                "source": validate_assets.EXPECTED_INTER_UPSTREAM_SOURCE,
                "upstreamCommit": validate_assets.EXPECTED_INTER_UPSTREAM_COMMIT,
                "sourceArtifact": validate_assets.EXPECTED_INTER_SOURCE_ARTIFACT,
                "licenseFile": "licenses/OFL-1.1-Inter.txt",
                "licenseSha256": hashlib.sha256(license_path.read_bytes()).hexdigest(),
                "outlinePath": "assets/brand/wordmark-outlines.json",
                "outlineSha256": hashlib.sha256(outline.read_bytes()).hexdigest(),
            },
            "archiveAssets": archive_items,
        }
        provenance_path = self.root / "assets/brand/provenance.json"
        provenance_path.write_text(json.dumps(provenance))
        return {
            "provenance": {
                "path": "assets/brand/provenance.json",
                "releaseEligible": False,
                "includedRoot": "assets/brand/final",
                "excludedRoots": ["assets/brand/archive"],
            }
        }

    def create_archive_items(self, count: int = 16) -> list[dict[str, str]]:
        archive = self.root / "assets/brand/archive"
        archive.mkdir(parents=True)
        items = []
        for index in range(count):
            path = archive / f"asset-{index}.svg"
            path.write_text(f"asset-{index}")
            items.append(
                {
                    "path": path.relative_to(self.root).as_posix(),
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                    "status": "evidence-blocked",
                }
            )
        return items

    def test_rejects_disguised_format_before_pillow_decode(self) -> None:
        path = self.root / "disguised.png"
        path.write_bytes(b"8BPS\x00\x01" + b"\x00" * 32)
        errors: list[str] = []

        with patch.object(image_safety.Image, "open") as image_open:
            validate_assets.validate_raster(path, 1, 1, False, errors)

        image_open.assert_not_called()
        self.assertTrue(any("wrong PNG file signature" in error for error in errors))

    def test_rejects_oversized_file_before_pillow_decode(self) -> None:
        path = self.root / "oversized.png"
        with path.open("wb") as handle:
            handle.truncate(validate_assets.MAX_IMAGE_FILE_BYTES + 1)
        errors: list[str] = []

        with patch.object(image_safety.Image, "open") as image_open:
            validate_assets.validate_raster(path, 1, 1, False, errors)

        image_open.assert_not_called()
        self.assertTrue(any("image file too large" in error for error in errors))

    def test_rejects_pixel_bomb_header_before_pillow_decode(self) -> None:
        path = self.root / "pixel-bomb.png"
        header = validate_assets.PNG_MAGIC + struct.pack(">I", 13) + b"IHDR"
        header += struct.pack(">II", 8192, 8193) + b"\x08\x06\x00\x00\x00"
        path.write_bytes(header)
        errors: list[str] = []

        with patch.object(image_safety.Image, "open") as image_open:
            validate_assets.validate_raster(path, 8192, 8193, True, errors)

        image_open.assert_not_called()
        self.assertTrue(any("image pixel limit exceeded" in error for error in errors))

    def test_allows_expected_png_through_restricted_decoder(self) -> None:
        path = self.root / "valid.png"
        Image.new("RGBA", (2, 3), (0, 0, 0, 0)).save(path, format="PNG")
        errors: list[str] = []

        validate_assets.validate_raster(path, 2, 3, True, errors)

        self.assertEqual(errors, [])

    def test_reads_little_endian_tiff_dimensions(self) -> None:
        path = self.root / "valid.tiff"
        Image.new("CMYK", (4, 5), (0, 0, 0, 0)).save(path, format="TIFF", dpi=(300, 300))

        dimensions = validate_assets.image_dimensions(path.read_bytes(), "TIFF")

        self.assertEqual(dimensions, (4, 5))

    def test_validates_complete_blocked_archive_provenance(self) -> None:
        manifest = self.write_provenance_fixture(self.create_archive_items())
        errors: list[str] = []

        with patch.object(validate_assets, "ROOT", self.root):
            validate_assets.validate_provenance(manifest, errors)

        self.assertEqual(errors, [])

    def test_rejects_unapproved_inter_source_coordinates(self) -> None:
        manifest = self.write_provenance_fixture(self.create_archive_items())
        provenance_path = self.root / "assets/brand/provenance.json"
        baseline = json.loads(provenance_path.read_text(encoding="utf-8"))
        mutations = (
            ("source", "https://github.com/example/inter/commit/" + "0" * 40),
            ("upstreamCommit", "0" * 40),
            ("sourceArtifact.owner", "example"),
            ("sourceArtifact.repository", "inter-copy"),
            ("sourceArtifact.commit", "0" * 40),
            ("sourceArtifact.path", "fonts/Inter-Bold.ttf"),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                provenance = json.loads(json.dumps(baseline))
                if field.startswith("sourceArtifact."):
                    provenance["wordmarkInput"]["sourceArtifact"][field.split(".", 1)[1]] = value
                else:
                    provenance["wordmarkInput"][field] = value
                provenance_path.write_text(json.dumps(provenance), encoding="utf-8")
                errors: list[str] = []

                with patch.object(validate_assets, "ROOT", self.root):
                    validate_assets.validate_provenance(manifest, errors)

                self.assertTrue(any("source" in error.lower() for error in errors), errors)

    def test_rejects_archive_path_traversal(self) -> None:
        items = self.create_archive_items()
        items[0]["path"] = "assets/brand/archive/../../../outside.svg"
        manifest = self.write_provenance_fixture(items)
        errors: list[str] = []

        with patch.object(validate_assets, "ROOT", self.root):
            validate_assets.validate_provenance(manifest, errors)

        self.assertTrue(any("invalid archive provenance path" in error for error in errors), errors)

    def test_rejects_archive_symlink_escape(self) -> None:
        items = self.create_archive_items(15)
        outside = self.root / "outside.svg"
        outside.write_text("outside")
        link = self.root / "assets/brand/archive/asset-15.svg"
        try:
            link.symlink_to(outside)
        except OSError as error:
            self.skipTest(f"symlink creation is unavailable: {error}")
        items.append(
            {
                "path": link.relative_to(self.root).as_posix(),
                "sha256": hashlib.sha256(outside.read_bytes()).hexdigest(),
                "status": "evidence-blocked",
            }
        )
        manifest = self.write_provenance_fixture(items)
        errors: list[str] = []

        with patch.object(validate_assets, "ROOT", self.root):
            validate_assets.validate_provenance(manifest, errors)

        self.assertTrue(any("escapes assets/brand/archive" in error for error in errors), errors)

    def test_rejects_release_eligible_brand_provenance(self) -> None:
        errors: list[str] = []
        manifest = {
            "provenance": {
                "path": "assets/brand/provenance.json",
                "releaseEligible": True,
                "includedRoot": "assets/brand/final",
                "excludedRoots": ["assets/brand/archive"],
            }
        }

        validate_assets.validate_provenance(manifest, errors)

        self.assertIn("brand provenance must remain release-ineligible", errors)


if __name__ == "__main__":
    unittest.main()
