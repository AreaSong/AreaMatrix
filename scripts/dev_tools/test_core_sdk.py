"""Regression tests for the fingerprinted Apple CoreSDK builder."""

from __future__ import annotations

import io
import json
import os
import plistlib
import re
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools import core_sdk
from scripts.dev_tools.common import ToolError


class CoreSDKTest(unittest.TestCase):
    def write_artifact(self, root: Path, fingerprint: str) -> Path:
        artifact = root / ".build/core-sdk" / fingerprint
        (artifact / "Sources/AreaMatrixCoreSDK").mkdir(parents=True)
        (artifact / "Sources/AreaMatrixCoreSDK/area_matrix.swift").write_text(
            "// binding\n", encoding="utf-8"
        )
        (artifact / "Package.swift").write_text("// package\n", encoding="utf-8")
        (artifact / "manifest.json").write_text(
            json.dumps(
                {
                    "schema_version": core_sdk.CORE_SDK_SCHEMA_VERSION,
                    "fingerprint": fingerprint,
                    "xcframework": core_sdk.CORE_SDK_NAME,
                }
            ),
            encoding="utf-8",
        )
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
        return artifact

    def test_fingerprint_changes_when_core_source_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "core/src/lib.rs"
            source.parent.mkdir(parents=True)
            source.write_text("pub fn value() -> u8 { 1 }\n", encoding="utf-8")
            with (
                patch("scripts.dev_tools.core_sdk._sdk_input_files", return_value=[source]),
                patch("scripts.dev_tools.core_sdk._capture_version", return_value="tool-version"),
            ):
                first, _ = core_sdk.core_sdk_fingerprint(root)
                source.write_text("pub fn value() -> u8 { 2 }\n", encoding="utf-8")
                second, _ = core_sdk.core_sdk_fingerprint(root)

            self.assertNotEqual(first, second)

    def test_generated_package_imports_binary_c_module(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            generated = root / "Generated"
            generated.mkdir()
            (generated / "area_matrix.swift").write_text(
                "#if canImport(area_matrixFFI)\nimport area_matrixFFI\n#endif\n",
                encoding="utf-8",
            )
            package = root / "Package"

            core_sdk._write_package(package, generated)

            source = (package / "Sources/AreaMatrixCoreSDK/area_matrix.swift").read_text(encoding="utf-8")
            manifest = (package / "Package.swift").read_text(encoding="utf-8")
            self.assertIn("import Carea_matrixFFI", source)
            self.assertIn('.binaryTarget(name: "Carea_matrixFFI"', manifest)

    def test_generated_package_uses_requested_deployment_targets(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            generated = root / "Generated"
            generated.mkdir()
            (generated / "area_matrix.swift").write_text("// binding\n", encoding="utf-8")

            core_sdk._write_package(
                root / "Package",
                generated,
                macos_deployment_target="15.0",
                ios_deployment_target="18.0",
            )

            manifest = (root / "Package/Package.swift").read_text(encoding="utf-8")
            self.assertIn('.macOS("15.0")', manifest)
            self.assertIn('.iOS("18.0")', manifest)

    def test_cache_hit_publishes_stable_package_and_ios_pointers(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "a" * 64
            artifact = self.write_artifact(root, fingerprint)

            with (
                patch("scripts.dev_tools.core_sdk.require_command"),
                patch(
                    "scripts.dev_tools.core_sdk.core_sdk_fingerprint",
                    return_value=(fingerprint, {}),
                ),
            ):
                dependency_file = root / ".build/derived/CoreSDK.d"
                output = io.StringIO()
                with redirect_stdout(output):
                    self.assertEqual(
                        core_sdk.run_core_sdk_build(root, dependency_file=dependency_file),
                        0,
                    )

            self.assertEqual((root / ".build/core-sdk/current").resolve(), artifact.resolve())
            self.assertEqual((root / "apps/ios/.core-sdk").resolve(), artifact.resolve())
            self.assertIn("core/Cargo.toml", dependency_file.read_text(encoding="utf-8"))
            self.assertRegex(
                output.getvalue(),
                re.compile(
                    r"CoreSDK metrics: status=0 cache=hit cargo_lane=sdk "
                    r"lock_wait_seconds=0\.000 duration_seconds=\d+\.\d{3}"
                ),
            )

    def test_cache_miss_failure_reports_standard_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            output = io.StringIO()
            with (
                patch(
                    "scripts.dev_tools.core_sdk._run_core_sdk_build_inner",
                    return_value=(65, "miss", 0.125),
                ),
                redirect_stdout(output),
            ):
                self.assertEqual(core_sdk.run_core_sdk_build(Path(temp)), 65)

            self.assertRegex(
                output.getvalue(),
                re.compile(
                    r"CoreSDK metrics: status=65 cache=miss cargo_lane=sdk "
                    r"lock_wait_seconds=0\.125 duration_seconds=\d+\.\d{3}"
                ),
            )

    def test_unexpected_builder_error_reports_error_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            output = io.StringIO()
            with (
                patch(
                    "scripts.dev_tools.core_sdk._run_core_sdk_build_inner",
                    side_effect=RuntimeError("builder failed"),
                ),
                redirect_stdout(output),
                self.assertRaises(RuntimeError),
            ):
                core_sdk.run_core_sdk_build(Path(temp))

            self.assertRegex(
                output.getvalue(),
                re.compile(
                    r"CoreSDK metrics: status=error cache=unknown cargo_lane=sdk "
                    r"lock_wait_seconds=0\.000 duration_seconds=\d+\.\d{3}"
                ),
            )

    def test_cache_miss_rechecks_under_lock_and_reports_hit_after_wait(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "d" * 64
            self.write_artifact(root, fingerprint)
            with (
                patch("scripts.dev_tools.core_sdk.require_command"),
                patch(
                    "scripts.dev_tools.core_sdk.core_sdk_fingerprint",
                    return_value=(fingerprint, {}),
                ) as fingerprint_call,
                patch(
                    "scripts.dev_tools.core_sdk._sdk_artifact_complete",
                    side_effect=[False, True],
                ),
                patch("scripts.dev_tools.core_sdk.run_core_build") as core_build,
            ):
                result, cache, lock_wait_seconds = core_sdk._run_core_sdk_build_inner(root)

            self.assertEqual((result, cache), (0, "hit-after-wait"))
            self.assertGreaterEqual(lock_wait_seconds, 0)
            self.assertEqual(fingerprint_call.call_count, 2)
            core_build.assert_not_called()

    def test_core_sdk_owns_sdk_lock_without_reentrant_core_build_lock(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "e" * 64
            with (
                patch("scripts.dev_tools.core_sdk.require_command"),
                patch(
                    "scripts.dev_tools.core_sdk.core_sdk_fingerprint",
                    return_value=(fingerprint, {}),
                ),
                patch("scripts.dev_tools.core_sdk._sdk_artifact_complete", return_value=False),
                patch("scripts.dev_tools.core_sdk.run_core_build", return_value=73) as core_build,
            ):
                result, cache, _ = core_sdk._run_core_sdk_build_inner(root)

            self.assertEqual((result, cache), (73, "miss"))
            self.assertFalse(core_build.call_args.kwargs["acquire_cargo_lock"])

    def test_corrupt_manifest_is_not_a_cache_hit(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "b" * 64
            artifact = self.write_artifact(root, fingerprint)
            (artifact / "manifest.json").write_text("{}", encoding="utf-8")

            self.assertFalse(core_sdk._sdk_artifact_complete(artifact, fingerprint))

    def test_xcframework_slice_paths_cannot_escape_the_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "f" * 64
            artifact = self.write_artifact(root, fingerprint)
            info_plist = artifact / core_sdk.CORE_SDK_NAME / "Info.plist"
            with info_plist.open("rb") as handle:
                info = plistlib.load(handle)
            info["AvailableLibraries"][0]["LibraryPath"] = "../../outside.a"
            with info_plist.open("wb") as handle:
                plistlib.dump(info, handle)
            (artifact / "outside.a").write_bytes(b"not-an-xcframework-slice")

            errors = core_sdk._sdk_artifact_errors(artifact, fingerprint)

            self.assertTrue(any("escapes its artifact root" in error for error in errors), errors)

    def test_verify_only_rejects_an_artifact_from_different_sources(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            restored_fingerprint = "a" * 64
            current_fingerprint = "b" * 64
            artifact = self.write_artifact(root, restored_fingerprint)
            (root / ".build/core-sdk/current").symlink_to(
                artifact.relative_to(root / ".build/core-sdk")
            )

            with (
                patch("scripts.dev_tools.core_sdk.require_command"),
                patch(
                    "scripts.dev_tools.core_sdk.core_sdk_fingerprint",
                    return_value=(current_fingerprint, {}),
                ),
                self.assertRaisesRegex(ToolError, "does not match the current source/tool fingerprint"),
            ):
                core_sdk.run_core_sdk_build(root, verify_only=True)

    def test_verify_only_writes_dependency_file_for_xcode_incrementality(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fingerprint = "a" * 64
            artifact = self.write_artifact(root, fingerprint)
            (root / ".build/core-sdk/current").symlink_to(
                artifact.relative_to(root / ".build/core-sdk")
            )
            dependency_file = root / ".build/derived/AreaMatrixCoreSDK.d"

            with (
                patch("scripts.dev_tools.core_sdk.require_command"),
                patch(
                    "scripts.dev_tools.core_sdk.core_sdk_fingerprint",
                    return_value=(fingerprint, {}),
                ),
            ):
                self.assertEqual(
                    core_sdk.run_core_sdk_build(
                        root,
                        dependency_file=dependency_file,
                        verify_only=True,
                    ),
                    0,
                )

            dependency_text = dependency_file.read_text(encoding="utf-8")
            self.assertIn("core/Cargo.toml", dependency_text)
            self.assertIn(".build/core-sdk/current/manifest.json", dependency_text)

    def test_existing_generated_cache_entry_can_be_replaced_atomically(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            destination = root / "cache"
            destination.mkdir()
            (destination / "value").write_text("old", encoding="utf-8")
            staged = root / "staged"
            staged.mkdir()
            (staged / "value").write_text("new", encoding="utf-8")

            core_sdk._replace_artifact_atomically(staged, destination)

            self.assertEqual((destination / "value").read_text(encoding="utf-8"), "new")
            self.assertFalse(staged.exists())
            self.assertEqual(list(root.glob(".*.backup")), [])

    def test_tar_round_trip_preserves_and_validates_current_pointer(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "source"
            restored = Path(temp) / "restored"
            fingerprint = "c" * 64
            artifact = self.write_artifact(root, fingerprint)
            (root / ".build/core-sdk/current").symlink_to(artifact.relative_to(root / ".build/core-sdk"))
            archive = Path(temp) / "core-sdk.tar.gz"
            (restored / ".build").mkdir(parents=True)

            subprocess.run(
                ["tar", "-czf", str(archive), "-C", str(root / ".build"), "core-sdk"],
                check=True,
            )
            subprocess.run(
                ["tar", "-xzf", str(archive), "-C", str(restored / ".build")],
                check=True,
            )

            self.assertEqual(core_sdk.verify_core_sdk_pointer(restored), 0)
            self.assertTrue((restored / ".build/core-sdk/current").is_symlink())

    def test_cache_prune_preview_uses_lru_and_preserves_current(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            oldest = self.write_artifact(root, "1" * 64)
            current = self.write_artifact(root, "2" * 64)
            newest = self.write_artifact(root, "3" * 64)
            (root / ".build/core-sdk/current").symlink_to(current.relative_to(root / ".build/core-sdk"))
            for timestamp, artifact in enumerate((oldest, current, newest), start=1):
                marker = artifact / core_sdk.CORE_SDK_LAST_USED_MARKER
                marker.touch()
                os.utime(marker, (timestamp, timestamp))

            output = io.StringIO()
            with redirect_stdout(output):
                result = core_sdk.run_core_sdk_cache_prune(
                    root,
                    max_bytes=0,
                    keep_recent=1,
                )

            self.assertEqual(result, 0)
            self.assertTrue(oldest.is_dir())
            self.assertTrue(current.is_dir())
            self.assertTrue(newest.is_dir())
            self.assertIn(f"would-remove {oldest.name}", output.getvalue())
            self.assertNotIn(f"would-remove {current.name}", output.getvalue())
            self.assertNotIn(f"would-remove {newest.name}", output.getvalue())

    def test_cache_prune_apply_removes_only_planned_fingerprint_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            removable = self.write_artifact(root, "4" * 64)
            current = self.write_artifact(root, "5" * 64)
            unrelated = root / ".build/core-sdk/manual-notes"
            unrelated.mkdir()
            (root / ".build/core-sdk/current").symlink_to(current.relative_to(root / ".build/core-sdk"))

            result = core_sdk.run_core_sdk_cache_prune(
                root,
                max_bytes=0,
                keep_recent=0,
                apply=True,
            )

            self.assertEqual(result, 0)
            self.assertFalse(removable.exists())
            self.assertTrue(current.is_dir())
            self.assertTrue(unrelated.is_dir())


if __name__ == "__main__":
    unittest.main()
