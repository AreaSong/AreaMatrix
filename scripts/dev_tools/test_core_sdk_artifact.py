"""Security regression tests for immutable CoreSDK artifacts."""

from __future__ import annotations

import json
import os
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools import core_sdk
from scripts.dev_tools.test_core_sdk_support import write_core_sdk_artifact


class CoreSDKArtifactSecurityTest(unittest.TestCase):
    def test_ci_binds_archive_digest_across_producer_and_consumers(self) -> None:
        root = Path(__file__).resolve().parents[2]
        workflow = (root / ".github/workflows/macos-ci.yml").read_text(encoding="utf-8")

        self.assertIn("archive_sha256: ${{ steps.package.outputs.archive_sha256 }}", workflow)
        self.assertEqual(
            workflow.count(
                "CORE_SDK_ARCHIVE_SHA256: ${{ needs.core-sdk.outputs.archive_sha256 }}"
            ),
            2,
        )
        self.assertIn("Verify packaged CoreSDK remained immutable during upload", workflow)
        digest_checks = [
            line
            for line in workflow.splitlines()
            if "core-sdk.tar.gz" in line and "shasum -a 256 --check" in line
        ]
        self.assertEqual(len(digest_checks), 3)

    def test_every_manifest_output_is_content_bound(self) -> None:
        with tempfile.TemporaryDirectory() as baseline_temp:
            baseline = write_core_sdk_artifact(Path(baseline_temp), "9" * 64)
            manifest = json.loads((baseline / "manifest.json").read_text(encoding="utf-8"))
            targets = [record["path"] for record in manifest["outputs"]]

        for relative in targets:
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                fingerprint = "9" * 64
                artifact = write_core_sdk_artifact(root, fingerprint)
                path = artifact / relative
                if relative.endswith("Info.plist"):
                    with path.open("rb") as handle:
                        info = plistlib.load(handle)
                    info["Tampered"] = True
                    with path.open("wb") as handle:
                        plistlib.dump(info, handle)
                else:
                    path.write_bytes(path.read_bytes() + b"tampered")

                errors = core_sdk._sdk_artifact_errors(artifact, fingerprint)

                self.assertIn(f"CoreSDK output SHA-256 mismatch: {relative}", errors)

    def test_unlisted_and_non_required_missing_outputs_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "8" * 64
            artifact = write_core_sdk_artifact(root, fingerprint)
            extra = "Sources/AreaMatrixCoreSDK/injected.swift"
            (artifact / extra).write_text("// injected\n", encoding="utf-8")
            missing = f"{core_sdk.CORE_SDK_NAME}/ios-arm64/Headers/module.modulemap"
            (artifact / missing).unlink()

            errors = core_sdk._sdk_artifact_errors(artifact, fingerprint)

            self.assertIn(f"CoreSDK artifact contains an unlisted output: {extra}", errors)
            self.assertIn(f"CoreSDK manifest references a missing output: {missing}", errors)

    def test_manifest_output_inventory_rejects_unsafe_duplicate_and_invalid_records(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "7" * 64
            artifact = write_core_sdk_artifact(root, fingerprint)
            manifest_path = artifact / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["outputs"] = [
                {"path": "../escape", "sha256": "0" * 64},
                {"path": "Package.swift", "sha256": "invalid"},
                manifest["outputs"][0],
                manifest["outputs"][0],
            ]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            errors = core_sdk._sdk_artifact_errors(artifact, fingerprint)

            self.assertTrue(any("unsafe or mutable" in error for error in errors), errors)
            self.assertTrue(any("invalid SHA-256" in error for error in errors), errors)
            self.assertIn("CoreSDK manifest outputs contain duplicate paths", errors)

    def test_symbolic_hard_and_root_links_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "6" * 64
            artifact = write_core_sdk_artifact(root, fingerprint)
            (artifact / "linked.swift").symlink_to("Package.swift")
            os.link(artifact / "Package.swift", artifact / "hard-linked.swift")

            errors = core_sdk._sdk_artifact_errors(artifact, fingerprint)

            self.assertTrue(any("symbolic link" in error for error in errors), errors)
            self.assertTrue(any("hard-linked file" in error for error in errors), errors)

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "4" * 64
            artifact = write_core_sdk_artifact(root, fingerprint)
            target = root / "outside-artifact"
            artifact.rename(target)
            artifact.symlink_to(target, target_is_directory=True)

            errors = core_sdk._sdk_artifact_errors(artifact, fingerprint)

            self.assertTrue(any("root must be a real directory" in error for error in errors), errors)

    def test_walk_errors_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "3" * 64
            artifact = write_core_sdk_artifact(root, fingerprint)

            def denied_walk(*_args: object, **kwargs: object):
                onerror = kwargs.get("onerror")
                assert callable(onerror)
                onerror(PermissionError("denied"))
                return iter(())

            with patch("scripts.dev_tools.core_sdk_artifact.os.walk", side_effect=denied_walk):
                errors = core_sdk._sdk_artifact_errors(artifact, fingerprint)

            self.assertTrue(any("unable to traverse" in error for error in errors), errors)

    def test_file_replacement_between_inspection_and_open_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "2" * 64
            artifact = write_core_sdk_artifact(root, fingerprint)
            target = artifact / f"{core_sdk.CORE_SDK_NAME}/ios-arm64/Headers/area_matrixFFI.h"
            outside = root / "outside.h"
            outside.write_bytes(target.read_bytes())
            original_open = os.open
            replaced = False

            def swapping_open(path: object, flags: int, *args: object, **kwargs: object) -> int:
                nonlocal replaced
                if Path(path) == target and not replaced:
                    target.unlink()
                    target.symlink_to(outside)
                    replaced = True
                return original_open(path, flags, *args, **kwargs)

            with patch("scripts.dev_tools.core_sdk_artifact.os.open", side_effect=swapping_open):
                errors = core_sdk._sdk_artifact_errors(artifact, fingerprint)

            self.assertTrue(any("without following links" in error for error in errors), errors)

    def test_last_used_marker_must_be_empty(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "5" * 64
            artifact = write_core_sdk_artifact(root, fingerprint)
            marker = artifact / core_sdk.CORE_SDK_LAST_USED_MARKER
            marker.touch()
            self.assertEqual(core_sdk._sdk_artifact_errors(artifact, fingerprint), [])

            marker.write_text("unexpected payload", encoding="utf-8")
            errors = core_sdk._sdk_artifact_errors(artifact, fingerprint)
            self.assertIn("CoreSDK mutable marker must be empty: .last-used", errors)


if __name__ == "__main__":
    unittest.main()
