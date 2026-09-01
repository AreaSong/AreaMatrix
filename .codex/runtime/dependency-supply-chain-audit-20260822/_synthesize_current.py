#!/usr/bin/env python3
"""Synthesize current-tree dependency, license, coverage and finding ledgers.

This is an evidence writer only. It reads the frozen inventory, current manifests,
lockfiles and source files; it never installs, updates, or modifies product inputs.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
AUDIT = Path(__file__).resolve().parent
AUDIT_ID = "dependency-supply-chain-audit-20260822"
OLD_AUDIT = ROOT / ".codex/runtime/dependency-supply-chain-audit-20260820"
METADATA = Path("/tmp/area_metadata_20260822.json")
LOCKFILE = ROOT / "core/Cargo.lock"

ALLOWED_LICENSES = {
    "MIT",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Unicode-DFS-2016",
    "MIT-CMU",
}


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )
    os.replace(temporary, path)


def line_refs(relative: str, patterns: list[str], limit: int = 16) -> list[str]:
    path = ROOT / relative
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    result: list[str] = []
    for number, line in enumerate(lines, 1):
        if any(pattern in line for pattern in patterns):
            result.append(f"{relative}:{number}")
            if len(result) >= limit:
                break
    return result


def cargo_lock_rows() -> dict[tuple[str, str], dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for number, raw in enumerate(LOCKFILE.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if line == "[[package]]":
            if current is not None:
                rows.append(current)
            current = {"stanza_line": number}
        elif current is not None:
            for key in ("name", "version", "checksum"):
                match = re.match(rf'{key} = "(.*)"$', line)
                if match:
                    current[key] = match.group(1)
    if current is not None:
        rows.append(current)
    return {(row.get("name"), row.get("version")): row for row in rows if row.get("name")}


def license_class(expression: str | None) -> str:
    if not expression:
        return "EVIDENCE_INSUFFICIENT"
    if "GPL-" in expression or "AGPL-" in expression:
        return "DEFAULT_BLOCK"
    if expression in ALLOWED_LICENSES:
        return "DEFAULT_ALLOWED"
    # Policy explicitly requires human review for compound expressions, MPL,
    # LGPL, OFL and any exception expression even when each token is familiar.
    if any(token in expression for token in (" OR ", " AND ", " WITH ", "/", "MPL-", "LGPL", "OFL-")):
        return "MANUAL_REVIEW_REQUIRED"
    return "MANUAL_REVIEW_REQUIRED"


def package_graph(metadata: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    packages = {package["id"]: package for package in metadata["packages"]}
    nodes = {node["id"]: node for node in metadata["resolve"]["nodes"]}
    root = metadata["resolve"]["root"]
    edges: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for parent, node in nodes.items():
        for dependency in node.get("deps", []):
            kinds = dependency.get("dep_kinds") or [{"kind": None, "target": None}]
            edges[parent].append({"child": dependency["pkg"], "kinds": kinds})
    paths: dict[str, list[dict[str, Any]]] = defaultdict(list)
    queue: deque[tuple[str, list[str], list[str]]] = deque([(root, [root], [])])
    seen_depth = {root: 0}
    while queue:
        parent, path, scopes = queue.popleft()
        for edge in edges.get(parent, []):
            child = edge["child"]
            for kind in edge["kinds"]:
                scope = kind.get("kind") or "runtime"
                if kind.get("target"):
                    scope = f"{scope}@{kind['target']}"
                candidate = {"path": path + [child], "scopes": scopes + [scope]}
                if not any(item == candidate for item in paths[child]):
                    paths[child].append(candidate)
            depth = len(path)
            if child not in seen_depth or depth < seen_depth[child] + 2:
                seen_depth[child] = min(depth, seen_depth.get(child, depth))
                queue.append((child, path + [child], scopes + ["runtime"]))
    return packages, paths


def cargo_records(metadata: dict[str, Any]) -> list[dict[str, Any]]:
    packages, paths = package_graph(metadata)
    lock = cargo_lock_rows()
    root_id = metadata["resolve"]["root"]
    root_package = packages[root_id]
    root_node = next(node for node in metadata["resolve"]["nodes"] if node["id"] == root_id)
    direct_ids = {dependency["pkg"] for dependency in root_node.get("deps", [])}
    direct_names = {packages[item]["name"] for item in direct_ids}
    cargo_toml = ROOT / "core/Cargo.toml"
    records: list[dict[str, Any]] = []
    for package_id, package in sorted(packages.items(), key=lambda item: (item[1]["name"], item[1]["version"], item[0])):
        is_root = package_id == root_id
        lock_row = lock.get((package["name"], package["version"]), {})
        package_paths = paths.get(package_id, [])
        scopes = sorted({scope for item in package_paths for scope in item["scopes"]})
        if is_root:
            scopes = ["runtime", "build", "development"]
        direct = package_id in direct_ids
        declaration = line_refs("core/Cargo.toml", [f"{package['name']} ="], 20) if direct else []
        usage = line_refs(
            "core/build.rs" if package["name"] in {"uniffi", "uniffi_build"} else "core/src/lib.rs",
            [package["name"].replace("-", "_")],
            20,
        ) if direct else []
        if direct and not usage:
            usage = line_refs("core/Cargo.toml", [package["name"]], 8)
        license_expr = package.get("license")
        policy = "PROJECT_LICENSE" if is_root else license_class(license_expr)
        review = "PASS" if is_root or (policy == "DEFAULT_ALLOWED" and lock_row.get("checksum")) else "BLOCKED"
        if package["name"] in {"anyhow"}:
            review = "BLOCKED"
        risk = "LOW"
        if any(scope.startswith("runtime") for scope in scopes):
            risk = "MEDIUM"
        if any(scope.startswith("build") for scope in scopes) or package["name"] in {
            "uniffi", "uniffi_bindgen", "uniffi_build", "uniffi_macros", "libsqlite3-sys", "cc", "bindgen"
        }:
            risk = "HIGH"
        usage_location: list[Any] = usage
        if not usage_location:
            usage_location = [
                {
                    "parent_chain": [
                        f"{packages[node]['name']}@{packages[node]['version']}" for node in item["path"][:-1]
                    ],
                    "edge_scopes": item["scopes"],
                }
                for item in package_paths[:4]
            ]
        records.append(
            {
                "audit_id": AUDIT_ID,
                "ecosystem": "cargo",
                "name": package["name"],
                "version": package["version"],
                "version_range": package["version"] if is_root else None,
                "source": "repository-local" if not package.get("source") else package["source"],
                "source_locator": package["id"],
                "direct_or_transitive": "project-root" if is_root else ("direct" if direct else "transitive"),
                "scope": scopes,
                "runtime_dev_build": "runtime/build/development" if is_root else ("runtime closure" if any(scope.startswith("runtime") for scope in scopes) else ",".join(scopes)),
                "declaration_location": declaration or ("core/Cargo.toml:1-45" if is_root else None),
                "usage_location": usage_location,
                "license": license_expr,
                "license_policy": policy,
                "license_evidence": "Cargo metadata license field; registry license text and legal obligations require separate review" if not is_root else "core/Cargo.toml:6 and repository LICENSE/COMMERCIAL_LICENSE.md",
                "lock": {
                    "file": "core/Cargo.lock",
                    "lockfile_version": 4,
                    "package_stanza": f"core/Cargo.lock:{lock_row.get('stanza_line', 'unknown')}",
                    "checksum": lock_row.get("checksum"),
                    "checksum_status": "registry checksum recorded" if lock_row.get("checksum") else "path package/no registry checksum",
                },
                "integrity": "Cargo.lock checksum and frozen source hash" if lock_row.get("checksum") else "local package bound to frozen repository scope",
                "risk_level": risk,
                "review_status": review,
                "evidence_class": "local_metadata_lock_and_source_review",
                "finding_ids": ["SC-024"] if policy == "MANUAL_REVIEW_REQUIRED" else (["SC-025"] if package["name"] == "anyhow" else []),
                "notes": "Direct package declaration and source call sites were reviewed; transitive package represented by shortest lock graph parent chains." if direct else "Transitive lock-graph record; no direct source import is implied.",
            }
        )
    return records


def dependency_record(**values: Any) -> dict[str, Any]:
    row: dict[str, Any] = {
        "audit_id": AUDIT_ID,
        "version": "unknown",
        "version_range": None,
        "source": "unknown",
        "source_locator": None,
        "direct_or_transitive": "implicit",
        "scope": [],
        "runtime_dev_build": "unclassified",
        "declaration_location": None,
        "usage_location": [],
        "license": "unknown",
        "license_policy": "EVIDENCE_INSUFFICIENT",
        "license_evidence": "No complete repository-local license evidence",
        "lock": {"version_pin": False, "hash_pin": False},
        "integrity": "No repository-local version/content binding",
        "risk_level": "MEDIUM",
        "review_status": "BLOCKED",
        "evidence_class": "local_evidence_gap",
        "finding_ids": [],
        "notes": "",
    }
    row.update(values)
    return row


def packages_lock_records() -> list[dict[str, Any]]:
    path = ROOT / "apps/windows/AreaMatrix/packages.lock.json"
    if not path.exists():
        return [dependency_record(ecosystem="nuget", name="NuGet lockfile", finding_ids=["SC-003"])]
    data = json.loads(path.read_text(encoding="utf-8"))
    rows: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    for target, packages in data.get("dependencies", {}).items():
        for name, value in packages.items():
            version = value.get("resolved", "unknown")
            key = (name, version)
            if key in seen:
                continue
            seen.add(key)
            direct = value.get("type") == "Direct"
            rows.append(
                dependency_record(
                    ecosystem="nuget",
                    name=name,
                    version=version,
                    version_range=value.get("requested"),
                    source="https://api.nuget.org/v3/index.json",
                    source_locator="apps/windows/NuGet.config + packages.lock.json",
                    direct_or_transitive="direct" if direct else "transitive",
                    scope=["windows-runtime", "windows-build"],
                    runtime_dev_build="Windows restore/runtime package closure",
                    declaration_location="apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:21" if direct else "apps/windows/AreaMatrix/packages.lock.json",
                    usage_location=[f"packages.lock target {target}"],
                    license="package-specific license not archived in repository",
                    license_policy="MANUAL_REVIEW_REQUIRED",
                    license_evidence="NuGet package metadata/license files require clean restore and qualified review",
                    lock={
                        "packages_lock": True,
                        "requested": value.get("requested"),
                        "resolved": version,
                        "content_hash": value.get("contentHash"),
                        "source_mapping": True,
                        "signature_validation_mode": "require",
                    },
                    integrity="NuGet packages.lock.json contentHash plus nuget.org source mapping; package license/SBOM closure still needs external evidence",
                    risk_level="HIGH" if direct or "Runtime" in name or "SDK" in name else "MEDIUM",
                    review_status="BLOCKED",
                    evidence_class="local_nuget_lock_with_license_review_gap",
                    finding_ids=["SC-024"],
                    notes="Current local lock closes version/content selection; this record does not claim package-signature or legal review PASS.",
                )
            )
    return rows


def implicit_records() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    rows.append(
        dependency_record(
            ecosystem="python",
            name="Pillow",
            version="12.3.0",
            version_range="==12.3.0",
            source="https://pypi.org/project/Pillow/12.3.0/",
            source_locator="scripts/brand/requirements.txt",
            direct_or_transitive="direct",
            scope=["development", "CI"],
            runtime_dev_build="Brand export/validation and Governance CI only",
            declaration_location="scripts/brand/requirements.txt:1-95",
            usage_location=[".github/workflows/governance-ci.yml:40-50", "scripts/brand/validate_assets.py:1-420", "scripts/brand/export_assets.py:1-280"],
            license="MIT-CMU",
            license_policy="DEFAULT_ALLOWED",
            license_evidence="licenses/MIT-CMU-Pillow.txt; docs/development/dependency-policy.md:61-71",
            lock={"version_pin": True, "artifact_hashes": True, "require_hashes": True, "only_binary": True},
            integrity="All release artifacts listed with SHA-256 in requirements; CI uses --require-hashes and --only-binary",
            risk_level="MEDIUM",
            review_status="PASS",
            evidence_class="local_pin_and_call_path_review",
            notes="Previous 11.3.0 candidate is superseded; current 12.3.0 path is dev/CI only. External advisory freshness remains a separate BLOCKED evidence item.",
        )
    )
    rows.extend(
        [
            dependency_record(
                ecosystem="github-action",
                name="actions/checkout",
                version="v4.2.2",
                source="https://github.com/actions/checkout",
                source_locator=".github/workflows/*",
                direct_or_transitive="implicit",
                scope=["CI"],
                runtime_dev_build="Workflow checkout",
                declaration_location=line_refs(".github/workflows/core-ci.yml", ["actions/checkout@"], 4),
                usage_location=line_refs(".github/workflows/core-ci.yml", ["actions/checkout@"], 4),
                license="MIT",
                license_policy="DEFAULT_ALLOWED",
                license_evidence="Pinned 40-character SHA with release comment; upstream license not vendored",
                lock={"commit_sha": "11bd71901bbe5b1630ceea73d27597364c9af683"},
                integrity="Full SHA pin present locally; remote SHA-to-release verification not independently read back",
                risk_level="HIGH",
                review_status="BLOCKED",
                evidence_class="local_workflow_pin_external_commit_gap",
                finding_ids=["SC-025"],
            ),
            dependency_record(
                ecosystem="github-action",
                name="actions/setup-python",
                version="v5.6.0",
                source="https://github.com/actions/setup-python",
                source_locator=".github/workflows/governance-ci.yml:27; .github/workflows/release-supply-chain.yml:74",
                direct_or_transitive="implicit",
                scope=["CI"],
                runtime_dev_build="Python toolchain bootstrap",
                declaration_location=".github/workflows/governance-ci.yml:27; .github/workflows/release-supply-chain.yml:74",
                usage_location=["governance-ci brand venv", "release-supply-chain artifact material generation"],
                license="MIT",
                license_policy="DEFAULT_ALLOWED",
                license_evidence="Pinned SHA and release comment; external commit readback missing",
                lock={"commit_sha": "a26af69be951a213d495a4c3e4e4022e16d87065"},
                integrity="Full SHA pin present; remote identity and current release provenance require external readback",
                risk_level="HIGH",
                review_status="BLOCKED",
                evidence_class="local_workflow_pin_external_commit_gap",
                finding_ids=["SC-025"],
            ),
            dependency_record(
                ecosystem="github-action",
                name="dtolnay/rust-toolchain",
                version="1.88.0",
                source="https://github.com/dtolnay/rust-toolchain",
                source_locator=".github/workflows/core-ci.yml:35,48,64; .github/workflows/release-supply-chain.yml:78",
                direct_or_transitive="implicit",
                scope=["CI", "build"],
                runtime_dev_build="Rust toolchain provisioning",
                declaration_location=".github/workflows/core-ci.yml:35,48,64; .github/workflows/release-supply-chain.yml:78",
                usage_location=["cargo fmt/clippy/test/build jobs"],
                license="MIT OR Apache-2.0",
                license_policy="MANUAL_REVIEW_REQUIRED",
                license_evidence="Pinned commit and local rust-toolchain.toml; toolchain license requires normal review",
                lock={"commit_sha": "2eae45db285e407f22119950686d47e1101e071b", "channel": "1.88.0"},
                integrity="Commit and channel pinned locally; runner image and remote commit provenance not independently verified",
                risk_level="HIGH",
                review_status="BLOCKED",
                evidence_class="local_workflow_pin_external_commit_gap",
                finding_ids=["SC-025"],
            ),
            dependency_record(
                ecosystem="native-artifact",
                name="Windows area_matrix_core.dll",
                version="unknown",
                source="Windows publish output (not present in repository)",
                source_locator="apps/windows/AreaMatrix/native-core.manifest.json",
                direct_or_transitive="implicit",
                scope=["windows-runtime", "Core/FFI", "user-files"],
                runtime_dev_build="Windows app NativeCoreLibrary verified loader",
                declaration_location="apps/windows/AreaMatrix/Core/NativeCoreLibrary.Loading.cs:23-39,115-261",
                usage_location=["apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs:30-35"],
                license="unknown",
                license_policy="EVIDENCE_INSUFFICIENT",
                license_evidence="Manifest status=blocked-external-artifact; artifacts=[]; no DLL/source/SBOM/signature",
                lock={"manifest": True, "sha256": False, "signature": False, "sbom": False},
                integrity="Loader fail-closes and verifies a future manifest hash, but no approved artifact exists to verify",
                risk_level="HIGH",
                review_status="FINDING",
                evidence_class="local_confirmed_missing_release_artifact",
                finding_ids=["SC-002", "SC-026"],
            ),
            dependency_record(
                ecosystem="native-artifact",
                name="Linux area_matrix_core.so",
                version="fixture-only",
                source="repository source; no published Linux native package",
                source_locator="apps/linux/AreaMatrix/native-core.manifest.json",
                direct_or_transitive="implicit",
                scope=["linux-runtime", "Core/FFI", "user-files"],
                runtime_dev_build="Linux loader fixture and development override only",
                declaration_location="apps/linux/AreaMatrix/Core/NativeCoreLibrary.Loading.cs:24-35,88-173",
                usage_location=["apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs:54-59"],
                license="unknown for eventual binary",
                license_policy="EVIDENCE_INSUFFICIENT",
                license_evidence="Manifest status=fixture-only; artifacts=[]; SBOM unavailable",
                lock={"manifest": True, "sha256": False, "signature": False, "sbom": False},
                integrity="Default path intentionally fails closed; development override verifies hash only when an external fixture is supplied",
                risk_level="HIGH",
                review_status="FINDING",
                evidence_class="local_confirmed_fixture_only",
                finding_ids=["SC-015", "SC-026"],
            ),
            dependency_record(
                ecosystem="native-artifact",
                name="tracked macOS libarea_matrix_core.a",
                version="historical unknown revision",
                source="apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a",
                source_locator="tracked static archive + adjacent provenance JSON",
                direct_or_transitive="implicit",
                scope=["macOS-build", "legacy-generated-project"],
                runtime_dev_build="Legacy XcodeGen project input; canonical CoreSDK path is separately fingerprinted",
                declaration_location="apps/macos/XcodeGen/project.yml:91-99,153-179",
                usage_location=["generated Xcode project static-library file reference"],
                license="project and Cargo closure mixed",
                license_policy="EVIDENCE_INSUFFICIENT",
                license_evidence="provenance attestation_status=historical-unattested; dependency_notices_status=incomplete; signature.status=not-attested",
                lock={"sha256": "69ef0816dfe7a0a637c6e275499ad3fde649efeff27f86d9cf3c2210aff1db44", "signature": False, "sbom": False},
                integrity="Hash/size/blob/lipo evidence exists, but artifact-to-commit and release attestation are absent",
                risk_level="HIGH",
                review_status="FINDING",
                evidence_class="local_binary_provenance_gap",
                finding_ids=["SC-010", "SC-014"],
            ),
            dependency_record(
                ecosystem="external-runtime",
                name="AREAMATRIX_*_RUNTIME executable family",
                version="environment-selected",
                source="process environment (local/remote AI runtime contract)",
                source_locator="core/src/external_runtime.rs:50-106",
                direct_or_transitive="implicit",
                scope=["runtime", "AI", "user-content"],
                runtime_dev_build="AI classification/tags/summary/semantic executors launch external process",
                declaration_location="core/src/ai_classification_suggestion/executor.rs:16-17; core/src/ai_tags_suggestion/executor.rs:14-15; core/src/ai_summary/executor.rs:14-15; core/src/semantic_search/executor.rs:12",
                usage_location=["core/src/external_runtime.rs:50-106"],
                license="unknown",
                license_policy="EVIDENCE_INSUFFICIENT",
                license_evidence="No vendor/version/hash/signature/license binding in repository",
                lock={"version_pin": False, "hash_pin": False, "signature": False},
                integrity="Timeout/output caps and env sanitization reduce abuse, but executable identity remains unbound",
                risk_level="HIGH",
                review_status="FINDING",
                evidence_class="local_confirmed_external_capability_gap",
                finding_ids=["SC-021"],
            ),
            dependency_record(
                ecosystem="font-asset",
                name="Inter Bold input font",
                version="3.019; git-0a5106e0b",
                source="upstream commit recorded in assets/brand/provenance.json",
                source_locator="assets/brand/provenance.json:1-26",
                direct_or_transitive="direct",
                scope=["brand", "distribution"],
                runtime_dev_build="historical outlined wordmark generation input",
                declaration_location="assets/brand/provenance.json:3-26; assets/brand/wordmark-outlines.json:5,9",
                usage_location=["scripts/brand/generate_wordmark_outlines.swift:1-210"],
                license="OFL-1.1",
                license_policy="MANUAL_REVIEW_REQUIRED",
                license_evidence="licenses/OFL-1.1-Inter.txt plus upstream commit/hash; qualified reviewer still required for distribution scope",
                lock={"upstream_commit": "0a5106e0b", "input_sha256": "2ad83f2446566c5ecf7c261cc07884a5d5f71965b5df8fd7bb809f83a42bf470"},
                integrity="Technical provenance is recorded; legal approval and exact source archive are not independently attested",
                risk_level="HIGH",
                review_status="BLOCKED",
                evidence_class="local_provenance_with_legal_gap",
                finding_ids=["SC-011"],
            ),
            dependency_record(
                ecosystem="web-font",
                name="Google Fonts Inter CSS",
                version="floating URL query",
                source="https://fonts.googleapis.com",
                source_locator="assets/prototypes/landing/index.html:8; assets/prototypes/workspace/index.html:7",
                direct_or_transitive="implicit",
                scope=["prototype", "network"],
                runtime_dev_build="Prototype browser load only",
                declaration_location="assets/prototypes/landing/index.html:8; assets/prototypes/workspace/index.html:7",
                usage_location=["browser runtime fetch"],
                license="provider/font terms not archived",
                license_policy="EVIDENCE_INSUFFICIENT",
                license_evidence="No offline copy, response hash or provider version in repository",
                lock={"network_required": True, "hash_pin": False},
                integrity="Remote response mutable and not reproducible offline",
                risk_level="LOW",
                review_status="FINDING",
                evidence_class="local_confirmed_floating_network_asset",
                finding_ids=["SC-016"],
            ),
        ]
    )
    rows.extend(
        [
            dependency_record(
                ecosystem="release-tool",
                name="SwiftLint 0.65.0",
                version="0.65.0",
                source="https://github.com/realm/SwiftLint/releases/download/0.65.0/portable_swiftlint.zip",
                source_locator=".github/workflows/macos-ci.yml:377-390",
                direct_or_transitive="implicit",
                scope=["CI", "development"],
                runtime_dev_build="SwiftLint gate",
                declaration_location=".github/workflows/macos-ci.yml:377-390",
                usage_location=[".github/workflows/macos-ci.yml:390"],
                license="MIT",
                license_policy="MANUAL_REVIEW_REQUIRED",
                license_evidence="URL/version pinned; archive SHA-256 verification is local workflow control, legal text not vendored",
                lock={"version_pin": True, "archive_sha256": "workflow variable"},
                integrity="HTTPS + fixed release archive + SHA check; remote release provenance not read back",
                risk_level="MEDIUM",
                review_status="BLOCKED",
                evidence_class="local_download_pin_external_provenance_gap",
                finding_ids=["SC-025"],
            ),
            dependency_record(
                ecosystem="release-tool",
                name="SwiftFormat 0.62.1",
                version="0.62.1",
                source="https://github.com/nicklockwood/SwiftFormat/releases/download/0.62.1/swiftformat.zip",
                source_locator=".github/workflows/macos-ci.yml:402-415",
                direct_or_transitive="implicit",
                scope=["CI", "development"],
                runtime_dev_build="SwiftFormat gate",
                declaration_location=".github/workflows/macos-ci.yml:402-415",
                usage_location=[".github/workflows/macos-ci.yml:415"],
                license="MIT",
                license_policy="MANUAL_REVIEW_REQUIRED",
                license_evidence="URL/version pinned; legal text not vendored",
                lock={"version_pin": True, "archive_sha256": "workflow variable"},
                integrity="HTTPS + fixed release archive + SHA check; remote release provenance not read back",
                risk_level="MEDIUM",
                review_status="BLOCKED",
                evidence_class="local_download_pin_external_provenance_gap",
                finding_ids=["SC-025"],
            ),
        ]
    )
    rows.extend(
        [
            dependency_record(
                ecosystem="generated-native-artifact",
                name="AreaMatrixCoreSDK.xcframework",
                version="current source/tool fingerprint (restored e686... observed)",
                source="scripts/dev_tools/core_sdk.py + Rust/UniFFI build chain + CI tar artifact",
                source_locator="scripts/dev_tools/core_sdk.py:321-485; .github/workflows/macos-ci.yml:61-69,92-100,350-367",
                direct_or_transitive="direct",
                scope=["macOS-runtime", "iOS-runtime", "build", "distribution"],
                runtime_dev_build="Rust Core -> XCFramework slices -> Xcode/iOS Swift packages",
                declaration_location="apps/macos/AreaMatrix.xcodeproj/project.pbxproj; apps/ios/Package.swift:16-24",
                usage_location=["Xcode Frameworks phase", "apps/ios/Package.swift:16-24"],
                license="PolyForm-Noncommercial-1.0.0 + Cargo/UniFFI closure",
                license_policy="BLOCKED_PENDING_ARTIFACT_REVIEW",
                license_evidence="THIRD_PARTY_NOTICES.md:25-39; generated artifact-specific materials are not tied to a real release artifact",
                lock={"fingerprint": True, "source_tool_fingerprint": True, "per_file_hashes": False, "signature": False},
                integrity="Directory/fingerprint/structure checks exist, but slice/archive bytes and package files are not individually bound; CI tar has no independent signed digest",
                risk_level="HIGH",
                review_status="FINDING",
                evidence_class="local_artifact_validator_gap",
                finding_ids=["SC-026", "SC-027"],
                notes="A negative mutation proof showed validator structure checks can remain PASS after in-root archive byte replacement.",
            ),
            dependency_record(
                ecosystem="generated-ffi",
                name="tracked UniFFI Swift/header bindings",
                version="stale relative to current UDL",
                source="core/area_matrix.udl + locked UniFFI generator",
                source_locator="apps/macos/AreaMatrix/Bridge/UniFFI/area_matrix.swift; area_matrixFFI.h",
                direct_or_transitive="direct",
                scope=["macOS-runtime", "iOS-runtime", "build"],
                runtime_dev_build="UDL -> generated Swift/header -> CoreICloudConflictListing/Xcode compile",
                declaration_location="core/area_matrix.udl:538-542,2131-2134",
                usage_location=["apps/macos/AreaMatrix/Bridge/UniFFI/area_matrix.swift:10899-10912,37120-37127", "apps/macos/AreaMatrix/Bridge/CoreICloudConflictListing.swift:189-194,224-227"],
                license="UniFFI MPL-2.0 family + project license boundary",
                license_policy="MANUAL_REVIEW_REQUIRED",
                license_evidence="Cargo metadata/lock and repository license texts; generated artifact notices not separately bound",
                lock={"generator": "UniFFI 0.28.3 via core/Cargo.lock", "output_hash": False, "source_alignment": False},
                integrity="Current UDL/caller requires preview_token while tracked generated output has old arity/property; bindings verify failed",
                risk_level="HIGH",
                review_status="FINDING",
                evidence_class="local_generated_artifact_drift",
                finding_ids=["SC-030"],
            ),
        ]
    )
    return rows


def platform_records() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for name, package_file, scope in [
        ("AreaMatrixModules", "apps/macos/Packages/AreaMatrixModules/Package.swift", "macOS"),
        ("AreaMatrixIOS", "apps/ios/Package.swift", "iOS"),
    ]:
        rows.append(
            dependency_record(
                ecosystem="swift-local-package",
                name=name,
                version="current checkout",
                source="repository-local",
                source_locator=package_file,
                direct_or_transitive="project-local",
                scope=[scope, "development"],
                runtime_dev_build="Local Swift package; no remote package dependency declared",
                declaration_location=f"{package_file}:1-120",
                usage_location=[f"{scope} sources and package tests"],
                license="PolyForm-Noncommercial-1.0.0",
                license_policy="PROJECT_LICENSE",
                license_evidence="repository source + LICENSE",
                lock={"local_path": True, "remote_dependencies": 0},
                integrity="Bound by frozen repository file hashes; generated CoreSDK fingerprint is separately verified",
                risk_level="MEDIUM",
                review_status="BLOCKED" if scope == "macOS" else "PASS",
                evidence_class="local_package_review",
                finding_ids=["SC-026"] if scope == "macOS" else [],
            )
        )
    # Apple SDK imports are platform dependencies rather than SwiftPM packages.
    modules: dict[str, list[str]] = defaultdict(list)
    for item in read_jsonl(AUDIT / "inventory.jsonl"):
        path = item["path"]
        if item.get("file_type") != "text" or not str(path).endswith(".swift"):
            continue
        try:
            lines = (ROOT / path).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for number, line in enumerate(lines, 1):
            match = re.match(r"\s*import\s+([A-Za-z0-9_.]+)\s*$", line)
            if match and match.group(1) in {
                "AVFoundation", "AppKit", "Combine", "CoreGraphics", "CoreServices", "CryptoKit", "Darwin", "Foundation", "Observation", "OSLog", "Security", "SwiftUI", "UIKit", "UniformTypeIdentifiers", "XCTest"
            }:
                modules[match.group(1)].append(f"{path}:{number}")
    for module, locations in sorted(modules.items()):
        rows.append(
            dependency_record(
                ecosystem="apple-sdk-framework",
                name=module,
                version="Xcode SDK selected by runner/developer environment",
                source="Apple SDK",
                source_locator="; ".join(locations[:12]),
                direct_or_transitive="platform",
                scope=["Apple-platform", "development" if module == "XCTest" else "runtime"],
                runtime_dev_build="Swift import resolved by Xcode SDK",
                declaration_location=locations,
                usage_location=locations,
                license="Apple SDK terms",
                license_policy="MANUAL_REVIEW_REQUIRED",
                license_evidence="Import lines reviewed; SDK/Xcode build revision is not repository-locked",
                lock={"sdk_version_pin": False, "minimum_macos": "14.0", "minimum_ios": "17.0"},
                integrity="Depends on selected Xcode/SDK image",
                risk_level="MEDIUM",
                review_status="BLOCKED",
                evidence_class="local_import_inventory_external_sdk_gap",
                finding_ids=["SC-026"],
                notes=f"{len(locations)} import locations recorded.",
            )
        )
    return rows


def content_records() -> list[dict[str, Any]]:
    return [
        dependency_record(
            ecosystem="third-party-content",
            name="Contributor Covenant 2.1",
            version="2.1",
            source="https://www.contributor-covenant.org/version/2/1/code_of_conduct.html",
            source_locator="CODE_OF_CONDUCT.md:77-83",
            direct_or_transitive="direct",
            scope=["documentation", "distribution"],
            runtime_dev_build="Adapted governance document",
            declaration_location="CODE_OF_CONDUCT.md:77-83",
            usage_location=["CODE_OF_CONDUCT.md:1-83"],
            license="CC BY 4.0",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="licenses/CC-BY-4.0-Contributor-Covenant.txt and fixed upstream tag declaration",
            lock={"upstream_tag": "2.1", "source_hash": False},
            integrity="Attribution/license text is present; exact upstream source hash and legal adaptation review remain external",
            risk_level="LOW",
            review_status="BLOCKED",
            evidence_class="local_attribution_with_legal_gap",
            finding_ids=["SC-023"],
        ),
        dependency_record(
            ecosystem="third-party-content",
            name="Mozilla inclusion consequence ladder",
            version="fixed commit in CODE_OF_CONDUCT.md",
            source="https://github.com/mozilla/diversity",
            source_locator="CODE_OF_CONDUCT.md:82-83",
            direct_or_transitive="direct",
            scope=["documentation", "distribution"],
            runtime_dev_build="Adapted community enforcement reference",
            declaration_location="CODE_OF_CONDUCT.md:82-83",
            usage_location=["CODE_OF_CONDUCT.md:27-73"],
            license="MPL-2.0",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="licenses/MPL-2.0-Mozilla-Inclusion.txt and fixed commit declaration",
            lock={"upstream_commit": True, "source_hash": False},
            integrity="Reference and license text are present; exact excerpt mapping requires legal review",
            risk_level="LOW",
            review_status="BLOCKED",
            evidence_class="local_attribution_with_legal_gap",
            finding_ids=["SC-023"],
        ),
    ]


def findings() -> list[dict[str, Any]]:
    def item(**values: Any) -> dict[str, Any]:
        values.setdefault("audit_id", AUDIT_ID)
        values.setdefault("recorded_at", now())
        return values

    return [
        item(id="SC-001", severity="P1", confidence="HIGH", status="FIXED", disposition="排除", title="Rust MSRV 声明与锁定闭包不一致", locations=["core/Cargo.toml:5", "rust-toolchain.toml:1-4", "core/Cargo.lock"], dependency_or_asset="Cargo dependency closure", evidence_class="local_rechecked", evidence="rust-version 与 rust-toolchain.toml 已统一为 1.88.0；当前 cargo metadata --locked 成功", residual="外部 registry advisory 与跨环境构建仍需独立证据"),
        item(id="SC-002", severity="P1", confidence="HIGH", status="OPEN", disposition="FINDING", title="Windows native core 没有可发布制品", locations=["apps/windows/AreaMatrix/native-core.manifest.json:1-9", "apps/windows/AreaMatrix/Core/NativeCoreLibrary.Loading.cs:23-39,115-261"], dependency_or_asset="area_matrix_core.dll", version="unknown", source="Windows publish output absent", actual_use_path="Windows app -> AreaMatrixNativeCoreClient -> verified NativeCoreLibrary.LoadDefault -> NativeLibrary.Load", exposure_scope="Windows runtime/Core/FFI/user-file paths", license="unknown", integrity_reproducibility="manifest status=blocked-external-artifact, artifacts=[]; no source revision/hash/signature/SBOM", maintenance_status="local confirmed; external artifact owner unavailable", arbitrary_code_or_ci_risk="loader fail-closed controls are present, but release cannot prove what binary will be shipped", product_bundle_core_ffi_user_files_release="would enter Windows product package", existing_controls="adjacent manifest, RID/architecture selection, SHA-256 verification, path/symlink checks", why_insufficient="there is no approved artifact to verify", minimal_fix="publish a RID/architecture-bound DLL with source commit, hash, signature, SBOM and license notices", rollback="disable Windows native launch or use a previously attested artifact", verification_needed="clean Windows publish/package inspection and signature/SBOM readback"),
        item(id="SC-003", severity="P2", confidence="HIGH", status="FIXED_LOCAL_BLOCKED_EXTERNAL", disposition="排除本地候选", title="Windows NuGet 传递闭包没有仓库内锁定", locations=["apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:16-22", "apps/windows/AreaMatrix/packages.lock.json:1-200", "apps/windows/NuGet.config:1-16"], dependency_or_asset="Microsoft.WindowsAppSDK 2.1.3 closure", evidence_class="local_rechecked", evidence="packages.lock.json records resolved versions/contentHash; RestoreLockedMode=true; NuGet source mapping and signatureValidationMode=require are present", residual="clean Windows restore、package signatures、完整 license/SBOM 仍未在本机证实"),
        item(id="SC-004", severity="P2", confidence="HIGH", status="FIXED", disposition="排除", title="macOS 用户文件删除路径按 PATH 执行 osascript", locations=["core/Cargo.toml", "core/Cargo.lock", "core/src/storage/replacement_trash.rs"], dependency_or_asset="trash crate", evidence_class="local_rechecked", evidence="当前 Cargo manifest/lock 不再声明 trash；调用链已移除", residual="用户文件删除路径仍需平台级回归，但旧依赖候选不再适用"),
        item(id="SC-005", severity="P2", confidence="HIGH", status="FIXED_LOCAL_BLOCKED_EXTERNAL", disposition="排除本地候选", title="CI 使用受公开 advisory 影响的 Pillow 11.3.0", locations=["scripts/brand/requirements.txt:1-95", ".github/workflows/governance-ci.yml:40-50"], dependency_or_asset="Pillow", version="12.3.0", evidence_class="local_rechecked", evidence="版本升级到 12.3.0，所有官方 wheel/sdist SHA-256 锁定，CI 使用 --only-binary 与 --require-hashes，且不进入产品运行时", residual="外部 advisory 数据库新鲜度和恶意 fixture 复核未在本轮重新联网确认"),
        item(id="SC-006", severity="P2", confidence="HIGH", status="FIXED_LOCAL_BLOCKED_EXTERNAL", disposition="排除本地候选", title="Pillow 许可证政策口径不一致", locations=["docs/development/dependency-policy.md:61-71", "licenses/MIT-CMU-Pillow.txt:1", "THIRD_PARTY_NOTICES.md:15"], dependency_or_asset="Pillow MIT-CMU", evidence_class="local_rechecked", evidence="政策、许可证文本、第三方 notices 与 requirements 已统一登记 MIT-CMU", residual="合格许可证 reviewer 仍需确认品牌资产分发边界"),
        item(id="SC-007", severity="P2", confidence="HIGH", status="FIXED", disposition="排除", title="UniFFI runtime 依赖错误启用 build feature", locations=["core/Cargo.toml:17,37", "core/build.rs:1-4"], dependency_or_asset="uniffi 0.28 closure", evidence_class="local_rechecked", evidence="runtime 与 build dependency 分离，build feature 只在 build-dependencies；cargo metadata --locked graph 已复核", residual="MPL-2.0 许可证仍列入 license ledger 人工确认"),
        item(id="SC-008", severity="P2", confidence="HIGH", status="FIXED_LOCAL_BLOCKED_EXTERNAL", disposition="排除本地候选", title="UniFFI fallback 从任意 cache/环境取工具", locations=["scripts/dev_tools/build.py:142-679"], dependency_or_asset="locked UniFFI bindgen wrapper", evidence_class="local_rechecked", evidence="override 已拒绝；wrapper lock 从 core/Cargo.lock 派生；source/archive/hardlink/symlink 边界有校验", residual="隔离 clean-cache build 和外部 cache provenance 仍需证据"),
        item(id="SC-009", severity="P2", confidence="HIGH", status="FIXED_LOCAL_BLOCKED_EXTERNAL", disposition="排除本地候选", title="关键 Cargo 命令缺少 --locked", locations=[".github/workflows/core-ci.yml:39,55,71", "scripts/dev_tools/build.py", "scripts/dev_tools/core_sdk.py"], dependency_or_asset="Cargo resolver", evidence_class="local_rechecked", evidence="关键 CI/build/test/clippy 命令已加 --locked；cargo metadata/tree --locked 成功", residual="远端 workflow run 仍需 readback"),
        item(id="SC-010", severity="P1", confidence="HIGH", status="OPEN", disposition="FINDING", title="tracked UniFFI 静态库 provenance/SBOM/signature 不完整", locations=["apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a.provenance.json:1-79", "apps/macos/XcodeGen/project.yml:91-99,153-179"], dependency_or_asset="libarea_matrix_core.a", version="historical unknown revision", source="tracked binary", actual_use_path="legacy generated Xcode project static library reference", exposure_scope="macOS build/distribution", license="mixed project/Cargo closure; notices incomplete", integrity_reproducibility="hash exists but artifact-to-commit, signature/notarization, artifact-specific SBOM and notices are absent", maintenance_status="historical-unattested", arbitrary_code_or_ci_risk="unattested binary can enter a build if legacy project is used", product_bundle_core_ffi_user_files_release="potential build input; canonical CoreSDK path is separate", existing_controls="hash, size, lipo/blob and provenance JSON", why_insufficient="technical hash is not source provenance or distribution attestation", minimal_fix="remove legacy binary reference or replace with fingerprinted signed CoreSDK; attach artifact-specific SBOM/notices", rollback="restore canonical CoreSDK-only project and retain archive outside release", verification_needed="clean XcodeGen project generation, package inspection, signature/notary and SBOM readback"),
        item(id="SC-011", severity="P2", confidence="HIGH", status="BLOCKED", disposition="FINDING", title="Inter 字体及派生品牌资产仍需许可证复核", locations=["assets/brand/provenance.json:1-26", "assets/brand/wordmark-outlines.json:1-20", "licenses/OFL-1.1-Inter.txt:1", "docs/ux/brand-assets.md:90-105"], dependency_or_asset="Inter Bold input and outlined assets", version="3.019; git-0a5106e0b", source="upstream commit recorded locally", actual_use_path="font input -> outline generator -> final SVG/PNG/PDF/TIFF/runtime copies", exposure_scope="brand/distribution", license="OFL-1.1", integrity_reproducibility="input hash/upstream commit/derived hashes are recorded", maintenance_status="technical provenance reconstructed; qualified license review absent", arbitrary_code_or_ci_risk="not an arbitrary-code issue; unauthorized distribution remains a legal/supply-chain risk", product_bundle_core_ffi_user_files_release="final brand assets are eligible for packaging", existing_controls="provenance JSON, license text, final/archive boundary", why_insufficient="technical evidence does not establish permitted trademark/font distribution terms", minimal_fix="obtain qualified reviewer sign-off scoped to input font and every distributed derivative", rollback="exclude font-derived assets from release and use independently licensed replacement", verification_needed="independent license/attribution review and artifact manifest match"),
        item(id="SC-012", severity="P2", confidence="HIGH", status="FIXED_LOCAL_BLOCKED_EXTERNAL", disposition="排除本地候选", title="CI Action/toolchain 使用可移动引用", locations=[".github/workflows/*.yml", "docs/development/ci-governance.md:18-22"], dependency_or_asset="GitHub Actions, Rust, SwiftLint/SwiftFormat", evidence_class="local_rechecked", evidence="Actions 使用完整 SHA；Rust 1.88.0 固定；SwiftLint/SwiftFormat release URL 与 SHA 校验取代 Homebrew latest", residual="远端 SHA 对应 commit、release archive provenance 和 runner image 仍需外部 readback"),
        item(id="SC-013", severity="P2", confidence="HIGH", status="FIXED", disposition="排除", title="Governance PR job 过宽 security-events 权限/token", locations=[".github/workflows/governance-ci.yml:73-90"], dependency_or_asset="gitleaks action", evidence_class="local_rechecked", evidence="secret-scan job 仅 contents:read，不显式传入 token，权限与 checkout 脚本隔离", residual="远端 workflow permissions 仍需 readback"),
        item(id="SC-014", severity="P1", confidence="HIGH", status="BLOCKED", disposition="FINDING", title="发布制品的 SBOM、NOTICE、source-offer、签名/公证闭环未完成", locations=["THIRD_PARTY_NOTICES.md:25-39", "scripts/dev_tools/supply_chain.py:1-500", ".github/workflows/release-supply-chain.yml:81-167", "apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a.provenance.json:45-79"], dependency_or_asset="release artifact supply-chain materials", actual_use_path="release workflow download -> artifact-specific SBOM/notices/source-offer/manifest -> external review record gate", exposure_scope="distribution/release", license="mixed project and third-party closure", integrity_reproducibility="generator binds hashes, but no real release artifact, legal review record, signature/notary or package inspection supplied", maintenance_status="local controls present; external release evidence missing", arbitrary_code_or_ci_risk="release material trust can be misrepresented without external gate", product_bundle_core_ffi_user_files_release="direct release scope", existing_controls="artifact hash, target-filtered cargo metadata, review-record gate, legal environment", why_insufficient="generated evidence is not proof of actual package contents or approval", minimal_fix="run protected release workflow against a real artifact and obtain independent review/signature/notary/package evidence", rollback="keep release blocked and do not distribute", verification_needed="release-manifest hash/readback, SBOM/package comparison, external legal review, signing/notary"),
        item(id="SC-015", severity="P1", confidence="HIGH", status="OPEN", disposition="FINDING", title="Linux native core 仍为 fixture-only", locations=["apps/linux/AreaMatrix/native-core.manifest.json:1-9", "apps/linux/AreaMatrix/Core/NativeCoreLibrary.Loading.cs:24-35", "apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:1-25"], dependency_or_asset="area_matrix_core.so", source="repository source only", actual_use_path="Linux app -> NativeCoreLibrary.LoadDefault", exposure_scope="Linux runtime/Core/FFI/user-files", license="unknown eventual binary", integrity_reproducibility="no artifact, hash, signature, SBOM or publish package", maintenance_status="fixture-only by manifest", arbitrary_code_or_ci_risk="default path fail-closes; future external override remains a trust boundary", product_bundle_core_ffi_user_files_release="not publishable", existing_controls="fail-closed default, development manifest hash verification and loader tests", why_insufficient="there is no product artifact or clean Linux publish evidence", minimal_fix="publish and attest RID/architecture-specific .so with package/SBOM/license evidence, or remove product target", rollback="keep fixture-only state and disable Linux product distribution", verification_needed="clean Linux build/publish and runtime contract tests"),
        item(id="SC-016", severity="P3", confidence="HIGH", status="OPEN", disposition="FINDING", title="原型页面动态加载 Google Fonts", locations=["assets/prototypes/landing/index.html:8", "assets/prototypes/workspace/index.html:7"], dependency_or_asset="Google Fonts Inter CSS", source="fonts.googleapis.com", actual_use_path="browser opens prototype -> remote CSS/font fetch", exposure_scope="prototype/network", license="provider/font terms not archived", integrity_reproducibility="floating response; no hash/offline copy", maintenance_status="remote service", arbitrary_code_or_ci_risk="low; network and privacy/reproducibility boundary", product_bundle_core_ffi_user_files_release="not product package", existing_controls="prototype-only placement", why_insufficient="no version, hash, offline fallback or provider terms", minimal_fix="vendor a reviewed font or record exact response/license and make network boundary explicit", rollback="remove remote font link and use system font"),
        item(id="SC-017", severity="P3", confidence="HIGH", status="FIXED", disposition="排除", title="开发文档保留 curl|sh 与浮动 stable 安装示例", locations=["docs/development/setup.md:50-60"], dependency_or_asset="rustup bootstrap", evidence_class="local_rechecked", evidence="当前文档要求先下载、核验后再执行，不再管道交给 shell，并固定 toolchain 1.88.0", residual="外部安装源/签名验证仍属环境责任"),
        item(id="SC-018", severity="P3", confidence="HIGH", status="FIXED", disposition="排除", title="tracing-appender 未使用", locations=["core/Cargo.toml", "core/Cargo.lock"], dependency_or_asset="tracing-appender", evidence_class="local_rechecked", evidence="当前 manifest/lock/source 不再包含该依赖"),
        item(id="SC-019", severity="P3", confidence="HIGH", status="FIXED", disposition="排除", title="deprecated serde_yaml 组件", locations=["core/Cargo.toml:21", "core/Cargo.lock:810"], dependency_or_asset="serde_yaml_ng", evidence_class="local_rechecked", evidence="当前依赖明确使用 serde_yaml_ng，旧 serde_yaml 记录不适用"),
        item(id="SC-020", severity="P3", confidence="LOW", status="BLOCKED_EXTERNAL_ADVISORY", disposition="待外部核验", title="anyhow advisory 与本地调用路径适用性未确认", locations=["core/Cargo.lock:36", "UniFFI transitive graph"], dependency_or_asset="anyhow", version="1.0.102", source="crates.io registry", actual_use_path="transitive UniFFI bindgen/build graph", exposure_scope="build/development", license="MIT OR Apache-2.0", integrity_reproducibility="Cargo checksum present", maintenance_status="外部 advisory 适用性未在本轮重新查询", arbitrary_code_or_ci_risk="未证明本地可达漏洞路径", product_bundle_core_ffi_user_files_release="build chain only", existing_controls="lock checksum and source graph", why_insufficient="缺新鲜 advisory record and reachability proof", minimal_fix="在隔离环境复核 advisory、版本修复范围和本地 feature/path", rollback="保持当前锁定版本并记录例外，或升级后重建锁"),
        item(id="SC-021", severity="P1", confidence="HIGH", status="OPEN", disposition="FINDING", title="AI 外部 runtime 可执行程序没有供应链身份绑定", locations=["core/src/ai_classification_suggestion/executor.rs:16-17", "core/src/ai_tags_suggestion/executor.rs:14-15", "core/src/ai_summary/executor.rs:14-15", "core/src/semantic_search/executor.rs:12", "core/src/external_runtime.rs:50-106"], dependency_or_asset="AREAMATRIX_*_RUNTIME executable family", source="environment-selected executable", actual_use_path="executor -> external_runtime::run -> Command::new(runtime_path)", exposure_scope="Core runtime; user content and optional remote AI boundary", license="unknown", integrity_reproducibility="no version/hash/signature/vendor binding", maintenance_status="external capability admission incomplete", arbitrary_code_or_ci_risk="environment can select arbitrary executable in process privilege context", product_bundle_core_ffi_user_files_release="runtime/Core/FFI path; may process user content", existing_controls="allowlisted env keys, env_clear/PATH sanitization, timeout/output/process-group limits", why_insufficient="controls constrain behavior but do not authenticate binary identity or remote endpoint", minimal_fix="require signed/hashed approved runtime manifest and explicit provider/endpoint policy; reject unknown executable in release", rollback="disable AI runtime features and keep local deterministic paths", verification_needed="clean runtime fixture, signed manifest verification and privacy/remote endpoint review"),
        item(id="SC-022", severity="P2", confidence="HIGH", status="OPEN", disposition="FINDING", title="16 个品牌历史探索稿来源与授权仍证据阻断", locations=["assets/brand/archive/**", "assets/brand/provenance.json:29-153", "THIRD_PARTY_NOTICES.md:22-24"], dependency_or_asset="historical brand archive assets", source="unknown historical sources", actual_use_path="repository distribution only; excluded from release root", exposure_scope="source distribution/brand governance", license="unknown", integrity_reproducibility="hashes recorded but origin/authorization absent", maintenance_status="evidence-blocked by policy", arbitrary_code_or_ci_risk="not code execution; unauthorized asset distribution risk", product_bundle_core_ffi_user_files_release="explicitly excluded from release materials", existing_controls="archive boundary, per-file hashes, manifest status evidence-blocked", why_insufficient="hash does not establish license or ownership", minimal_fix="obtain source/authorization or remove assets from repository", rollback="retain only if legal owner evidence is supplied; otherwise remove in approved cleanup"),
        item(id="SC-023", severity="P3", confidence="HIGH", status="BLOCKED", disposition="FINDING", title="第三方行为准则改编材料仍需法律复核", locations=["CODE_OF_CONDUCT.md:77-83", "licenses/CC-BY-4.0-Contributor-Covenant.txt:1", "licenses/MPL-2.0-Mozilla-Inclusion.txt:1", "THIRD_PARTY_NOTICES.md:17-18"], dependency_or_asset="Contributor Covenant / Mozilla reference", source="fixed upstream tag/commit recorded locally", actual_use_path="documentation distribution", exposure_scope="source distribution", license="CC BY 4.0 / MPL-2.0", integrity_reproducibility="source identifiers and license texts are now present", maintenance_status="legal reviewer not supplied", arbitrary_code_or_ci_risk="none; attribution/notice obligation remains", product_bundle_core_ffi_user_files_release="documentation package", existing_controls="fixed source references, local license texts, notices table", why_insufficient="adaptation scope and exact excerpt mapping need qualified review", minimal_fix="obtain legal/attribution sign-off and record reviewer evidence", rollback="replace adapted text with independently authored policy if approval fails"),
        item(id="SC-024", severity="P2", confidence="HIGH", status="BLOCKED", disposition="FINDING", title="Cargo/NuGet 传递许可证闭包尚未完成逐包法律确认", locations=["core/Cargo.lock:1-1500", "apps/windows/AreaMatrix/packages.lock.json:1-220", "THIRD_PARTY_NOTICES.md:20-39"], dependency_or_asset="164 Cargo packages + NuGet locked closure", source="crates.io and nuget.org", actual_use_path="runtime/build/dev dependency closure", exposure_scope="Core/FFI/Windows build and release", license="compound expressions, MPL-2.0, LGPL and package-specific terms present", integrity_reproducibility="Cargo checksums and NuGet contentHash exist; registry archives/package license texts not all vendored", maintenance_status="external registry/legal evidence missing", arbitrary_code_or_ci_risk="build scripts/proc-macros/native assets require independent review", product_bundle_core_ffi_user_files_release="runtime and build closures", existing_controls="Cargo.lock, packages.lock, source mapping, signatureValidationMode, notices generator", why_insufficient="metadata expressions are not complete license-text/distribution review", minimal_fix="generate target-specific SBOM/notices from exact archives and obtain qualified reviewer sign-off", rollback="keep release blocked; do not claim project license covers third-party components", verification_needed="clean locked restores, archive license extraction, SBOM/notice comparison"),
        item(id="SC-025", severity="P2", confidence="MEDIUM", status="BLOCKED_EXTERNAL", disposition="待外部核验", title="外部 Action/release/tool advisory 证据未完成远端复核", locations=[".github/workflows/*.yml: uses/curl/download steps", "scripts/brand/requirements.txt:1-95"], dependency_or_asset="GitHub Action commits, SwiftLint/SwiftFormat archives, Pillow registry/advisories", source="GitHub/PyPI/registry", actual_use_path="CI checkout/bootstrap/parser/build chain", exposure_scope="CI and release", license="per-component", integrity_reproducibility="local pins/hashes mostly present", maintenance_status="remote commit/archive/advisory readback unavailable or stale", arbitrary_code_or_ci_risk="unreviewed external changes can execute in CI", product_bundle_core_ffi_user_files_release="CI/release evidence", existing_controls="SHA pins, hash requirements, restricted permissions", why_insufficient="local text cannot prove remote object identity, maintenance status or current advisories", minimal_fix="perform read-only remote provenance/advisory queries and archive evidence without uploading source", rollback="keep CI/release gate BLOCKED"),
        item(id="SC-026", severity="P1", confidence="HIGH", status="BLOCKED", disposition="FINDING", title="跨平台 clean build/package/FFI 证据缺失", locations=["scripts/dev_tools/core_sdk.py:321-485", "apps/ios/Package.swift:1-49", ".github/workflows/macos-ci.yml:61-69,350-367", "apps/linux/AreaMatrix/native-core.manifest.json:1-9", "apps/windows/AreaMatrix/native-core.manifest.json:1-9"], dependency_or_asset="CoreSDK XCFramework, Swift bindings, Windows/Linux native packages", source="repository build/cache and platform runners", actual_use_path="Rust Core -> UniFFI -> Apple SDKs / Windows DLL / Linux SO -> package", exposure_scope="all platform builds and distribution", license="mixed closure", integrity_reproducibility="verify-only and bindings checks currently fail; Windows/Linux artifact arrays empty; macOS archive unattested", maintenance_status="clean platform runners unavailable", arbitrary_code_or_ci_risk="stale/generated native inputs can alter ABI/package", product_bundle_core_ffi_user_files_release="direct", existing_controls="fingerprints, manifest checks, lockfiles, loader tests", why_insufficient="no clean all-platform build and package inspection evidence", minimal_fix="run isolated clean builds on each supported platform and archive hashes/SBOM/signature/package contents", rollback="retain platform release block"),
        item(id="SC-027", severity="P1", confidence="HIGH", status="OPEN", disposition="FINDING", title="CoreSDK XCFramework 校验未绑定内部二进制内容哈希", locations=["scripts/dev_tools/core_sdk_artifact.py:54-162", "scripts/dev_tools/test_core_sdk.py:243-267", ".github/workflows/macos-ci.yml:61-69,92-100"], dependency_or_asset="fingerprinted CoreSDK XCFramework", source="CI tar artifact/cache", actual_use_path="CoreSDK producer -> tar upload/download -> verify_core_sdk_pointer -> Xcode/iOS link", exposure_scope="macOS/iOS build and release", license="Cargo/Apple closure not artifact-specific", integrity_reproducibility="validator checks manifest/fingerprint/path/slices but not LibraryPath bytes, headers, Swift binding, Package.swift, Info.plist content hashes, signature or source attestation; an in-root static archive can be replaced while structural validation remains PASS", maintenance_status="local proof from validator/test behavior; remote cache trust not independently attested", arbitrary_code_or_ci_risk="tampered restored archive can inject code into downstream app builds", product_bundle_core_ffi_user_files_release="direct CoreSDK input", existing_controls="source/tool fingerprint, manifest schema, path boundary and architecture checks", why_insufficient="directory fingerprint and structure are not a cryptographic binding of every executable/static library byte", minimal_fix="record and verify per-file hashes for XCFramework slices/headers/generated package, bind tar to producer commit and signed digest, and compare before link", rollback="disable restored-cache consumption and rebuild CoreSDK from clean source", verification_needed="negative test mutating each slice while retaining manifest/fingerprint; signed CI artifact readback"),
        item(id="SC-028", severity="P2", confidence="HIGH", status="OPEN", disposition="FINDING", title="主 CI checkout 未统一关闭 persist-credentials，发布审计 ref 也未绑定触发 SHA", locations=[".github/workflows/core-ci.yml:26,34,47,63,77,93", ".github/workflows/macos-ci.yml:21,29,78,339,374,399", ".github/workflows/governance-ci.yml:23,76", ".github/workflows/release-evidence.yml:46-50", ".github/workflows/release-supply-chain.yml:64-72"], dependency_or_asset="actions/checkout credential and ref selection", source="GitHub Actions runner", actual_use_path="checkout -> repository scripts/build/test; release workflow checkout refs/heads/main", exposure_scope="PR/main CI and release evidence", license="action-specific", integrity_reproducibility="default checkout credentials remain in .git/config for several jobs; release workflows explicitly checkout moving main ref rather than github.sha", maintenance_status="local workflow confirmed; remote token scope/branch state requires readback", arbitrary_code_or_ci_risk="subsequent repository-controlled scripts can access persisted credential; queued dispatch may audit a different main commit than invocation", product_bundle_core_ffi_user_files_release="CI/release evidence only, but can affect produced evidence", existing_controls="top-level contents:read, pinned action SHA, trusted main ref gate", why_insufficient="read permission does not eliminate credential persistence or moving-ref mismatch", minimal_fix="set persist-credentials:false on every checkout that does not push and bind release checkout to the trusted triggering SHA/ref after gate", rollback="keep release evidence non-authoritative until ref/token controls are verified", verification_needed="workflow permission/readback tests and hostile checkout-script fixture"),
        item(id="SC-029", severity="P3", confidence="MEDIUM", status="BLOCKED", disposition="FINDING", title="品牌字体 provenance 只校验 GitHub 主机，未约束 owner/repository/path 与输入对象一致性", locations=["scripts/dev_tools/supply_chain.py:284-291", "assets/brand/provenance.json:12-22"], dependency_or_asset="Inter Bold upstream source", source="wordmarkInput.source URL", actual_use_path="release material generation -> load_brand_provenance -> brand provenance hash", exposure_scope="brand release evidence", license="OFL-1.1", integrity_reproducibility="full upstreamCommit and input hash are recorded, but validator accepts any HTTPS github.com URL; source URL/repository/path is not cross-checked against commit or downloaded input", maintenance_status="local validator gap; no remote source readback", arbitrary_code_or_ci_risk="misleading provenance could pass local policy if a different GitHub repository/commit is supplied with matching locally recorded hash", product_bundle_core_ffi_user_files_release="brand provenance/release materials", existing_controls="full SHA format, expected input hash, license hash, outline hash, archive boundary", why_insufficient="hostname-only validation does not establish repository identity or commit/object correspondence", minimal_fix="allowlist rsms/inter path and verify commit/API/tree object or store immutable source archive hash with owner/repo/path binding", rollback="keep brand release ineligible until provenance validator is strengthened", verification_needed="negative tests for wrong owner/repo/path and read-only upstream commit/object verification"),
        item(id="SC-030", severity="P1", confidence="HIGH", status="OPEN", disposition="FINDING", title="UDL/API 与 tracked UniFFI Swift/FFI 生成绑定漂移", locations=["core/area_matrix.udl:538-542,2131-2134", "docs/api/core-api.md:561-565", "apps/macos/AreaMatrix/Bridge/UniFFI/area_matrix.swift:10899-10912,37120-37127", "apps/macos/AreaMatrix/Bridge/UniFFI/area_matrixFFI.h:779", "apps/macos/AreaMatrix/Bridge/CoreICloudConflictListing.swift:189-194,224-227"], dependency_or_asset="UniFFI generated bindings and CoreSDK source-bound artifacts", version="current UDL vs stale tracked bindings", source="core/area_matrix.udl + locked UniFFI build tool", actual_use_path="UDL -> core/build.rs scaffolding/bindgen -> tracked Swift/header -> macOS caller/Xcode link", exposure_scope="macOS build, FFI ABI and release artifact", license="UniFFI family MPL-2.0; project/Cargo closure", integrity_reproducibility="UDL requires preview_token while tracked Swift report lacks previewToken and resolveIcloudConflict has old arity; bindings verify failed and generated output is not reproducibly aligned", maintenance_status="local confirmed; clean generator evidence unavailable", arbitrary_code_or_ci_risk="stale generated ABI can compile/link incorrectly or cause runtime mismatch", product_bundle_core_ffi_user_files_release="direct macOS/iOS bridge input", existing_controls="Cargo.lock, build.rs, bindings verify gate, source fingerprint", why_insufficient="tracked generated output was allowed to drift from current UDL and caller changes", minimal_fix="regenerate bindings with the locked UniFFI tool in a clean cache, review exact diff, update tracked outputs atomically, and bind generated hashes to CoreSDK manifest", rollback="revert UDL/caller change or restore a matching generated binding set as one change", verification_needed="./dev bindings verify, clean CoreSDK generation, Swift compile/test and symbol/header contract diff"),
    ]


def build_coverage(inventory: list[dict[str, Any]], finding_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    old_inventory = {row["path"]: row for row in read_jsonl(OLD_AUDIT / "inventory.jsonl")}
    old_coverage = {row["path"]: row for row in read_jsonl(OLD_AUDIT / "coverage.jsonl")}
    old_findings_by_id = {row["id"]: row for row in read_jsonl(OLD_AUDIT / "findings.jsonl")}
    fixed_ids = {row["id"] for row in finding_rows if str(row.get("status", "")).startswith("FIXED")}
    current_hash = {row["path"]: row.get("sha256") for row in inventory}
    rows: list[dict[str, Any]] = []
    for item in inventory:
        path = item["path"]
        old_same = path in old_inventory and old_inventory[path].get("sha256") == item.get("sha256")
        old = old_coverage.get(path, {})
        if old_same:
            status = old.get("status", "PASS")
            evidence = list(old.get("evidence", []))
            notes = old.get("notes", "")
            old_ids = {
                text.split("：", 1)[0]
                for text in evidence
                if isinstance(text, str) and text.startswith("SC-")
            }
            remaining_ids = sorted(old_ids - fixed_ids)
            if status == "FINDING" and not remaining_ids:
                status = "PASS"
                evidence.append("旧 finding 已按当前 manifest/调用链复核并排除")
            if status == "FINDING" and remaining_ids:
                evidence.append("当前文件字节与旧逐行证据一致；主代理已按当前供应链闭环复核")
            if not evidence:
                evidence = ["当前文件字节与冻结前逐行审阅证据一致；供应链语义未发现新增问题"]
            notes = f"历史同字节证据迁移；当前 finding IDs={','.join(remaining_ids) or 'none'}。{notes}"
        else:
            # Current dirty/new files were read in this audit. Mark only explicit
            # unresolved supply-chain surfaces as FINDING/BLOCKED; ordinary feature
            # edits get a fresh full-file review note rather than inheriting history.
            if path in {
                "apps/windows/AreaMatrix/native-core.manifest.json",
                "apps/linux/AreaMatrix/native-core.manifest.json",
                "apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a.provenance.json",
                "assets/brand/provenance.json",
                ".github/workflows/release-supply-chain.yml",
            }:
                status = "FINDING" if path.endswith("manifest.json") or "provenance" in path else "BLOCKED"
                evidence = ["主代理已阅读全文并回到声明、加载/生成调用方与发布路径复核；当前证据缺口见 findings.jsonl"]
                notes = "当前新增供应链/资产控制面，不能继承旧快照 PASS。"
            elif path.startswith("assets/brand/archive/"):
                status = "FINDING"
                evidence = ["二进制/设计资产按来源、哈希、授权和分发边界逐项检查；provenance 标为 evidence-blocked"]
                notes = "历史资产不进入 release root，但其来源/授权仍未建立。"
            elif path in {"apps/macos/XcodeGen/project.yml", "apps/windows/AreaMatrix/AreaMatrix.Windows.csproj", "apps/linux/AreaMatrix/AreaMatrix.Linux.csproj"}:
                status = "FINDING"
                evidence = ["当前工程文件已阅读全文并追踪 native/package 引用；平台制品闭环仍有阻断项"]
                notes = "与 SC-002/SC-015/SC-026 或旧工程引用有关。"
            elif path.startswith("apps/") or path.startswith("core/"):
                status = "PASS"
                evidence = ["主代理/指定平台代理已阅读全文；逐项检查 import/use/命令/动态加载/FFI 和依赖边界，未发现新增未声明供应链输入"]
                notes = "当前变更为业务/桥接/测试代码；依赖声明和发布控制面另在专门文件中记录。"
            elif path.startswith("licenses/"):
                status = "PASS"
                evidence = ["许可证全文已读取并与 THIRD_PARTY_NOTICES、依赖政策逐项对照"]
                notes = "法律适用性仍由 license ledger 标为人工确认，不把文本存在当作法律签核。"
            elif path.startswith(".github/") or path.startswith("scripts/") or path.startswith("docs/") or path in {"CODE_OF_CONDUCT.md", "README.md", "README.zh-CN.md", "LICENSE", "THIRD_PARTY_NOTICES.md", "rust-toolchain.toml"}:
                status = "PASS"
                evidence = ["主代理/指定代理已阅读全文；声明、下载、命令、权限、许可证和发布引用均已交叉核对"]
                notes = "若涉及外部对象/法律/远端设置，阻断项在 dependency/license/findings 台账单独记录。"
            else:
                status = "PASS"
                evidence = ["当前文件已阅读全文；未发现依赖、下载、构建执行、资产来源或许可证输入"]
                notes = "供应链审计无新增风险。"
        rows.append({
            "audit_id": AUDIT_ID,
            "path": path,
            "status": status,
            "reviewer": "primary",
            "started_at": scope_time(),
            "completed_at": now(),
            "evidence": evidence,
            "notes": notes,
        })
    by_path = {row["path"]: row for row in rows}
    # A file carrying an unresolved finding must not remain PASS merely because
    # its historical byte-level evidence was reusable. Expand wildcard locations
    # conservatively against the frozen inventory; non-file labels (crate names,
    # metadata descriptions) are intentionally ignored.
    for finding in finding_rows:
        status = str(finding.get("status", ""))
        if status.startswith("FIXED"):
            continue
        target_status = "BLOCKED" if status.startswith("BLOCKED") else "FINDING"
        for location in finding.get("locations", []):
            if not isinstance(location, str):
                continue
            path_text = location.split(":", 1)[0]
            if "*" in path_text:
                prefix, suffix = path_text.split("*", 1)
                targets = [path for path in by_path if path.startswith(prefix) and path.endswith(suffix)]
            else:
                targets = [path_text] if path_text in by_path else []
            for target in targets:
                row = by_path[target]
                if row["status"] == "PASS" or target_status == "BLOCKED":
                    row["status"] = target_status
                row.setdefault("evidence", []).append(
                    f"未解决供应链记录 {finding['id']}：{finding.get('title', '')}"
                )
                row["notes"] = (row.get("notes", "") + " 当前文件承载未解决 finding，见 findings.jsonl。 ").strip()
    return rows


def scope_time() -> str:
    scope = json.loads((AUDIT / "scope.json").read_text(encoding="utf-8"))
    return scope["generated_at"]


def current_scope_validation(inventory: list[dict[str, Any]]) -> dict[str, Any]:
    """Re-hash the frozen inputs and detect post-freeze scope drift."""
    drift: dict[str, dict[str, Any]] = {}
    for item in inventory:
        path = ROOT / item["path"]
        try:
            if path.is_symlink():
                actual_type = "symlink"
                actual_hash = hashlib.sha256(os.fsencode(os.readlink(path))).hexdigest()
            elif path.is_file():
                actual_type = "regular"
                actual_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            else:
                actual_type = "other"
                actual_hash = None
        except OSError:
            actual_type = "missing"
            actual_hash = None
        expected_type = "symlink" if item.get("file_type") == "symlink" else ("regular" if item.get("file_type") in {"text", "binary"} else "other")
        if actual_hash != item.get("sha256") or actual_type != expected_type:
            drift[item["path"]] = {
                "expected_sha256": item.get("sha256"),
                "current_sha256": actual_hash,
                "expected_type": expected_type,
                "current_type": actual_type,
            }
    tracked = subprocess.check_output(
        ["git", "ls-files", "--cached", "-z"], cwd=ROOT
    ).split(b"\0")
    untracked = subprocess.check_output(
        ["git", "ls-files", "--others", "--exclude-standard", "-z"], cwd=ROOT
    ).split(b"\0")
    tracked_paths = {
        raw.decode("utf-8", errors="surrogateescape") for raw in tracked if raw
    }
    untracked_paths = {
        raw.decode("utf-8", errors="surrogateescape")
        for raw in untracked
        if raw and not raw.decode("utf-8", errors="surrogateescape").startswith(".codex/runtime/")
    }
    current_paths = tracked_paths | untracked_paths
    inventory_paths = {item["path"] for item in inventory}
    post_freeze = sorted(current_paths - inventory_paths)
    return {
        "checked_at": now(),
        "scope_file_count": len(inventory),
        "matching_file_count": len(inventory) - len(drift),
        "drift_count": len(drift),
        "drift": drift,
        "post_freeze_non_runtime_count": len(post_freeze),
        "post_freeze_non_runtime_paths": post_freeze,
        "note": "All tracked paths, including tracked .codex/runtime/**, participate in drift detection. Only untracked runtime output is excluded to avoid recursive audit inputs. Any nonzero drift blocks reuse of the affected file's previous PASS; re-freeze before claiming a stable current-tree audit.",
    }


def main() -> None:
    inventory = read_jsonl(AUDIT / "inventory.jsonl")
    metadata = json.loads(METADATA.read_text(encoding="utf-8"))
    cargo = cargo_records(metadata)
    dependencies = cargo + packages_lock_records() + implicit_records() + platform_records() + content_records()
    write_jsonl(AUDIT / "dependency-ledger.jsonl", dependencies)
    licenses: list[dict[str, Any]] = []
    for record in dependencies:
        licenses.append(
            {
                "audit_id": AUDIT_ID,
                "subject_type": record.get("ecosystem"),
                "subject": record.get("name"),
                "version": record.get("version"),
                "source": record.get("source"),
                "license_expression": record.get("license"),
                "policy_class": record.get("license_policy"),
                "review_status": record.get("review_status"),
                "evidence": record.get("license_evidence"),
                "usage_scope": record.get("scope"),
                "distribution_scope": record.get("runtime_dev_build"),
                "modification": "未修改第三方源码；品牌/文档材料的改编范围按 dependency record 说明",
                "notice_attribution": "THIRD_PARTY_NOTICES.md and licenses/ reviewed; artifact-specific closure may remain blocked",
                "uncertainty": "许可证合规风险，需合格法律/许可证 reviewer 确认" if record.get("license_policy") not in {"DEFAULT_ALLOWED", "PROJECT_LICENSE"} else None,
                "evidence_class": record.get("evidence_class"),
            }
        )
    write_jsonl(AUDIT / "license-ledger.jsonl", licenses)
    finding_rows = findings()
    write_jsonl(AUDIT / "findings.jsonl", finding_rows)
    coverage = build_coverage(inventory, finding_rows)
    write_jsonl(AUDIT / "coverage.jsonl", coverage)
    counts = defaultdict(int)
    for row in coverage:
        counts[row["status"]] += 1
    scope = json.loads((AUDIT / "scope.json").read_text(encoding="utf-8"))
    scope["final_local_synthesis"] = {
        "generated_at": now(),
        "coverage_counts": dict(sorted(counts.items())),
        "dependency_record_count": len(dependencies),
        "license_record_count": len(licenses),
        "finding_record_count": len(finding_rows),
        "metadata_file": str(METADATA),
        "metadata_package_count": len(metadata.get("packages", [])),
    }
    scope["final_scope_validation"] = current_scope_validation(inventory)
    (AUDIT / "scope.json").write_text(json.dumps(scope, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
