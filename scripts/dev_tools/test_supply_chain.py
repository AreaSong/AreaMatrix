"""Regression tests for artifact-specific supply-chain materials."""

from __future__ import annotations

import json
import base64
import os
import shutil
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

from scripts.dev_tools import supply_chain


class SupplyChainTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.artifacts = self.root / "artifacts"
        self.bundle = self.root / "bundle"
        self.artifacts.mkdir()
        (self.artifacts / "AreaMatrix.dmg").write_bytes(b"release-artifact")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_rejects_path_traversal(self) -> None:
        outside = self.root / "outside.dmg"
        outside.write_bytes(b"outside")

        with self.assertRaises(supply_chain.SupplyChainError):
            supply_chain.safe_relative_path(self.artifacts, "../outside.dmg")

    def test_rejects_in_tree_symlink_before_resolution(self) -> None:
        target = self.artifacts / "AreaMatrix.dmg"
        alias = self.artifacts / "alias.dmg"
        try:
            os.symlink(target, alias)
        except (NotImplementedError, OSError):
            self.skipTest("symbolic links are unavailable on this platform")

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "symlink"):
            supply_chain.safe_relative_path(self.artifacts, "alias.dmg")

    def test_license_root_symlink_is_rejected(self) -> None:
        licenses = self.root / "licenses"
        target = self.root / "license-target"
        target.mkdir()
        (target / "MIT.txt").write_text("MIT", encoding="utf-8")
        try:
            os.symlink(target, licenses)
        except (NotImplementedError, OSError):
            self.skipTest("symbolic links are unavailable on this platform")

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "license directory"):
            supply_chain.license_material_paths(self.root)

    def test_generate_rejects_non_empty_output_directory(self) -> None:
        (self.bundle / "stale.txt").parent.mkdir(parents=True)
        (self.bundle / "stale.txt").write_text("stale", encoding="utf-8")
        args = self._generate_args()

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "must be empty"):
            supply_chain.generate_bundle(args)

    def test_generate_binds_materials_to_artifact_hash(self) -> None:
        component = self._component()
        args = self._generate_args()

        with patch.object(supply_chain, "cargo_components", return_value=[component]), patch.object(
            supply_chain, "load_brand_provenance", return_value=({}, "a" * 64)
        ), patch.object(supply_chain, "repository_source", return_value="https://example.invalid/repo@commit"), patch.object(
            supply_chain, "generated_at", return_value="2026-08-21T00:00:00Z"
        ):
            result = supply_chain.generate_bundle(args)

        self.assertEqual(result, 0)
        manifest = json.loads((self.bundle / "release-manifest.json").read_text())
        self.assertEqual(manifest["artifact"]["sha256"], supply_chain.sha256_file(self.artifacts / "AreaMatrix.dmg"))
        self.assertEqual(manifest["status"], supply_chain.EVIDENCE_STATUS)
        self.assertEqual(manifest["inventoryBasis"], supply_chain.INVENTORY_BASIS)
        self.assertEqual(manifest["limitations"], supply_chain.EVIDENCE_LIMITATIONS)
        self.assertEqual(manifest["licenseMaterials"], sorted(manifest["licenseMaterials"]))
        self.assertTrue(manifest["licenseMaterials"])
        for name, digest in manifest["materials"].items():
            self.assertEqual(supply_chain.sha256_file(self.bundle / name), digest)
        sbom = json.loads((self.bundle / "sbom.cdx.json").read_text())
        self.assertEqual(sbom["metadata"]["component"]["hashes"][0]["content"], manifest["artifact"]["sha256"])
        properties = {item["name"]: item["value"] for item in sbom["metadata"]["properties"]}
        self.assertEqual(properties["areamatrix:inventoryBasis"], supply_chain.INVENTORY_BASIS)
        source_offer = json.loads((self.bundle / "source-offer.json").read_text())
        self.assertEqual(source_offer["limitations"], supply_chain.EVIDENCE_LIMITATIONS)

    def test_native_release_gate_ignores_unrelated_targets(self) -> None:
        supply_chain.validate_native_release_targets(self.root, ["aarch64-apple-darwin"])

    def test_native_release_gate_rejects_repository_placeholder_manifests(self) -> None:
        with self.assertRaisesRegex(supply_chain.SupplyChainError, "not approved"):
            supply_chain.validate_native_release_targets(
                supply_chain.ROOT,
                ["x86_64-pc-windows-msvc"],
            )
        with self.assertRaisesRegex(supply_chain.SupplyChainError, "not approved"):
            supply_chain.validate_native_release_targets(
                supply_chain.ROOT,
                ["x86_64-unknown-linux-gnu"],
            )

    def test_native_release_gate_binds_manifest_sbom_and_binary_hash(self) -> None:
        app = self.root / "apps/windows/AreaMatrix"
        binary = app / "runtimes/win-x64/native/area_matrix_core.dll"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"verified Windows native core")
        (self.root / "LICENSE").write_text("test license", encoding="utf-8")
        (app / "native-core.sbom.cdx.json").write_text("{}\n", encoding="utf-8")
        commit = "a" * 40
        manifest = {
            "schemaVersion": 1,
            "status": "approved",
            "sourceCommit": commit,
            "buildCommand": "cargo build --locked --target x86_64-pc-windows-msvc",
            "license": "../../../LICENSE",
            "sbom": "native-core.sbom.cdx.json",
            "artifacts": [
                {
                    "rid": "win-x64",
                    "architecture": "x64",
                    "fileName": "area_matrix_core.dll",
                    "sha256": supply_chain.sha256_file(binary),
                }
            ],
        }
        (app / "native-core.manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

        with patch.object(supply_chain, "command_output", return_value=commit):
            supply_chain.validate_native_release_targets(
                self.root,
                ["x86_64-pc-windows-msvc"],
            )

            binary.write_bytes(b"tampered Windows native core")
            with self.assertRaisesRegex(supply_chain.SupplyChainError, "hash-mismatched"):
                supply_chain.validate_native_release_targets(
                    self.root,
                    ["x86_64-pc-windows-msvc"],
                )

    def test_nuget_components_bind_lock_hash_and_target_groups(self) -> None:
        lock = self.root / "apps/windows/AreaMatrix/packages.lock.json"
        lock.parent.mkdir(parents=True)
        content_hash = base64.b64encode(b"n" * 64).decode("ascii")
        lock.write_text(
            json.dumps(
                {
                    "version": 1,
                    "dependencies": {
                        "net9.0-windows": {
                            "Example.Package": {
                                "type": "Direct",
                                "resolved": "1.2.3",
                                "contentHash": content_hash,
                            }
                        },
                        "net9.0-windows/win-x64": {
                            "Example.Package": {
                                "type": "Transitive",
                                "resolved": "1.2.3",
                                "contentHash": content_hash,
                            }
                        },
                    },
                }
            ),
            encoding="utf-8",
        )

        components = supply_chain.nuget_components(self.root)

        self.assertEqual(len(components), 1)
        component = components[0]
        self.assertEqual(component["purl"], "pkg:nuget/Example.Package@1.2.3")
        self.assertEqual(component["licenses"], [{"expression": "NOASSERTION"}])
        self.assertEqual(component["hashes"], [{"alg": "SHA-512", "content": (b"n" * 64).hex()}])
        properties = {item["name"]: item["value"] for item in component["properties"]}
        self.assertEqual(properties["areamatrix:dependencyTypes"], "Direct,Transitive")
        self.assertEqual(
            properties["areamatrix:targetFrameworks"],
            "net9.0-windows,net9.0-windows/win-x64",
        )

    def test_nuget_components_reject_target_group_hash_drift(self) -> None:
        lock = self.root / "apps/windows/AreaMatrix/packages.lock.json"
        lock.parent.mkdir(parents=True)
        lock.write_text(
            json.dumps(
                {
                    "version": 1,
                    "dependencies": {
                        "net9.0-windows": {
                            "Example.Package": {
                                "type": "Direct",
                                "resolved": "1.2.3",
                                "contentHash": base64.b64encode(b"a" * 64).decode("ascii"),
                            }
                        },
                        "net9.0-windows/win-x64": {
                            "Example.Package": {
                                "type": "Transitive",
                                "resolved": "1.2.3",
                                "contentHash": base64.b64encode(b"b" * 64).decode("ascii"),
                            }
                        },
                    },
                }
            ),
            encoding="utf-8",
        )

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "lock drift"):
            supply_chain.nuget_components(self.root)

    def test_release_components_include_nuget_only_for_windows_targets(self) -> None:
        cargo = self._component()
        nuget = dict(cargo, purl="pkg:nuget/example@1.0.0")
        with patch.object(supply_chain, "cargo_components", return_value=[cargo]), patch.object(
            supply_chain, "nuget_components", return_value=[nuget]
        ) as mocked_nuget:
            apple = supply_chain.release_components(self.root, ["aarch64-apple-darwin"])
            windows = supply_chain.release_components(self.root, ["x86_64-pc-windows-msvc"])

        self.assertEqual(apple, [cargo])
        self.assertEqual(windows, [cargo, nuget])
        mocked_nuget.assert_called_once_with(self.root)

    def test_verify_rejects_unlisted_bundle_material(self) -> None:
        component = self._component()
        args = self._generate_args()
        with patch.object(supply_chain, "cargo_components", return_value=[component]), patch.object(
            supply_chain, "load_brand_provenance", return_value=({}, "a" * 64)
        ), patch.object(supply_chain, "repository_source", return_value="https://example.invalid/repo@commit"), patch.object(
            supply_chain, "generated_at", return_value="2026-08-21T00:00:00Z"
        ):
            supply_chain.generate_bundle(args)

        (self.bundle / "unexpected.txt").write_text("unbound", encoding="utf-8")
        manifest = json.loads((self.bundle / "release-manifest.json").read_text(encoding="utf-8"))
        review_root = self.root / "review"
        review_root.mkdir()
        review = self._review(manifest)
        (review_root / "review.json").write_text(json.dumps(review), encoding="utf-8")
        verify_args = Namespace(
            bundle_dir=str(self.bundle),
            artifact_root=str(self.artifacts),
            artifact_relative="AreaMatrix.dmg",
            review_record_root=str(review_root),
            review_record_relative="review.json",
        )

        with patch.object(supply_chain, "load_brand_provenance", return_value=({}, "a" * 64)):
            with self.assertRaisesRegex(supply_chain.SupplyChainError, "inventory"):
                supply_chain.verify_bundle(verify_args)

    def test_verify_rejects_license_material_hash_drift(self) -> None:
        component = self._component()
        args = self._generate_args()
        with patch.object(supply_chain, "cargo_components", return_value=[component]), patch.object(
            supply_chain, "load_brand_provenance", return_value=({}, "a" * 64)
        ), patch.object(supply_chain, "repository_source", return_value="https://example.invalid/repo@commit"), patch.object(
            supply_chain, "generated_at", return_value="2026-08-21T00:00:00Z"
        ):
            supply_chain.generate_bundle(args)

        license_path = self.bundle / "licenses/OFL-1.1-Inter.txt"
        license_path.write_text("tampered", encoding="utf-8")
        manifest = json.loads((self.bundle / "release-manifest.json").read_text(encoding="utf-8"))
        review_root = self.root / "review"
        review_root.mkdir()
        (review_root / "review.json").write_text(json.dumps(self._review(manifest)), encoding="utf-8")
        verify_args = Namespace(
            bundle_dir=str(self.bundle),
            artifact_root=str(self.artifacts),
            artifact_relative="AreaMatrix.dmg",
            review_record_root=str(review_root),
            review_record_relative="review.json",
        )

        with patch.object(supply_chain, "load_brand_provenance", return_value=({}, "a" * 64)):
            with self.assertRaisesRegex(supply_chain.SupplyChainError, "material hash mismatch"):
                supply_chain.verify_bundle(verify_args)

    def test_verify_rejects_bundle_symlink(self) -> None:
        component = self._component()
        args = self._generate_args()
        with patch.object(supply_chain, "cargo_components", return_value=[component]), patch.object(
            supply_chain, "load_brand_provenance", return_value=({}, "a" * 64)
        ), patch.object(supply_chain, "repository_source", return_value="https://example.invalid/repo@commit"), patch.object(
            supply_chain, "generated_at", return_value="2026-08-21T00:00:00Z"
        ):
            supply_chain.generate_bundle(args)

        try:
            os.symlink(self.artifacts / "AreaMatrix.dmg", self.bundle / "unexpected-link")
        except (NotImplementedError, OSError):
            self.skipTest("symbolic links are unavailable on this platform")
        with self.assertRaisesRegex(supply_chain.SupplyChainError, "symlink"):
            supply_chain.bundle_inventory(self.bundle)

    def test_brand_provenance_rejects_tampered_inter_input_hash(self) -> None:
        brand_root = self.root / "assets/brand"
        shutil.copytree(supply_chain.ROOT / "assets/brand", brand_root)
        shutil.copytree(supply_chain.ROOT / "licenses", self.root / "licenses")
        provenance_path = brand_root / "provenance.json"
        provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
        provenance["wordmarkInput"]["sha256"] = "0" * 64
        provenance_path.write_text(json.dumps(provenance), encoding="utf-8")

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "input hash"):
            supply_chain.load_brand_provenance(self.root)

    def test_brand_provenance_rejects_unapproved_inter_source_coordinates(self) -> None:
        brand_root = self.root / "assets/brand"
        shutil.copytree(supply_chain.ROOT / "assets/brand", brand_root)
        shutil.copytree(supply_chain.ROOT / "licenses", self.root / "licenses")
        provenance_path = brand_root / "provenance.json"
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

                with self.assertRaisesRegex(supply_chain.SupplyChainError, "source"):
                    supply_chain.load_brand_provenance(self.root)

    def test_release_workflows_use_trusted_main_and_fail_closed_pipelines(self) -> None:
        remote = (supply_chain.ROOT / ".github/workflows/remote-governance.yml").read_text(encoding="utf-8")
        evidence = (supply_chain.ROOT / ".github/workflows/release-evidence.yml").read_text(encoding="utf-8")
        supply_chain_workflow = (supply_chain.ROOT / ".github/workflows/release-supply-chain.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("EXPECTED_REF: refs/heads/main", remote)
        self.assertIn("ref: refs/heads/main", remote)
        self.assertIn("AUDIT_BRANCH: main", remote)
        self.assertNotIn("github.event.inputs.branch", remote)
        self.assertNotIn("\n      GH_TOKEN: ${{ github.token }}\n", remote)
        self.assertIn("          GH_TOKEN: ${{ github.token }}", remote)
        self.assertIn("set -euo pipefail", remote)
        self.assertIn("set -euo pipefail", evidence)
        self.assertIn("ref: ${{ github.sha }}", evidence)
        self.assertIn('test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', evidence)
        self.assertIn("set -euo pipefail\n          ./dev release evidence-audit", evidence)
        self.assertIn("set -euo pipefail\n          ./dev release status", evidence)
        self.assertIn(
            "expected_artifact_url=\"https://github.com/AreaSong/AreaMatrix/releases/download/"
            "$RELEASE_ID/$ARTIFACT_FILENAME\"",
            supply_chain_workflow,
        )
        self.assertIn("--proto-redir '=https'", supply_chain_workflow)
        self.assertIn("jobs:\n  ref-gate:", supply_chain_workflow)
        self.assertIn("    if: github.ref == 'refs/heads/main'", supply_chain_workflow)
        self.assertIn("ref: ${{ github.sha }}", supply_chain_workflow)
        self.assertIn(
            'test "$(git rev-parse HEAD)" = "$GITHUB_SHA"', supply_chain_workflow
        )

    def test_pending_review_fails_closed(self) -> None:
        manifest = self._manifest()
        review = self._review(manifest, status="pending")

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "not approved"):
            supply_chain.verify_review(review, manifest, self._manifest_sha256())

    def test_review_hash_mismatch_fails_closed(self) -> None:
        manifest = self._manifest()
        review = self._review(manifest)
        review["artifactSha256"] = "0" * 64

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "artifact hash"):
            supply_chain.verify_review(review, manifest, self._manifest_sha256())

    def test_review_manifest_hash_mismatch_fails_closed(self) -> None:
        manifest = self._manifest()
        review = self._review(manifest)

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "manifest hash"):
            supply_chain.verify_review(review, manifest, "0" * 64)

    def test_review_scope_must_be_exact(self) -> None:
        manifest = self._manifest()
        review = self._review(manifest)
        review["scope"] = ["licenses", "notices", "source-offer", "package-inspection"]

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "scope must be exactly"):
            supply_chain.verify_review(review, manifest, self._manifest_sha256())

    def test_review_cannot_predate_generated_materials(self) -> None:
        manifest = self._manifest()
        review = self._review(manifest)
        review["reviewedAt"] = "2026-08-20T23:59:59Z"

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "predates"):
            supply_chain.verify_review(review, manifest, self._manifest_sha256())

    def test_review_evidence_url_must_use_https(self) -> None:
        manifest = self._manifest()
        review = self._review(manifest)
        review["evidenceUrl"] = "http://example.invalid/review/1"

        with self.assertRaisesRegex(supply_chain.SupplyChainError, "HTTPS"):
            supply_chain.verify_review(review, manifest, self._manifest_sha256())

    def test_matching_external_review_can_open_gate(self) -> None:
        manifest = self._manifest()

        supply_chain.verify_review(self._review(manifest), manifest, self._manifest_sha256())

    def test_brand_provenance_drift_fails_closed(self) -> None:
        manifest = self._manifest()
        manifest["brandProvenanceSha256"] = "a" * 64

        with patch.object(supply_chain, "load_brand_provenance", return_value=({}, "b" * 64)):
            with self.assertRaisesRegex(supply_chain.SupplyChainError, "brand provenance"):
                supply_chain.verify_brand_provenance(manifest)

    def _generate_args(self) -> Namespace:
        return Namespace(
            artifact_root=str(self.artifacts),
            artifact_relative="AreaMatrix.dmg",
            output_dir=str(self.bundle),
            release="v1.2.3",
            cargo_target=["aarch64-apple-darwin"],
            expected_artifact_sha256=None,
        )

    @staticmethod
    def _component() -> dict[str, object]:
        return {
            "type": "library",
            "name": "example",
            "version": "1.0.0",
            "licenses": [{"expression": "MIT"}],
            "purl": "pkg:cargo/example@1.0.0",
            "externalReferences": [{"type": "distribution", "url": "registry+https://example.invalid"}],
        }

    @staticmethod
    def _manifest() -> dict[str, object]:
        return {
            "schemaVersion": 1,
            "release": "v1.2.3",
            "generatedAt": "2026-08-21T00:00:00Z",
            "artifact": {"sha256": "a" * 64},
        }

    @staticmethod
    def _manifest_sha256() -> str:
        return "b" * 64

    @staticmethod
    def _review(manifest: dict[str, object], *, status: str = "approved") -> dict[str, object]:
        artifact = manifest["artifact"]
        assert isinstance(artifact, dict)
        return {
            "status": status,
            "artifactSha256": artifact["sha256"],
            "manifestSha256": SupplyChainTest._manifest_sha256(),
            "release": manifest["release"],
            "scope": ["licenses", "notices", "source-offer"],
            "reviewer": "qualified-reviewer@example.com",
            "reviewedAt": "2026-08-21T00:00:00Z",
            "evidenceUrl": "https://example.invalid/review/1",
        }


if __name__ == "__main__":
    unittest.main()
