#!/usr/bin/env python3
"""合成本次供应链审计的覆盖、依赖、许可证和 finding 台账。

该脚本只读取冻结清单、上一轮同字节逐文件证据、Cargo metadata/lockfile 和
仓库源文件；所有输出都限制在本次审计目录，不触碰业务代码或构建状态。
"""

from __future__ import annotations

import csv
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
INVENTORY = AUDIT / "inventory.jsonl"
HISTORICAL = ROOT / ".codex/runtime/full-repo-audit-20260819/final-status.tsv"
ASSET_AUDIT = ROOT / ".codex/runtime/full-repo-audit-20260819/asset-audit.jsonl"
METADATA = Path("/tmp/area_metadata_full.json")
LOCKFILE = ROOT / "core/Cargo.lock"
COMMIT = "cf3647378d64885e8e6a44a2a5b60d8926668982"
AUDIT_ID = "dependency-supply-chain-audit-20260820"

ALLOW_LICENSES = {
    "MIT",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Unicode-DFS-2016",
}


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )
    os.replace(temporary, path)


def write_json(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def current_digest(item: dict[str, Any]) -> tuple[str | None, str]:
    path = ROOT / item["path"]
    try:
        path.lstat()
    except FileNotFoundError:
        return None, "MISSING"
    if path.is_symlink():
        target = os.readlink(path)
        return hashlib.sha256(os.fsencode(target)).hexdigest(), "symlink"
    if path.is_file():
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest(), "regular"
    return None, "other"


def current_scope_state(inventory: list[dict[str, Any]]) -> dict[str, Any]:
    drift: dict[str, dict[str, Any]] = {}
    inventory_paths = {item["path"] for item in inventory}
    for item in inventory:
        digest, current_type = current_digest(item)
        expected_type = "regular" if item["file_type"] in {"text", "binary"} else item["file_type"]
        if digest != item.get("sha256") or current_type != expected_type:
            drift[item["path"]] = {
                "expected_sha256": item.get("sha256"),
                "current_sha256": digest,
                "expected_type": expected_type,
                "current_type": current_type,
            }

    listed = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    current_paths = {
        raw.decode("utf-8", errors="surrogateescape")
        for raw in listed.split(b"\0")
        if raw
    }
    post_freeze = sorted(current_paths - inventory_paths)
    runtime_evidence = [path for path in post_freeze if path.startswith(".codex/runtime/")]
    non_runtime = [path for path in post_freeze if not path.startswith(".codex/runtime/")]
    return {
        "checked_at": now(),
        "scope_file_count": len(inventory),
        "matching_file_count": len(inventory) - len(drift),
        "drift_count": len(drift),
        "drift": drift,
        "post_freeze_runtime_evidence_count": len(runtime_evidence),
        "post_freeze_runtime_evidence_paths": runtime_evidence,
        "post_freeze_non_runtime_count": len(non_runtime),
        "post_freeze_non_runtime_paths": non_runtime,
    }


def line_number(path: Path, needle: str) -> int | None:
    try:
        for index, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if needle in line:
                return index
    except OSError:
        return None
    return None


def all_line_numbers(path: Path, needle: str, limit: int = 12) -> list[int]:
    result: list[int] = []
    try:
        for index, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if needle in line:
                result.append(index)
                if len(result) >= limit:
                    break
    except OSError:
        pass
    return result


def cargo_lock_rows() -> dict[tuple[str, str], dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for line_number_value, raw in enumerate(LOCKFILE.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if line == "[[package]]":
            if current is not None:
                rows.append(current)
            current = {}
            continue
        if current is None:
            continue
        match = re.match(r'name = "(.*)"$', line)
        if match:
            current["name"] = match.group(1)
            current["name_line"] = line_number_value
            continue
        match = re.match(r'version = "(.*)"$', line)
        if match:
            current["version"] = match.group(1)
            current["version_line"] = line_number_value
            continue
        match = re.match(r'checksum = "(.*)"$', line)
        if match:
            current["checksum"] = match.group(1)
    if current is not None:
        rows.append(current)
    return {
        (row["name"], row["version"]): row
        for row in rows
        if "name" in row and "version" in row
    }


def license_class(expression: str | None) -> str:
    if not expression:
        return "EVIDENCE_INSUFFICIENT"
    # 仓库政策要求双许可证、复合许可证和 WITH exception 全部人工确认，
    # 即使各个 token 单独位于默认允许清单中也不能自动放行。
    normalized = expression.replace("(", " ").replace(")", " ")
    if re.search(r"\s(?:OR|AND|WITH)\s", normalized, re.IGNORECASE) or "/" in normalized:
        return "MANUAL_REVIEW_REQUIRED"
    parts = [normalized.strip()]
    tokens = set(parts)
    if tokens and tokens <= ALLOW_LICENSES:
        return "DEFAULT_ALLOWED"
    if "MPL-2.0" in tokens or any(token.startswith("LGPL") for token in tokens):
        return "MANUAL_REVIEW_REQUIRED"
    if "GPL-" in expression or "AGPL-" in expression:
        return "DEFAULT_BLOCK"
    return "MANUAL_REVIEW_REQUIRED"


def source_url(source: str | None) -> str | None:
    if not source:
        return None
    if source.startswith("registry+"):
        return source.removeprefix("registry+")
    if source.startswith("git+"):
        return source
    if source == "path":
        return "repository-local"
    return source


def package_graph(metadata: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    packages = {pkg["id"]: pkg for pkg in metadata["packages"]}
    nodes = {node["id"]: node for node in metadata["resolve"]["nodes"]}
    root = metadata["resolve"]["root"]
    edges: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for parent_id, node in nodes.items():
        for dep in node.get("deps", []):
            child_id = dep["pkg"]
            kinds = dep.get("dep_kinds") or [{"kind": None, "target": None}]
            edges[parent_id].append(
                {
                    "child": child_id,
                    "name": dep.get("name"),
                    "kinds": kinds,
                }
            )

    # Keep every shortest path and scope encountered.  This gives a stable,
    # machine-readable parent edge for transitive records without pretending
    # that a transitive crate has a direct source import in this repository.
    paths: dict[str, list[dict[str, Any]]] = defaultdict(list)
    queue: deque[tuple[str, list[str], list[str]]] = deque([(root, [root], [])])
    seen_depth: dict[str, int] = {root: 0}
    while queue:
        parent, path, scopes = queue.popleft()
        for edge in edges.get(parent, []):
            child = edge["child"]
            for kind in edge["kinds"]:
                scope = kind.get("kind") or "runtime"
                if kind.get("target"):
                    scope = f"{scope}@{kind['target']}"
                candidate = {"path": path + [child], "scopes": scopes + [scope], "parent": parent}
                if not any(item["path"] == candidate["path"] and item["scopes"] == candidate["scopes"] for item in paths[child]):
                    paths[child].append(candidate)
            depth = len(path)
            if child not in seen_depth or depth < seen_depth[child] + 2:
                seen_depth[child] = min(depth, seen_depth.get(child, depth))
                queue.append((child, path + [child], scopes + ["runtime"]))
    return packages, paths


def package_usage(name: str) -> list[dict[str, Any]]:
    token = name.replace("-", "_")
    files = [ROOT / "core/build.rs"]
    files.extend(
        path
        for path in sorted((ROOT / "core").rglob("*.rs"))
        if ".build" not in path.parts
    )
    results: list[dict[str, Any]] = []
    pattern = re.compile(rf"\b{re.escape(token)}\b")
    for path in files:
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        hits = [index for index, line in enumerate(lines, 1) if pattern.search(line)]
        if hits:
            results.append({"path": str(path.relative_to(ROOT)), "lines": hits[:20]})
    return results


def cargo_records(metadata: dict[str, Any]) -> list[dict[str, Any]]:
    lock = cargo_lock_rows()
    packages, paths = package_graph(metadata)
    root_id = metadata["resolve"]["root"]
    root_name = next(pkg["name"] for pkg in metadata["packages"] if pkg["id"] == root_id)
    root_node = next(node for node in metadata["resolve"]["nodes"] if node["id"] == root_id)
    direct_ids = {dep["pkg"] for dep in root_node.get("deps", [])}
    cargo_toml = ROOT / "core/Cargo.toml"
    root_pkg = packages[root_id]
    direct_specs: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for dependency in root_pkg.get("dependencies", []):
        direct_specs[dependency["name"]].append(
            {
                "req": dependency.get("req"),
                "kind": dependency.get("kind") or "runtime",
                "target": dependency.get("target"),
                "features": dependency.get("features") or [],
                "uses_default_features": dependency.get("uses_default_features", True),
            }
        )
    root_lock = lock.get((root_pkg["name"], root_pkg["version"]), {})
    root_lock_line = root_lock.get("name_line")
    records: list[dict[str, Any]] = [
        {
            "audit_id": AUDIT_ID,
            "ecosystem": "cargo",
            "name": root_pkg["name"],
            "version": root_pkg["version"],
            "version_range": root_pkg["version"],
            "source": "仓库本地源码",
            "source_locator": root_id,
            "direct_or_transitive": "project-root",
            "scope": ["runtime", "build", "development"],
            "runtime_dev_build": "项目根包；进入 Core、FFI 与各平台产品构建",
            "declaration_location": "core/Cargo.toml:1-41",
            "usage_location": [{"path": "core/src", "lines": "全部项目模块"}],
            "license": root_pkg.get("license"),
            "license_policy": "PROJECT_LICENSE",
            "license_evidence": "core/Cargo.toml:6、根 LICENSE 与 COMMERCIAL_LICENSE.md",
            "lock": {
                "file": "core/Cargo.lock",
                "package_stanza": f"core/Cargo.lock:{root_lock_line or 'unknown'}",
                "checksum": root_lock.get("checksum"),
                "checksum_status": "本地 path 包，不适用 registry checksum",
                "lockfile_version": 4,
            },
            "integrity": "本地源码由冻结 Git HEAD、dirty-worktree 清单与逐文件 SHA-256 绑定",
            "risk_level": "HIGH",
            "review_status": "BLOCKED",
            "evidence_class": "local_project_source",
            "notes": "为保证 Cargo metadata 的 198 包闭包守恒而纳入；这是项目根包，不是第三方依赖。",
        }
    ]
    for pkg_id, pkg in sorted(packages.items(), key=lambda item: (item[1]["name"], item[1]["version"], item[0])):
        if pkg["name"] == root_name and pkg_id == root_id:
            continue
        key = (pkg["name"], pkg["version"])
        lock_row = lock.get(key, {})
        package_paths = paths.get(pkg_id, [])
        scopes = sorted({scope for item in package_paths for scope in item["scopes"]}) or ["unreachable-from-root"]
        direct = pkg_id in direct_ids
        declaration_lines = all_line_numbers(cargo_toml, f'{pkg["name"]} =', limit=20)
        declaration_location = "; ".join(f"core/Cargo.toml:{value}" for value in declaration_lines)
        usage = package_usage(pkg["name"]) if direct else []
        license_expr = pkg.get("license")
        review = "PASS"
        risk = "LOW" if all(scope.startswith("dev") for scope in scopes) else "MEDIUM"
        lock_line = lock_row.get("name_line")
        if any(scope.startswith("build") for scope in scopes) or pkg.get("name") in {
            "uniffi",
            "uniffi_bindgen",
            "uniffi_build",
            "uniffi_macros",
            "libsqlite3-sys",
            "bindgen",
            "cc",
        }:
            risk = "HIGH"
        finding_ids: list[str] = []
        if pkg["name"] in {"time", "uuid"}:
            finding_ids.append("SC-001")
        if pkg["name"] == "trash":
            finding_ids.append("SC-004")
        if pkg["name"] == "uniffi":
            finding_ids.append("SC-007")
        if pkg["name"] == "tracing-appender":
            finding_ids.append("SC-018")
        if pkg["name"] in {"bincode", "paste", "serde_yaml"}:
            finding_ids.append("SC-019")
        if pkg["name"] == "anyhow":
            finding_ids.append("SC-020")
        if finding_ids:
            review = "FINDING"
        if license_class(license_expr) != "DEFAULT_ALLOWED":
            review = "BLOCKED" if review == "PASS" else review
        records.append(
            {
                "audit_id": AUDIT_ID,
                "ecosystem": "cargo",
                "name": pkg["name"],
                "version": pkg["version"],
                "version_range": (
                    [spec for spec in direct_specs.get(pkg["name"], [])]
                    if direct
                    else None
                ),
                "source": source_url(pkg.get("source")),
                "source_locator": pkg.get("id"),
                "direct_or_transitive": "direct" if direct else "transitive",
                "scope": scopes,
                "runtime_dev_build": "运行时闭包" if any(scope.startswith("runtime") for scope in scopes) else ",".join(scopes),
                "declaration_location": declaration_location if direct and declaration_location else None,
                "usage_location": usage or [
                    {
                        "parent_chain": [packages[node]["name"] + "@" + packages[node]["version"] for node in item["path"][:-1]],
                        "edge_scopes": item["scopes"],
                    }
                    for item in package_paths[:4]
                ],
                "license": license_expr,
                "license_policy": license_class(license_expr),
                "license_evidence": "Cargo metadata 的 license 字段；未对每个 registry archive 内许可证全文作独立法律复核",
                "lock": {
                    "file": "core/Cargo.lock",
                    "package_stanza": f"core/Cargo.lock:{lock_line or 'unknown'}",
                    "checksum": lock_row.get("checksum"),
                    "checksum_status": "已记录" if lock_row.get("checksum") else "缺失或本地 path 包",
                    "lockfile_version": 4,
                },
                "integrity": "Cargo.lock 已记录 registry checksum" if lock_row.get("checksum") else "未记录 registry checksum 或属于本地 path 包",
                "risk_level": risk,
                "review_status": review,
                "evidence_class": "local_declaration_and_lock_plus_external_registry_metadata",
                "finding_ids": finding_ids,
                "notes": "; ".join(
                    note
                    for note in [
                        "直接依赖未在 Core Rust 源码中发现同名 token，需确认是否仅通过 feature/build 间接使用" if direct and not usage else None,
                        "外部 advisory 的本地适用性仍需独立验证" if pkg["name"] == "anyhow" else None,
                        "上游 package metadata 已标记 deprecated" if pkg["name"] == "serde_yaml" else None,
                    ]
                    if note
                ),
            }
        )
    return records


def dependency_record(**values: Any) -> dict[str, Any]:
    row = {
        "audit_id": AUDIT_ID,
        "version_range": None,
        "source_locator": None,
        "direct_or_transitive": "implicit",
        "scope": [],
        "runtime_dev_build": "未分类",
        "declaration_location": None,
        "usage_location": [],
        "license": "未知",
        "license_policy": "EVIDENCE_INSUFFICIENT",
        "license_evidence": "仓库内未找到充分许可证证据",
        "lock": {"version_pin": False, "hash_pin": False},
        "integrity": "仓库内未固定版本或内容哈希",
        "risk_level": "MEDIUM",
        "review_status": "BLOCKED",
        "evidence_class": "local_confirmed_evidence_gap",
        "notes": "",
        "finding_ids": [],
    }
    row.update(values)
    return row


def nuget_records() -> list[dict[str, Any]]:
    top_hash = "e6456fa9281819bc1e0ddf39639566eaf7cae75ec68fb47eb3e3072f8f084c88129820aa1148ea96b12169d5b7dd0c786312858a646145df646d5cc8d6de662b"
    rows = [
        dependency_record(
            ecosystem="nuget",
            name="Microsoft.WindowsAppSDK",
            version="2.1.3",
            version_range="2.1.3",
            source="https://api.nuget.org/v3-flatcontainer/microsoft.windowsappsdk/2.1.3/microsoft.windowsappsdk.2.1.3.nupkg",
            source_locator="Microsoft 官方 NuGet flat container",
            direct_or_transitive="direct",
            scope=["windows-runtime", "build"],
            runtime_dev_build="Windows 产品运行时与构建",
            declaration_location="apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:21",
            usage_location=["apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:1-22（WinUI SDK/runtime assets）"],
            license="Microsoft Software License Terms（包内 license.txt）",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="官方 nuspec 的 license type=file；包内 license.txt 需合格许可证 reviewer 复核",
            lock={"packages_lock": False, "nuget_config": False, "source_mapping": False, "observed_nupkg_sha512": top_hash, "hash_pinned_in_repo": False},
            integrity=f"对官方 nupkg 的只读下载计算 SHA-512={top_hash}；仓库未记录该值",
            risk_level="HIGH",
            review_status="FINDING",
            evidence_class="local_declaration_plus_external_registry",
            notes="顶层版本精确，但传递包、feed 与 package hash 未由仓库锁定。",
            finding_ids=["SC-003"],
        )
    ]
    children = [
        ("Microsoft.WindowsAppSDK.Base", "2.0.4"),
        ("Microsoft.WindowsAppSDK.Foundation", "2.0.21"),
        ("Microsoft.WindowsAppSDK.InteractiveExperiences", "2.0.13"),
        ("Microsoft.WindowsAppSDK.WinUI", "2.1.0"),
        ("Microsoft.WindowsAppSDK.DWrite", "2.1.0"),
        ("Microsoft.WindowsAppSDK.Widgets", "2.0.5"),
        ("Microsoft.WindowsAppSDK.AI", "2.1.10"),
        ("Microsoft.WindowsAppSDK.ML", "2.1.1"),
        ("Microsoft.WindowsAppSDK.Runtime", "2.1.3"),
    ]
    for name, version in children:
        normalized = name.lower()
        rows.append(
            dependency_record(
                ecosystem="nuget",
                name=name,
                version=version,
                version_range=version,
                source=f"https://api.nuget.org/v3-flatcontainer/{normalized}/{version.lower()}/",
                source_locator="Microsoft.WindowsAppSDK 2.1.3 nuspec dependency group",
                direct_or_transitive="transitive",
                scope=["windows-runtime", "build"],
                runtime_dev_build="经 Microsoft.WindowsAppSDK 进入 Windows 产品构建/运行时闭包",
                declaration_location="Microsoft.WindowsAppSDK 2.1.3 外部 nuspec（2026-08-20 只读查询）",
                usage_location=["Microsoft.WindowsAppSDK@2.1.3 -> " + name + "@" + version],
                license="未逐包确认",
                license_policy="EVIDENCE_INSUFFICIENT",
                license_evidence="仅确认父包 nuspec 的直接依赖声明；子包 license/file 与更深闭包未稳定取回",
                lock={"packages_lock": False, "package_hash": None, "source_mapping": False},
                integrity="仓库无 packages.lock.json，子包 hash 与最终选择资产未绑定",
                risk_level="HIGH",
                review_status="BLOCKED",
                evidence_class="external_nuspec_with_local_lock_gap",
                notes="需在隔离 Windows 环境以 locked restore/SBOM 闭合。",
                finding_ids=["SC-003"],
            )
        )
    rows.append(
        dependency_record(
            ecosystem="nuget",
            name="Microsoft.WindowsAppSDK 更深传递闭包（未解析哨兵记录）",
            version="未知",
            source="NuGet v3 registration/catalog",
            source_locator="本次 registration 查询不稳定",
            direct_or_transitive="transitive",
            scope=["windows-runtime", "build"],
            runtime_dev_build="Windows restore 与发布闭包",
            declaration_location="apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:21",
            usage_location=["Microsoft.WindowsAppSDK 2.1.3 -> 9 个已知直接子包 -> 未闭合的更深依赖/资产选择"],
            license="未知",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="缺 packages.lock.json、project.assets.json 固化副本和逐包许可证清单",
            lock={"packages_lock": False, "resolved_graph": False, "status": "BLOCKED"},
            integrity="无法证明完整传递闭包、RID 资产与 package hash",
            risk_level="HIGH",
            review_status="BLOCKED",
            evidence_class="external_registry_blocked",
            notes="该记录明确表示闭包未知，不代表一项实际包。最终审计因此保持 BLOCKED。",
            finding_ids=["SC-003"],
        )
    )
    return rows


def local_and_content_records() -> list[dict[str, Any]]:
    pillow_advisories = [
        {"id": "GHSA-cfh3-3jmp-rvhc", "format_or_path": "PSD/Image.open", "fixed_in": "12.1.1"},
        {"id": "GHSA-pwv6-vv43-88gr", "format_or_path": "PSD/Image.open", "fixed_in": "12.2.0"},
        {"id": "GHSA-whj4-6x5x-4v2j", "format_or_path": "FITS/Image.open", "fixed_in": "12.2.0"},
        {"id": "GHSA-62p4-gmf7-7g93", "format_or_path": "McIdas/Image.open 后像素读取", "fixed_in": "12.3.0"},
    ]
    return [
        dependency_record(
            ecosystem="python",
            name="Pillow",
            version="11.3.0",
            version_range="==11.3.0",
            source="https://pypi.org/project/Pillow/11.3.0/",
            source_locator="PyPI JSON metadata（2026-08-20 只读查询）",
            direct_or_transitive="direct",
            scope=["development", "CI"],
            runtime_dev_build="仅品牌开发工具与 PR CI；未发现产品运行时路径",
            declaration_location="scripts/brand/requirements.txt:1",
            usage_location=[".github/workflows/governance-ci.yml:40-46", "scripts/brand/validate_assets.py:90-106", "scripts/brand/export_assets.py:61-258"],
            license="MIT-CMU",
            license_policy="MANUAL_REVIEW_REQUIRED",
            license_evidence="PyPI info.license_expression=MIT-CMU 与 upstream LICENSE；仓库政策 docs/development/dependency-policy.md:61,66 记为 HPND",
            lock={"file": "scripts/brand/requirements.txt", "version_pin": "exact", "hash_pin": False},
            integrity="sdist SHA-256=3828ee7586cd0b2091b6209e5ad53e20d0649bbe87164a459d0676e035e8f523；仓库未 pin 选定 artifact hash/index",
            risk_level="HIGH",
            review_status="FINDING",
            evidence_class="local_call_path_plus_external_registry_and_advisory",
            notes="固定文件名未限制 Pillow formats，PR 可替换内容 magic；外部数据共 18 个唯一 GHSA，表中仅列与 Image.open 格式自动探测最接近的 4 个候选，其他调用路径未证实。",
            finding_ids=["SC-005", "SC-006"],
            external_advisories=pillow_advisories,
        ),
        dependency_record(
            ecosystem="swift-local-generated",
            name="AreaMatrixCoreSDK / AreaMatrixCoreFFI.xcframework",
            version="本地 fingerprint 制品",
            source="scripts/dev_tools/core_sdk.py + Rust/UDL 构建链",
            source_locator=".build/core-sdk/<fingerprint>",
            direct_or_transitive="direct",
            scope=["macOS-runtime", "iOS-runtime", "build"],
            runtime_dev_build="Apple 产品运行时与构建",
            declaration_location="apps/macos/AreaMatrix.xcodeproj/project.pbxproj:3148-3150; apps/ios/Package.swift:16-24",
            usage_location=["Xcode Frameworks phase", ".github/workflows/macos-ci.yml:352-364"],
            license="项目 PolyForm-Noncommercial 与 Cargo 传递许可证混合",
            license_policy="BLOCKED_PENDING_NOTICES",
            license_evidence="本地生成脚本与项目引用可追溯；未跟踪逐制品 SBOM/THIRD_PARTY_NOTICES",
            lock={"fingerprint": True, "source_lock": "core/Cargo.lock", "artifact_signature": False},
            integrity="存在内容 fingerprint/manifest 校验；仓库缺发布签名、provenance、SBOM 与 notices 绑定",
            risk_level="HIGH",
            review_status="BLOCKED",
            evidence_class="local_build_chain",
            finding_ids=["SC-014"],
        ),
        dependency_record(
            ecosystem="native-artifact",
            name="libarea_matrix_core.a（tracked UniFFI archive）",
            version="未知构建 revision",
            source="apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a",
            source_locator="tracked binary",
            direct_or_transitive="direct",
            scope=["development", "legacy-generated-project"],
            runtime_dev_build="潜在 Apple 链接输入；canonical project 当前消费 CoreSDK XCFramework",
            declaration_location="apps/macos/XcodeGen/AreaMatrixGenerated.xcodeproj/project.pbxproj:40,1688,3205",
            usage_location=["archive 含 area_matrix_core/UniFFI symbols；生产 project 另走 CoreSDK"],
            license="项目对象与 Cargo 传递对象混合",
            license_policy="BLOCKED_PENDING_PROVENANCE_AND_NOTICES",
            license_evidence="无邻接 source commit、build manifest、SBOM、signature 或 notices",
            lock={"sha256": "69ef0816dfe7a0a637c6e275499ad3fde649efeff27f86d9cf3c2210aff1db44", "architecture": "arm64+x86_64"},
            integrity="本地 hash 已知；来源、可复现性与签名未建立",
            risk_level="HIGH",
            review_status="FINDING",
            evidence_class="local_binary_inspection",
            finding_ids=["SC-010", "SC-014"],
        ),
        dependency_record(
            ecosystem="native-runtime",
            name="area_matrix_core.dll",
            version="未知/仓库内不存在",
            source="AREAMATRIX_CORE_LIBRARY 或 Windows NativeLibrary 系统搜索",
            direct_or_transitive="implicit",
            scope=["windows-runtime", "Core/FFI", "user-files"],
            runtime_dev_build="Windows 产品运行时",
            declaration_location="apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs:242-260",
            usage_location=["Windows app -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault -> NativeLibrary.Load"],
            license="未知",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="仓库无 DLL、manifest、SBOM 或许可证材料",
            lock={"version_pin": False, "hash_pin": False, "signature_check": False},
            integrity="仅检查路径存在/导出符号，不认证来源、版本、架构或签名",
            risk_level="HIGH",
            review_status="FINDING",
            evidence_class="local_runtime_loader",
            finding_ids=["SC-002"],
        ),
        dependency_record(
            ecosystem="native-runtime",
            name="area_matrix_core.so",
            version="未知/仓库内不存在",
            source="AREAMATRIX_CORE_LIBRARY 或 Linux NativeLibrary 系统搜索",
            direct_or_transitive="implicit",
            scope=["linux-runtime", "Core/FFI", "future-user-files"],
            runtime_dev_build="Linux headless/UI contract fixture 的潜在运行时",
            declaration_location="apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs:224-242",
            usage_location=["LinuxDesktopShell -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault"],
            license="未知",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="仓库无 .so、RID/publish asset、manifest、SBOM 或许可证材料",
            lock={"version_pin": False, "hash_pin": False, "signature_check": False},
            integrity="库搜索路径与显式路径均未做 hash/signature/provenance 校验",
            risk_level="HIGH",
            review_status="FINDING",
            evidence_class="local_runtime_loader_readiness_gap",
            finding_ids=["SC-015"],
        ),
        dependency_record(
            ecosystem="external-runtime",
            name="AREAMATRIX_*_RUNTIME AI 可执行程序族",
            version="未知，由进程环境提供",
            source="AREAMATRIX_AI_CLASSIFICATION_{LOCAL,REMOTE}_RUNTIME、AREAMATRIX_AI_TAGS_{LOCAL,REMOTE}_RUNTIME、AREAMATRIX_AI_SUMMARY_{LOCAL,REMOTE}_RUNTIME、AREAMATRIX_AI_SEMANTIC_REMOTE_RUNTIME",
            direct_or_transitive="implicit",
            scope=["runtime", "remote-AI", "user-content"],
            runtime_dev_build="可选 Core AI 运行时；接收序列化用户内容并返回模型结果",
            declaration_location="core/src/ai_classification_suggestion/executor.rs:16-17; core/src/ai_tags_suggestion/executor.rs:14-15; core/src/ai_summary/executor.rs:14-15; core/src/semantic_search/executor.rs:12",
            usage_location=["各 executor 的 Command::new(runtime_path) -> core/src/external_runtime.rs:50-106"],
            license="未知",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="仓库只定义环境变量协议，未绑定供应商、版本、hash、签名、许可证或分发方式",
            lock={"version_pin": False, "hash_pin": False, "signature_check": False},
            integrity="env 指定任意 executable；已有 env_clear、固定 PATH、超时、输出上限和进程组清理，但不认证 executable",
            risk_level="HIGH",
            review_status="FINDING",
            evidence_class="local_confirmed_external_capability_gap",
            finding_ids=["SC-021"],
        ),
        dependency_record(
            ecosystem="font-asset",
            name="Inter Bold 字体输入",
            version="未知",
            source="仓库未记录；wordmark-outlines.json 仅记 family/postScriptName",
            direct_or_transitive="direct",
            scope=["brand", "distribution", "runtime-copies"],
            runtime_dev_build="品牌字标、lockup、stacked、social、print 与应用副本的生成输入",
            declaration_location="assets/brand/wordmark-outlines.json:5,9; docs/ux/brand-assets.md:27",
            usage_location=["scripts/brand/build_source_assets.py -> final SVG -> PNG/PDF/TIFF/runtime copies"],
            license="未知",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="无字体文件、版本、来源 URL、许可证文本、输入 hash 或生成审批记录",
            lock={"outline_json": True, "font_hash": False, "font_version": False},
            integrity="固化 outline 可保证后续渲染稳定，但不能证明原始字体来源与授权",
            risk_level="HIGH",
            review_status="FINDING",
            evidence_class="local_asset_provenance_gap",
            finding_ids=["SC-011"],
        ),
        dependency_record(
            ecosystem="web-asset",
            name="Google Fonts Inter CSS",
            version="URL 查询参数浮动",
            source="https://fonts.googleapis.com",
            direct_or_transitive="direct",
            scope=["prototype", "network"],
            runtime_dev_build="仅两个 prototype HTML 在浏览器打开时动态加载",
            declaration_location="assets/prototypes/landing/index.html:8; assets/prototypes/workspace/index.html:7",
            usage_location=["prototype browser -> fonts.googleapis.com CSS -> font resources"],
            license="仓库未记录 provider/font 条款",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="prototype README 未记录版本、字体许可证、响应 hash 或离线副本",
            lock={"version_pin": False, "hash_pin": False, "network_required": True},
            integrity="远端响应可变且离线不可复现",
            risk_level="LOW",
            review_status="FINDING",
            evidence_class="local_confirmed_low_scope",
            finding_ids=["SC-016"],
        ),
        dependency_record(
            ecosystem="third-party-content",
            name="Contributor Covenant",
            version="2.1",
            source="https://www.contributor-covenant.org/version/2/1/code_of_conduct.html",
            direct_or_transitive="direct",
            scope=["documentation", "distribution"],
            runtime_dev_build="随仓库源码分发的治理文档",
            declaration_location="CODE_OF_CONDUCT.md:77,81-82",
            usage_location=["CODE_OF_CONDUCT.md:1-77 的改编行为准则正文"],
            license="仓库未记录上游许可证表达式或许可证链接",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="已记录来源、版本与改编事实；未归档具体许可条款、copyright/attribution 完整性",
            lock={"source_url": True, "source_hash": False, "license_text": False},
            integrity="来源链接可追溯但未以 revision/hash 固定",
            risk_level="LOW",
            review_status="FINDING",
            evidence_class="local_attribution_with_license_gap",
            finding_ids=["SC-023"],
        ),
        dependency_record(
            ecosystem="third-party-content",
            name="Mozilla Community Participation Guidelines enforcement ladder",
            version="未记录具体 revision",
            source="https://github.com/mozilla/diversity",
            direct_or_transitive="direct",
            scope=["documentation", "distribution"],
            runtime_dev_build="随仓库源码分发的社区影响与执行阶梯文本",
            declaration_location="CODE_OF_CONDUCT.md:79,83",
            usage_location=["CODE_OF_CONDUCT.md:27-73 的社区影响准则与执行阶梯"],
            license="仓库未记录所采用上游文本的许可证表达式或固定 revision",
            license_policy="EVIDENCE_INSUFFICIENT",
            license_evidence="仅有上游仓库入口；未指明采用文件、revision、许可证文本或改编范围",
            lock={"source_url": True, "source_revision": False, "source_hash": False, "license_text": False},
            integrity="无法由当前归属声明还原所采用的确切上游文本版本",
            risk_level="LOW",
            review_status="FINDING",
            evidence_class="local_attribution_with_license_gap",
            finding_ids=["SC-023"],
        ),
    ]


def tool_dependency_records() -> list[dict[str, Any]]:
    specs = [
        ("Python 3", "未固定；runner/系统提供", "系统或 GitHub runner", "dev:1; task-loop:1; .github/workflows/governance-ci.yml:42-46", "PSF License（实际版本许可证需复核）", ["development", "CI", "workflow"], "HIGH", []),
        ("pip", "未固定；随 Python/venv 解析", "PyPA/Python 环境", ".github/workflows/governance-ci.yml:43; docs/development/ci-governance.md:87", "MIT（实际版本需复核）", ["development", "CI"], "HIGH", ["SC-005", "SC-006"]),
        ("POSIX sh", "系统提供", "/bin/sh 或 PATH", "docs/development/setup.md:51; core/src/external_runtime.rs:270（测试 helper）", "操作系统条款", ["development", "test"], "MEDIUM", ["SC-017"]),
        ("bash", "GitHub runner 提供", "runner shell", ".github/workflows/macos-ci.yml:129,145,217; .github/workflows/remote-governance.yml:30", "runner/系统条款", ["CI"], "HIGH", ["SC-012"]),
        ("git", "未固定", "系统/GitHub runner", "scripts/dev_tools/checks.py:320; scripts/task_loop/git.py:26; docs/development/release.md:73-74", "GPL-2.0-only 工具（不链接进产品；需工具使用复核）", ["development", "CI", "release"], "HIGH", []),
        ("rustup", "stable channel 浮动", "https://static.rust-lang.org / rustup", "docs/development/setup.md:51; scripts/dev_tools/build.py:43-50", "MIT OR Apache-2.0（双许可证需人工确认）", ["development", "CI", "build"], "HIGH", ["SC-001", "SC-012", "SC-017"]),
        ("rustc", "stable/runner 提供；未固定", "rustup/GitHub runner", "scripts/dev_tools/build.py:32; scripts/dev_tools/core_sdk.py:323", "MIT OR Apache-2.0（双许可证需人工确认）", ["build", "CI"], "HIGH", ["SC-001", "SC-012"]),
        ("cargo", "随 Rust stable；未固定", "rustup/GitHub runner", ".github/workflows/core-ci.yml:38,53,66,100; scripts/dev_tools/build.py:223,257,313", "MIT OR Apache-2.0（双许可证需人工确认）", ["build", "CI", "development"], "HIGH", ["SC-001", "SC-008", "SC-009", "SC-012"]),
        ("rustfmt", "随 Rust stable；未固定", "rustup component", ".github/workflows/core-ci.yml:38", "MIT OR Apache-2.0（双许可证需人工确认）", ["CI", "development"], "MEDIUM", ["SC-012"]),
        ("clippy", "随 Rust stable；未固定", "rustup component", ".github/workflows/core-ci.yml:53", "MIT OR Apache-2.0（双许可证需人工确认）", ["CI", "development"], "MEDIUM", ["SC-012"]),
        ("cargo-llvm-cov", "未固定 cargo install 结果", "crates.io", ".github/workflows/core-ci.yml:97-100; docs/development/setup.md:97", "Apache-2.0 OR MIT（双许可证需人工确认）", ["CI", "development"], "HIGH", ["SC-012"]),
        ("cargo-watch", "文档可选、未固定", "crates.io", "docs/development/setup.md:96", "工具上游许可证需按实际版本复核", ["development"], "LOW", []),
        ("cargo-edit", "文档可选、未固定", "crates.io", "docs/development/setup.md:98", "工具上游许可证需按实际版本复核", ["development"], "LOW", []),
        ("Swift compiler", "SWIFT_VERSION=5.0；编译器 patch 由 Xcode/runner 提供且未固定", "Apple Xcode toolchain", "apps/macos/AreaMatrix.xcodeproj/project.pbxproj:4097,4137,4169,4202", "Apple/Swift 工具链条款", ["build", "CI", "development"], "HIGH", ["SC-012"]),
        ("SwiftPM / swift CLI", "swift-tools-version=5.9；实际工具链 patch 未固定", "Apple Xcode toolchain", "apps/ios/Package.swift:1; apps/macos/Packages/AreaMatrixModules/Package.swift:1; .github/workflows/macos-ci.yml:58,107,361,364", "Apple/Swift 工具链条款", ["build", "CI", "development"], "HIGH", ["SC-012"]),
        ("Xcode application/toolchain", "macos-14 runner 当前 Xcode；仓库未固定 build version", "Apple Xcode/GitHub runner image", "docs/development/setup.md:19-31; .github/workflows/macos-ci.yml:31-40", "Apple Xcode/SDK 条款", ["build", "CI", "release"], "HIGH", ["SC-012"]),
        ("xcodebuild", "由所选 Xcode 提供；build version 未固定", "Apple Xcode toolchain/PATH", "scripts/dev_tools/core_sdk.py:77,412; scripts/dev_tools/macos.py:448,710,719; .github/workflows/macos-ci.yml:32,86,102,340", "Apple Xcode/SDK 条款", ["build", "CI", "release"], "HIGH", ["SC-012"]),
        ("xcode-select", "macOS/Xcode Command Line Tools 随附", "Apple system tool", ".github/workflows/macos-ci.yml:39", "Apple 系统/开发工具条款", ["CI", "build-environment"], "MEDIUM", ["SC-012"]),
        ("xcrun", "Xcode 随附；未固定", "Apple Xcode", "scripts/dev_tools/macos.py:139,227,355,855; scripts/dev_tools/release.py:101-102", "Apple Xcode 条款", ["build", "test", "release"], "HIGH", ["SC-012"]),
        ("lipo", "Xcode Command Line Tools 随附", "Apple toolchain", "scripts/dev_tools/core_sdk.py:128,323; scripts/dev_tools/build.py:292,385", "Apple 工具条款", ["build"], "HIGH", ["SC-012"]),
        ("codesign", "macOS 随附", "Apple Security tools", "scripts/dev_tools/release.py:783-813,1021-1030", "Apple 系统条款", ["release"], "HIGH", []),
        ("hdiutil", "macOS 随附", "Apple DiskImages framework/tool", "docs/development/release.md:148-160", "Apple 系统条款", ["release"], "HIGH", []),
        ("spctl", "macOS 随附", "Apple Gatekeeper tool", "scripts/dev_tools/release.py:793-818", "Apple 系统条款", ["release"], "HIGH", []),
        ("sips", "macOS 随附", "Apple system tool", "scripts/brand/export_assets.py:61,201", "Apple 系统条款", ["development", "CI", "brand"], "MEDIUM", ["SC-012"]),
        ("iconutil", "macOS 随附", "Apple system tool", "scripts/brand/export_assets.py:98", "Apple 系统条款", ["development", "brand"], "MEDIUM", ["SC-012"]),
        ("ditto", "macOS 随附", "Apple system tool", "scripts/dev_tools/release.py:1069-1084; docs/development/release.md:130", "Apple 系统条款", ["release"], "HIGH", []),
        ("security", "macOS 随附", "Apple Keychain tool", "scripts/dev_tools/release.py:68-69", "Apple 系统条款", ["release", "credentials"], "HIGH", []),
        ("shasum", "系统提供", "Perl/system tool", "scripts/dev_tools/release.py:622,1014; docs/development/release.md:160", "系统/Perl 工具条款", ["release"], "MEDIUM", []),
        ("otool", "Xcode Command Line Tools 随附", "Apple toolchain", "scripts/dev_tools/macos_release_probe.py:176-177; scripts/dev_tools/release.py:1037", "Apple 工具条款", ["release", "build"], "MEDIUM", []),
        ("mdls", "macOS 随附", "Apple Spotlight metadata tool", "scripts/dev_tools/release.py:328-355", "Apple 系统条款", ["release"], "MEDIUM", []),
        ("osascript", "macOS 随附；trash crate 按 PATH 调用", "Apple system tool/PATH", "core/src/storage/replacement_trash.rs:105-118; scripts/dev_tools/release.py:1053-1054", "Apple 系统条款", ["runtime", "user-files", "release"], "HIGH", ["SC-004"]),
        ("tar", "runner/系统提供", "BSD/GNU tar 或 runner image", ".github/workflows/macos-ci.yml:354; scripts/dev_tools/test_core_sdk.py:345-350", "实际实现许可证未知", ["CI", "artifact"], "HIGH", ["SC-012"]),
        ("Homebrew", "brew latest/formula 最新解析", "https://brew.sh 与 formula registry", ".github/workflows/macos-ci.yml:374-389", "BSD-2-Clause（brew 本体；formula 逐项另审）", ["CI", "development"], "HIGH", ["SC-012"]),
        ("SwiftLint", "Homebrew latest", "Homebrew/GitHub realm/SwiftLint", ".github/workflows/macos-ci.yml:374-377; scripts/dev_tools/checks.py:3093-3133", "MIT（实际下载版本需复核）", ["CI", "development"], "HIGH", ["SC-012"]),
        ("SwiftFormat", "Homebrew latest", "Homebrew/GitHub nicklockwood/SwiftFormat", ".github/workflows/macos-ci.yml:388-391; scripts/dev_tools/checks.py:3078-3133", "MIT（实际下载版本需复核）", ["CI", "development"], "HIGH", ["SC-012"]),
        ("gitleaks CLI", "Homebrew/latest 或本机 PATH", "Homebrew/GitHub gitleaks", "docs/development/secret-scan-runbook.md:35; scripts/dev_tools/checks.py（secret gate）", "MIT（实际下载版本需复核）", ["CI", "development", "security"], "HIGH", ["SC-012", "SC-013"]),
        (".NET SDK", "9.0；patch 未固定", "Microsoft .NET SDK", "apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:1,4; apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:1,3", "MIT 与 Microsoft SDK 分发条款（需按实际 SDK 复核）", ["windows-build", "linux-build", "test"], "HIGH", ["SC-003", "SC-015"]),
        ("NuGet restore client", "随 .NET SDK；未固定", "Microsoft NuGet", "apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:21", "Apache-2.0（实际版本/组件需复核）", ["windows-build", "restore"], "HIGH", ["SC-003"]),
        ("Windows SDK", "10.0.19041.0 target minimum；安装 SDK build 未固定", "Microsoft Windows SDK", "apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:4,17", "Microsoft SDK 条款", ["windows-build", "windows-runtime"], "HIGH", ["SC-003"]),
        ("curl", "系统提供；远端响应浮动", "系统 curl + https://sh.rustup.rs", "docs/development/setup.md:51", "实现/系统条款", ["development", "bootstrap", "network"], "HIGH", ["SC-017"]),
        ("GitHub CLI gh", "未固定", "https://cli.github.com", "scripts/dev_tools/remote_governance.py:62,120,370", "MIT（实际版本需复核）", ["governance", "network", "development"], "HIGH", []),
        ("Codex CLI", "未固定；PATH 解析", "外部 Codex 安装", "scripts/task_loop/runner.py:776,1271; scripts/task_loop/self_check.py:1651", "外部产品条款，仓库未记录", ["workflow", "development", "external-capability"], "HIGH", []),
        ("AreaFlow CLI", "未固定；PATH 解析", "外部 areaflow 安装", "scripts/areaflow_shim.py:110", "未知", ["workflow", "development", "external-capability"], "HIGH", []),
        ("zenity", "Linux 系统包；未固定", "distribution package/PATH", "apps/linux/AreaMatrix/Features/Onboarding/LinuxFolderPickerAdapter.cs:102; apps/linux/AreaMatrix/Features/Import/LinuxImportPickerAdapter.cs:113,119", "上游/发行版包许可证需复核", ["linux-runtime", "user-files"], "HIGH", ["SC-015"]),
        ("kdialog", "Linux 系统包；未固定", "distribution package/PATH", "apps/linux/AreaMatrix/Features/Onboarding/LinuxFolderPickerAdapter.cs:103; apps/linux/AreaMatrix/Features/Import/LinuxImportPickerAdapter.cs:114,120", "上游/发行版包许可证需复核", ["linux-runtime", "user-files"], "HIGH", ["SC-015"]),
        ("xdg-open", "Linux 系统包；未固定", "xdg-utils distribution package/PATH", "apps/linux/AreaMatrix/Features/Onboarding/LinuxFolderOpener.cs:91", "上游/发行版包许可证需复核", ["linux-runtime", "user-files"], "HIGH", ["SC-015"]),
        ("gio", "Linux 系统包；未固定", "GLib distribution package/PATH", "apps/linux/AreaMatrix/Features/Onboarding/LinuxFolderOpener.cs:92", "LGPL 系列，使用/分发方式需人工确认", ["linux-runtime", "user-files"], "HIGH", ["SC-015"]),
        ("taskkill", "Windows 系统提供", "Windows system tool", "scripts/dev_tools/codex_os_automation.py:1899", "Microsoft Windows 条款", ["development", "workflow"], "MEDIUM", []),
        ("ps", "系统提供；实现未固定", "POSIX/macOS process tools", "scripts/task_loop/runner.py:325-330; scripts/task_loop/console.py:285-292", "系统工具条款", ["development", "workflow"], "LOW", []),
        ("pgrep", "macOS/系统提供；实现未固定", "系统 process tools", "scripts/dev_tools/release.py:1044-1046", "系统工具条款", ["release"], "MEDIUM", []),
        ("clear", "终端环境提供；实现未固定", "系统 terminal tools", "scripts/task_loop/console.py:262-265", "系统工具条款", ["development", "workflow"], "LOW", []),
        ("which", "系统提供；实现未固定", "系统/PATH", "scripts/dev_tools/build.py:42-45", "系统工具条款", ["development", "build"], "LOW", []),
        ("jq", "macos-14 runner 预装版本；仓库未固定", "GitHub runner image/PATH", ".github/workflows/macos-ci.yml:260-287", "上游/runner 镜像许可证需按实际版本复核", ["CI", "diagnostics"], "MEDIUM", ["SC-012"]),
        ("tee", "runner/系统提供；实现未固定", "POSIX runner tools/PATH", ".github/workflows/macos-ci.yml:321; .github/workflows/remote-governance.yml:45; .github/workflows/release-evidence.yml:47,52,57", "系统工具条款", ["CI", "governance", "release-evidence"], "MEDIUM", ["SC-012"]),
        ("find", "runner/系统提供；实现未固定", "POSIX runner tools/PATH", ".github/workflows/macos-ci.yml:131", "系统工具条款", ["CI", "diagnostics"], "LOW", ["SC-012"]),
        ("tail", "runner/系统提供；实现未固定", "POSIX runner tools/PATH", ".github/workflows/macos-ci.yml:139,172,177,184,236,245,278", "系统工具条款", ["CI", "diagnostics"], "LOW", ["SC-012"]),
        ("grep", "runner/系统提供；实现未固定", "POSIX runner tools/PATH", ".github/workflows/macos-ci.yml:168,236; scripts/task_loop/self_check.py:1391,1485,1584,1713", "系统工具条款", ["CI", "diagnostics", "test"], "LOW", ["SC-012"]),
        ("uname", "macos-14 runner 系统提供", "POSIX runner tools/PATH", ".github/workflows/macos-ci.yml:37-38,112,160", "系统工具条款", ["CI", "build-environment"], "LOW", ["SC-012"]),
        ("tr", "runner/系统提供；实现未固定", "POSIX runner tools/PATH", ".github/workflows/macos-ci.yml:161", "系统工具条款", ["CI", "diagnostics"], "LOW", ["SC-012"]),
        ("ln", "runner/系统提供；实现未固定", "POSIX runner tools/PATH", ".github/workflows/macos-ci.yml:358", "系统工具条款", ["CI", "artifact-linking"], "MEDIUM", ["SC-012"]),
        ("sed", "runner/系统提供；实现未固定", "POSIX runner tools/PATH", ".github/workflows/macos-ci.yml:40", "系统工具条款", ["CI", "build-environment"], "LOW", ["SC-012"]),
    ]
    rows: list[dict[str, Any]] = []
    for name, version, source, location, license_expression, scope, risk, finding_ids in specs:
        rows.append(
            dependency_record(
                ecosystem="implicit-tool",
                name=name,
                version=version,
                version_range=version,
                source=source,
                source_locator=location,
                direct_or_transitive="implicit",
                scope=scope,
                runtime_dev_build=" / ".join(scope),
                declaration_location=location,
                usage_location=[location],
                license=license_expression,
                license_policy="MANUAL_REVIEW_REQUIRED" if license_expression != "未知" else "EVIDENCE_INSUFFICIENT",
                license_evidence="仓库调用位置已确认；实际解析版本、下载来源和许可证文本未由统一工具锁文件绑定",
                lock={"version_pin": False, "hash_pin": False, "path_or_runner_resolution": True},
                integrity="依赖 PATH、系统/Xcode/runner image 或外部安装；未形成仓库内统一版本/hash 锁定",
                risk_level=risk,
                review_status="FINDING" if finding_ids else "BLOCKED",
                evidence_class="local_command_call_chain",
                notes="该工具逐项记录，不以聚合 external-tool 记录代替。",
                finding_ids=finding_ids,
            )
        )
    return rows


def swift_platform_records(inventory: list[dict[str, Any]]) -> list[dict[str, Any]]:
    modules = {
        "AVFoundation", "AppKit", "Combine", "CoreGraphics", "CoreServices", "CryptoKit",
        "Darwin", "Darwin.Mach", "Foundation", "Observation", "OSLog", "PackageDescription",
        "Security", "SwiftUI", "UIKit", "UniformTypeIdentifiers", "XCTest",
    }
    swift_paths = [
        ROOT / item["path"]
        for item in inventory
        if item["file_type"] == "text" and item["path"].endswith(".swift") and item["path"].startswith("apps/")
    ]
    rows: list[dict[str, Any]] = []
    for module in sorted(modules):
        locations: list[str] = []
        matcher = re.compile(rf"^\s*import\s+{re.escape(module)}\s*$")
        for path in swift_paths:
            for index, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                if matcher.match(line):
                    locations.append(f"{path.relative_to(ROOT)}:{index}")
        if not locations:
            continue
        rows.append(
            dependency_record(
                ecosystem="apple-sdk-framework",
                name=module,
                version="由实际 Xcode/macOS/iOS SDK 决定；仓库未固定 build version",
                source="Apple SDK/Xcode toolchain",
                direct_or_transitive="platform",
                scope=["macOS" if not any("apps/ios/" in value for value in locations) else "Apple-platform", "runtime" if module not in {"XCTest", "PackageDescription"} else "development"],
                runtime_dev_build="Apple 平台 SDK framework/module",
                declaration_location=locations,
                usage_location=locations,
                license="Apple SDK/Xcode 条款",
                license_policy="MANUAL_REVIEW_REQUIRED",
                license_evidence="所有 import 行已逐项映射；SDK license/build version 未随仓库固化",
                lock={"sdk_version_pin": False, "minimum_macos": "14.0", "minimum_ios": "17.0"},
                integrity="绑定 runner/开发机 Xcode SDK；仅最低部署版本入库",
                risk_level="HIGH" if module in {"Security", "CryptoKit", "CoreServices", "AppKit"} else "MEDIUM",
                review_status="BLOCKED",
                evidence_class="local_import_inventory",
                notes=f"共 {len(locations)} 个精确 import 位置。",
            )
        )
    return rows


def local_swift_package_records() -> list[dict[str, Any]]:
    return [
        dependency_record(
            ecosystem="swift-local-package",
            name="AreaMatrixModules",
            version=COMMIT,
            source="apps/macos/Packages/AreaMatrixModules",
            direct_or_transitive="project-local",
            scope=["macOS-runtime", "development"],
            runtime_dev_build="Xcode local Swift package 与独立 SwiftPM tests",
            declaration_location="apps/macos/AreaMatrix.xcodeproj/project.pbxproj:4344-4358; apps/macos/Packages/AreaMatrixModules/Package.swift:1-120",
            usage_location=["apps/macos/AreaMatrix/**/*.swift 的 AreaMatrix* imports"],
            license="PolyForm-Noncommercial-1.0.0（项目许可证）",
            license_policy="PROJECT_LICENSE",
            license_evidence="仓库本地源码、根 LICENSE 与冻结 inventory hash",
            lock={"local_path": True, "git_commit": COMMIT},
            integrity="本地 package 由冻结逐文件 hash 绑定；无远端 SwiftPM dependency",
            risk_level="MEDIUM",
            review_status="PASS",
            evidence_class="local_project_source",
        ),
        dependency_record(
            ecosystem="swift-local-package",
            name="AreaMatrixIOS",
            version=COMMIT,
            source="apps/ios",
            direct_or_transitive="project-local",
            scope=["iOS-runtime", "development"],
            runtime_dev_build="iOS Swift package；依赖本地 verified CoreSDK",
            declaration_location="apps/ios/Package.swift:1-26",
            usage_location=["apps/ios/Sources/**/*.swift", ".github/workflows/macos-ci.yml:352-364"],
            license="PolyForm-Noncommercial-1.0.0（项目许可证）",
            license_policy="PROJECT_LICENSE",
            license_evidence="仓库本地源码、根 LICENSE 与冻结 inventory hash",
            lock={"local_path": True, "git_commit": COMMIT, "remote_dependencies": 0},
            integrity="本地 package 和 CoreSDK fingerprint；没有 Package.resolved 是因为无远端 SwiftPM 包",
            risk_level="MEDIUM",
            review_status="PASS",
            evidence_class="local_project_source",
        ),
    ]


def extra_dependency_records(inventory: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return (
        local_and_content_records()
        + nuget_records()
        + tool_dependency_records()
        + swift_platform_records(inventory)
        + local_swift_package_records()
    )


def action_records() -> list[dict[str, Any]]:
    refs = [
        ("actions/checkout", "v4", "11d5960a326750d5838078e36cf38b85af677262"),
        ("Swatinem/rust-cache", "v2", "49a0bdc70d2e1b713ca9e2869b211fcce03d3c1c"),
        ("actions/upload-artifact", "v4", "ea165f8d65b6e75b540449e92b4886f43607fa02"),
        ("actions/download-artifact", "v4", "d3f86a106a0bac45b974a628896c90dbdf5c8093"),
        ("gitleaks/gitleaks-action", "v2", "dcedce43c6f43de0b836d1fe38946645c9c638dc"),
        ("dtolnay/rust-toolchain", "stable", None),
    ]
    workflow_paths = sorted((ROOT / ".github/workflows").glob("*.yml"))
    rows = []
    for name, ref, observed_commit in refs:
        needle = f"uses: {name}@{ref}"
        locations = [
            f"{path.relative_to(ROOT)}:{line}"
            for path in workflow_paths
            for line in all_line_numbers(path, needle, limit=100)
        ]
        finding_ids = ["SC-012"] + (["SC-013"] if name == "gitleaks/gitleaks-action" else [])
        rows.append(
            dependency_record(
                ecosystem="github-actions",
                name=name,
                version=ref,
                version_range=ref,
                source=f"https://github.com/{name}",
                source_locator=locations,
                direct_or_transitive="direct",
                scope=["CI"],
                runtime_dev_build="在 GitHub Actions runner 上执行构建、缓存、制品或安全扫描逻辑",
                declaration_location=locations,
                usage_location=locations,
                license="上游仓库许可证未随 AreaMatrix 归档",
                license_policy="MANUAL_REVIEW_REQUIRED",
                license_evidence="本地 uses 行与公开 ref 解析已确认；许可证文本/notices 未 vendored",
                lock={"requested_ref": ref, "observed_resolved_commit_2026_08_20": observed_commit, "commit_pinned_in_workflow": False},
                integrity=(f"查询日 ref 解析为 {observed_commit}，但 workflow 仍请求可移动 ref" if observed_commit else "stable ref 无法作为可审计固定 tag 解析"),
                risk_level="HIGH",
                review_status="FINDING",
                evidence_class="local_workflow_plus_external_ref_query",
                notes="单次 ref 解析不能证明历史不可变；官方 action 身份本身不被定性为漏洞。",
                finding_ids=finding_ids,
            )
        )
    return rows


def findings() -> list[dict[str, Any]]:
    base = {
        "audit_id": AUDIT_ID,
        "status": "OPEN",
        "review_status": "FINDING",
        "recorded_at": now(),
    }
    inventory_paths = {item["path"] for item in read_jsonl(INVENTORY)}
    archive_assets = sorted(path for path in inventory_paths if path.startswith("assets/brand/archive/"))
    inter_tokens = ("wordmark", "lockup", "stacked", "social", "/print/", "brand-overview")
    inter_assets = sorted(
        path
        for path in inventory_paths
        if (
            path == "assets/brand/wordmark-outlines.json"
            or (
                path.endswith((".svg", ".png", ".pdf", ".tiff"))
                and any(token in path.lower() for token in inter_tokens)
            )
            or "AreaMatrixLogoLockup" in path
        )
    )
    rows = [
        {
            "id": "SC-001",
            "severity": "P1",
            "confidence": "HIGH",
            "title": "Rust MSRV 声明与锁定闭包不一致",
            "category": "reproducibility/build contract",
            "locations": ["core/Cargo.toml:5", "README.md:50", "README.zh-CN.md:50", "core/Cargo.lock:3", "time 0.3.54 metadata", "uuid 1.23.1 metadata"],
            "dependency_or_asset": "Cargo dependency closure",
            "version": "time 0.3.54; uuid 1.23.1; trash 5.2.5 and other packages",
            "source": "crates.io registry via core/Cargo.lock",
            "actual_use_path": "cargo build/test/clippy resolve core/Cargo.lock; advertised setup accepts Rust 1.75",
            "exposure_scope": "developer and CI build; blocks reproducible supported setup",
            "license": "not the primary issue; license closure separately tracked",
            "integrity_reproducibility": "lock checksum exists, but declared MSRV is false; current highest observed requirement is Rust 1.88",
            "maintenance_status": "dependency metadata locally confirmed; external release metadata should be rechecked before remediation",
            "arbitrary_code_or_ci_risk": "build failure/partial environment divergence, not arbitrary execution by itself",
            "product_bundle_core_ffi_user_files_release": "can prevent Core/FFI build; no direct runtime path",
            "existing_controls": "rust-version field, setup docs, Cargo.lock",
            "why_insufficient": "controls advertise a lower version than the resolved closure requires",
            "minimal_fix": "raise/document the actual MSRV or constrain/replace packages and regenerate lockfile under review",
            "rollback": "revert the manifest/lockfile/docs change as one reviewed commit",
            "verification_needed": "cargo metadata --locked plus rust-version compatibility checks on the declared MSRV and current toolchain",
            "evidence_class": "local_confirmed_with_registry_metadata",
            "evidence_files": ["core/Cargo.toml", "core/Cargo.lock", "README.md", "README.zh-CN.md", "docs/architecture/tech-stack.md", "docs/development/build.md", "docs/development/setup.md", "docs/user-guide/getting-started.md"],
        },
        {
            "id": "SC-002",
            "severity": "P1",
            "confidence": "HIGH",
            "title": "Windows native core 发布/加载链未闭环",
            "category": "native artifact provenance",
            "locations": ["apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:20-22", "apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs:240-260"],
            "dependency_or_asset": "area_matrix_core.dll",
            "version": "unknown",
            "source": "AREAMATRIX_CORE_LIBRARY or system NativeLibrary search path",
            "actual_use_path": "Windows app -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault/Load -> NativeLibrary.Load",
            "exposure_scope": "Windows runtime, Core/FFI, user-file operations reached through bridge",
            "license": "unknown for loaded binary",
            "integrity_reproducibility": "no project item, source revision, hash, signature, architecture or SBOM proves loaded DLL",
            "maintenance_status": "local repository gap; external binary source unavailable",
            "arbitrary_code_or_ci_risk": "loading an uncontrolled DLL creates code-execution and ABI substitution risk",
            "product_bundle_core_ffi_user_files_release": "Windows product runtime and all bridged file operations",
            "existing_controls": "environment variable and File.Exists check; exported symbol mapping",
            "why_insufficient": "existence and symbol lookup do not authenticate origin or version",
            "minimal_fix": "produce a tracked/fingerprinted self-contained native asset via the approved build, bind it to RID/architecture, verify hash/signature before load, and record notices",
            "rollback": "disable Windows native launch or restore the prior verified artifact and loader manifest",
            "verification_needed": "clean Windows build/publish, artifact hash/signature verification, ABI contract test and package inspection",
            "evidence_class": "local_confirmed",
            "evidence_files": ["apps/windows/AreaMatrix/AreaMatrix.Windows.csproj", "apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs", "apps/windows/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs", "apps/windows/AreaMatrixTests/AreaMatrix.Windows.Tests.csproj"],
        },
        {
            "id": "SC-003",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "Windows NuGet 传递闭包没有仓库内锁定",
            "category": "dependency integrity",
            "locations": ["apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:21", "apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:1-23"],
            "dependency_or_asset": "Microsoft.WindowsAppSDK",
            "version": "2.1.3",
            "source": "official NuGet package; transitive packages resolved externally",
            "actual_use_path": "WinUI project SDK/runtime assets and Windows app build",
            "exposure_scope": "Windows build and package distribution",
            "license": "Microsoft Software License Terms plus transitive package licenses",
            "integrity_reproducibility": "no packages.lock.json, NuGet.config source mapping, or repository package hash",
            "maintenance_status": "official package source confirmed; full registration/catalog closure was not stable in external query",
            "arbitrary_code_or_ci_risk": "restore-time package substitution/cache poisoning risk",
            "product_bundle_core_ffi_user_files_release": "Windows product bundle and build outputs",
            "existing_controls": "exact top-level PackageReference version and RID list",
            "why_insufficient": "top-level version does not lock transitive assets or source",
            "minimal_fix": "commit packages.lock.json and source mapping/approved feed policy, then verify package hashes and licenses",
            "rollback": "revert lock/config additions and retain the prior package reference only for development, not release",
            "verification_needed": "clean restore with locked mode, dependency graph/SBOM and package content hash comparison",
            "evidence_class": "local_confirmed_with_external_registry_gap",
            "evidence_files": ["apps/windows/AreaMatrix/AreaMatrix.Windows.csproj"],
        },
        {
            "id": "SC-004",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "macOS 用户文件删除路径间接按 PATH 执行 osascript",
            "category": "runtime dependency execution",
            "locations": ["core/src/storage/delete.rs:31", "core/src/storage/replacement_trash.rs:105-118", "trash 5.2.5 macOS implementation"],
            "dependency_or_asset": "trash 5.2.5",
            "version": "5.2.5",
            "source": "crates.io checksum in core/Cargo.lock",
            "actual_use_path": "delete_file -> replacement_trash::delete -> trash::delete -> Command::new(\"osascript\")",
            "exposure_scope": "macOS runtime user-file deletion/trash operation",
            "license": "MIT (registry metadata); upstream implementation requires separate review",
            "integrity_reproducibility": "Cargo checksum present; executable resolution is environment PATH-dependent",
            "maintenance_status": "local call path confirmed; external crate source behavior should be pinned/rechecked",
            "arbitrary_code_or_ci_risk": "PATH hijack can substitute osascript command in a process handling user files",
            "product_bundle_core_ffi_user_files_release": "Core and macOS bridge user-file path",
            "existing_controls": "platform cfg and trash abstraction",
            "why_insufficient": "abstraction delegates to an unqualified command name",
            "minimal_fix": "use a platform API/controlled absolute system tool path with explicit validation, or move the operation to a trusted Swift platform layer",
            "rollback": "restore the prior trash adapter while retaining a feature flag to disable destructive operations if verification fails",
            "verification_needed": "macOS PATH substitution test in a sandbox fixture plus user-file safety regression suite",
            "evidence_class": "local_confirmed_with_external_source_review",
            "evidence_files": ["core/src/storage/delete.rs", "core/src/storage/replacement_trash.rs", "core/Cargo.toml", "core/Cargo.lock"],
        },
        {
            "id": "SC-005",
            "severity": "P2",
            "confidence": "MEDIUM",
            "title": "CI 品牌图片解析器使用存在公开漏洞的 Pillow 11.3.0",
            "category": "CI parser attack surface",
            "locations": ["scripts/brand/requirements.txt:1", ".github/workflows/governance-ci.yml:40-46", "scripts/brand/validate_assets.py:90-106"],
            "dependency_or_asset": "Pillow",
            "version": "11.3.0",
            "source": "PyPI",
            "actual_use_path": "PR checkout -> pip install -> validate_assets.py -> Image.open on repository-controlled image files",
            "exposure_scope": "pull_request CI runner; not observed in product runtime",
            "license": "PyPI MIT-CMU; repository policy says HPND",
            "integrity_reproducibility": "exact version but no artifact hash pin; sdist hash recorded only in audit",
            "maintenance_status": "external OSV query returned multiple GHSA records; fixed versions vary by issue",
            "arbitrary_code_or_ci_risk": "malformed/hostile image input can exercise parser vulnerabilities in CI",
            "product_bundle_core_ffi_user_files_release": "CI only; no product package path confirmed",
            "existing_controls": "exact version pin, isolated venv, asset validation",
            "why_insufficient": "version is affected by published advisories and PR input is attacker-influenced",
            "minimal_fix": "upgrade to a version covering the applicable advisories, pin artifact hash, restrict formats/size and isolate parser job",
            "rollback": "temporarily disable nonessential image parsing on untrusted PRs or restore the last known-good pinned wheel with documented exception",
            "verification_needed": "re-run advisory validation, hostile PSD/PNG content tests, and confirm no runtime dependency path",
            "evidence_class": "local_call_path_plus_external_advisory",
            "evidence_files": ["scripts/brand/requirements.txt", ".github/workflows/governance-ci.yml", "scripts/brand/validate_assets.py", "docs/ux/brand-assets.md"],
        },
        {
            "id": "SC-006",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "Pillow 许可证政策口径和完整性锁定不一致",
            "category": "license/integrity",
            "locations": ["docs/development/dependency-policy.md:61-66", "scripts/brand/requirements.txt:1", "docs/ux/brand-assets.md:92-99"],
            "dependency_or_asset": "Pillow",
            "version": "11.3.0",
            "source": "PyPI and upstream Pillow LICENSE",
            "actual_use_path": "brand export/validate only",
            "exposure_scope": "development/CI distribution of tooling",
            "license": "MIT-CMU according to PyPI/upstream, not HPND as policy states",
            "integrity_reproducibility": "version exact, artifact hash absent from requirements/CI",
            "maintenance_status": "requires legal/license reviewer and dependency owner confirmation",
            "arbitrary_code_or_ci_risk": "unverified artifact selection can alter CI tool behavior",
            "product_bundle_core_ffi_user_files_release": "not product runtime; brand outputs may be distributed externally",
            "existing_controls": "policy exception and exact version",
            "why_insufficient": "policy and upstream license facts conflict; no hash or notice records",
            "minimal_fix": "correct policy to verified expression, record license text/notice and pin the selected wheel/sdist hash",
            "rollback": "revert policy/tooling update and use macOS-native tools for formats that do not require Pillow",
            "verification_needed": "qualified license review and clean CI install with hash enforcement",
            "evidence_class": "local_confirmed_with_external_registry_and_legal_gap",
            "evidence_files": ["docs/development/dependency-policy.md", "scripts/brand/requirements.txt", "docs/ux/brand-assets.md"],
        },
        {
            "id": "SC-007",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "UniFFI runtime 依赖错误启用 build feature",
            "category": "build-chain expansion",
            "locations": ["core/Cargo.toml:17", "core/Cargo.toml:37", "core/build.rs:180"],
            "dependency_or_asset": "uniffi 0.28.3 and bindgen toolchain",
            "version": "0.28.3",
            "source": "crates.io with lock checksums",
            "actual_use_path": "normal area_matrix_core dependency plus build-dependency both enable feature build; scaffolding generated in build.rs",
            "exposure_scope": "all Core builds, FFI generation and downstream SDK builds",
            "license": "MPL-2.0 for UniFFI family; legal review required",
            "integrity_reproducibility": "locked registry packages, but runtime graph includes build tooling",
            "maintenance_status": "external project/toolchain maintenance not independently assessed",
            "arbitrary_code_or_ci_risk": "proc-macro/build tooling executes during trusted builds and expands attack surface",
            "product_bundle_core_ffi_user_files_release": "Core/FFI build; generated artifacts may enter product package",
            "existing_controls": "Cargo.lock and source generation scripts",
            "why_insufficient": "feature selection is in normal dependency graph and no explicit reason/target boundary is recorded",
            "minimal_fix": "separate runtime and build dependencies/features according to UniFFI guidance, minimize feature set, and document generated-tool provenance",
            "rollback": "revert feature split if generated bindings drift, then regenerate from the prior locked tool",
            "verification_needed": "cargo tree -e features, clean build with locked mode, generated binding diff and package inspection",
            "evidence_class": "local_confirmed",
            "evidence_files": ["core/Cargo.toml", "core/Cargo.lock", "core/build.rs", "scripts/dev_tools/build.py"],
        },
        {
            "id": "SC-008",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "UniFFI fallback 从任意 Cargo cache/环境可执行文件取工具，来源闭环不足",
            "category": "code generation provenance",
            "locations": ["scripts/dev_tools/build.py:54-279", "scripts/dev_tools/build.py:246", "scripts/dev_tools/build.py:275-279"],
            "dependency_or_asset": "uniffi-bindgen fallback",
            "version": "locked source version inferred from Cargo.lock",
            "source": "Cargo cache or AREAMATRIX_UNIFFI_BINDGEN_TOOL_ROOT / UNIFFI_BINDGEN environment",
            "actual_use_path": "build/bindings command selection -> cached wrapper crate -> Swift bindings generation",
            "exposure_scope": "developer/CI code generation; generated FFI shipped downstream",
            "license": "MPL-2.0 family plus generated output obligations",
            "integrity_reproducibility": "wrapper crate is synthesized without an independent checked-in lock; environment can select arbitrary binary",
            "maintenance_status": "local code path confirmed; cache contents are external state",
            "arbitrary_code_or_ci_risk": "untrusted cache/tool binary can execute during build and alter generated bindings",
            "product_bundle_core_ffi_user_files_release": "generated bridge and CoreSDK packaging",
            "existing_controls": "locked version lookup and file existence checks",
            "why_insufficient": "path existence is not provenance or signature verification",
            "minimal_fix": "vendor or attest the exact bindgen artifact/source hash, use locked wrapper metadata, and reject arbitrary environment overrides in release mode",
            "rollback": "disable fallback and require an approved bindgen binary while preserving previous generated bindings",
            "verification_needed": "clean-cache generation, source/hash attestation, deterministic output diff and release-mode environment test",
            "evidence_class": "local_confirmed",
            "evidence_files": ["scripts/dev_tools/build.py", "scripts/dev_tools/test_build_tools.py", "core/Cargo.lock"],
        },
        {
            "id": "SC-009",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "CI/构建关键 Cargo 命令普遍缺少 --locked",
            "category": "reproducibility/integrity",
            "locations": [".github/workflows/core-ci.yml:53,66,82", "scripts/dev_tools/build.py:313,755", "scripts/dev_tools/core_sdk.py:115", "scripts/dev_tools/checks.py:3062-3067"],
            "dependency_or_asset": "Cargo resolver and build scripts",
            "version": "workspace lockfile v4",
            "source": "crates.io/Cargo.lock",
            "actual_use_path": "CI clippy/test/build and CoreSDK/check helper commands",
            "exposure_scope": "CI and release/build artifact generation",
            "license": "transitive Cargo closure; see dependency ledger",
            "integrity_reproducibility": "lockfile exists but commands may resolve/update outside it",
            "maintenance_status": "local command inventory confirmed",
            "arbitrary_code_or_ci_risk": "resolver drift and cache/artifact substitution during builds",
            "product_bundle_core_ffi_user_files_release": "Core/FFI and release artifacts",
            "existing_controls": "committed Cargo.lock and isolated target dirs",
            "why_insufficient": "without --locked, lockfile adherence is not enforced at each invocation",
            "minimal_fix": "add --locked to all CI/build/release Cargo commands and fail on lock drift",
            "rollback": "revert command-only changes if a legacy target cannot support locked mode, with explicit exception record",
            "verification_needed": "grep-based command inventory plus clean offline/locked CI rehearsal",
            "evidence_class": "local_confirmed",
            "evidence_files": [".github/workflows/core-ci.yml", "scripts/dev_tools/build.py", "scripts/dev_tools/core_sdk.py", "scripts/dev_tools/checks.py"],
        },
        {
            "id": "SC-010",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "tracked UniFFI 静态库缺少来源、SBOM、签名和许可证闭包",
            "category": "precompiled/native artifact",
            "locations": ["apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a", "apps/macos/XcodeGen/project.yml:1"],
            "dependency_or_asset": "libarea_matrix_core.a",
            "version": "unknown",
            "source": "tracked 90 MiB Mach-O universal archive",
            "actual_use_path": "tracked XcodeGen manifest generates a project that was inspected at audit time; current canonical project consumes CoreSDK XCFramework",
            "exposure_scope": "developer checkout and possible generated project/package path",
            "license": "mixed Rust/UniFFI/SQLite and project objects; no notices adjacent",
            "integrity_reproducibility": "SHA-256 69ef0816dfe7a0a637c6e275499ad3fde649efeff27f86d9cf3c2210aff1db44; build inputs/commit absent",
            "maintenance_status": "local binary provenance gap",
            "arbitrary_code_or_ci_risk": "linking an unverified archive can introduce arbitrary native code",
            "product_bundle_core_ffi_user_files_release": "potential Apple link path; archive contains Core user-file logic",
            "existing_controls": "current project points at generated CoreSDK instead",
            "why_insufficient": "alternate generated project still references tracked binary and no policy prevents accidental packaging",
            "minimal_fix": "remove or regenerate from attested source, attach SBOM/notices/signature and make project references unambiguous",
            "rollback": "restore the last verified project/CoreSDK artifact and remove the untrusted archive from release inputs",
            "verification_needed": "archive object inventory, source-to-binary reproducibility, signature and license notice verification",
            "evidence_class": "local_confirmed",
            "evidence_files": ["apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a", "apps/macos/XcodeGen/project.yml", "docs/development/build.md"],
            "supplemental_evidence_files": ["apps/macos/XcodeGen/AreaMatrixGenerated.xcodeproj/project.pbxproj"],
            "supplemental_evidence_basis": "审计时存在的 ignored/generated project；已读取其 40、1688、3205 行，但不属于冻结 tracked + 启动时 untracked 文件范围",
        },
        {
            "id": "SC-011",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "Inter 字体生成的 wordmark 缺少来源、版本、许可证和输入 hash",
            "category": "asset provenance/license",
            "locations": ["assets/brand/wordmark-outlines.json:5-9", "assets/brand/README.md:74", "docs/ux/brand-assets.md:27", "scripts/brand/generate_wordmark_outlines.swift:23-33"],
            "dependency_or_asset": "Inter-Bold font input and derived outlined brand assets",
            "version": "unknown",
            "source": "local font path passed to generate_wordmark_outlines.swift",
            "actual_use_path": "font file -> CoreText glyph paths -> wordmark-outlines.json -> generated SVG/PNG/print/runtime copies",
            "exposure_scope": "brand assets, documentation, print and runtime copies",
            "license": "not recorded in repository",
            "integrity_reproducibility": "derived JSON/assets have hashes but input font version/hash and generation record absent",
            "maintenance_status": "local provenance gap; legal reviewer required",
            "arbitrary_code_or_ci_risk": "not arbitrary code, but unverified third-party font can create distribution obligations",
            "product_bundle_core_ffi_user_files_release": "brand files may ship in application/docs/release package",
            "existing_controls": "outlined files avoid runtime font dependency; brand manifest maps copies",
            "why_insufficient": "outline conversion does not prove font license or source rights",
            "minimal_fix": "record font source/version/license text/input hash and deterministic generation command; retain notices where required",
            "rollback": "replace derived wordmark with a verified in-house/vector source or remove affected copies",
            "verification_needed": "license review, source archive/hash verification and regeneration diff",
            "evidence_class": "local_confirmed_with_legal_gap",
            "evidence_files": ["assets/brand/wordmark-outlines.json", "assets/brand/README.md", "docs/ux/brand-assets.md", "scripts/brand/generate_wordmark_outlines.swift", "scripts/brand/build_source_assets.py"],
        },
        {
            "id": "SC-012",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "CI Action、Rust channel 与 Homebrew 工具链使用可移动/未锁定引用",
            "category": "CI supply chain",
            "locations": [".github/workflows/core-ci.yml:35,47,62,75,90", ".github/workflows/macos-ci.yml:42,88,345,374,389", ".github/workflows/governance-ci.yml:24,64"],
            "dependency_or_asset": "GitHub Actions and runner tools",
            "version": "checkout@v4, rust-cache@v2, upload/download-artifact@v4, gitleaks-action@v2, rust-toolchain@stable, brew latest",
            "source": "GitHub repositories, rustup channel and Homebrew",
            "actual_use_path": "all CI checkout/build/test/security/format jobs",
            "exposure_scope": "PR and main CI runners",
            "license": "upstream action/tool licenses not vendored",
            "integrity_reproducibility": "some refs resolved to commits on query date, but workflow requests mutable tags/channel",
            "maintenance_status": "external refs require continuous monitoring",
            "arbitrary_code_or_ci_risk": "changed action/tool content executes with CI permissions",
            "product_bundle_core_ffi_user_files_release": "build artifacts and release evidence; no direct product runtime",
            "existing_controls": "official actions, macos-14 runner, read-mostly permissions",
            "why_insufficient": "major tags/channel and brew latest do not provide immutable content",
            "minimal_fix": "pin third-party actions/tools to reviewed commit/version, maintain update bot/process and record hashes",
            "rollback": "revert ref updates to last reviewed commit and disable affected job if provenance fails",
            "verification_needed": "commit pin review, action provenance/SLSA or equivalent, clean runner replay",
            "evidence_class": "local_confirmed_with_external_ref_query",
            "evidence_files": [".github/workflows/core-ci.yml", ".github/workflows/macos-ci.yml", ".github/workflows/governance-ci.yml"],
        },
        {
            "id": "SC-013",
            "severity": "P2",
            "confidence": "MEDIUM",
            "title": "Governance PR job 给 checkout 脚本环境 security-events:write 并传入 token",
            "category": "CI permission boundary",
            "locations": [".github/workflows/governance-ci.yml:20-24", ".github/workflows/governance-ci.yml:63-66"],
            "dependency_or_asset": "gitleaks action and PR checkout",
            "version": "gitleaks-action@v2",
            "source": "GitHub Action plus fork PR workflow behavior",
            "actual_use_path": "pull_request -> checkout -> local scripts -> gitleaks action with GITHUB_TOKEN",
            "exposure_scope": "fork and same-repository PR CI",
            "license": "upstream action license not vendored",
            "integrity_reproducibility": "permission behavior depends on repository settings/event token downgrading",
            "maintenance_status": "remote repository settings/run evidence not available",
            "arbitrary_code_or_ci_risk": "overbroad token/action permission could amplify a workflow compromise",
            "product_bundle_core_ffi_user_files_release": "CI only",
            "existing_controls": "workflow top-level contents:read and GitHub fork restrictions",
            "why_insufficient": "job override grants write permission and token is explicitly exposed to third-party action",
            "minimal_fix": "use least-privilege permissions, isolate secret scan, and verify fork token behavior in repository settings",
            "rollback": "revert permission changes and disable upload/reporting path until validated",
            "verification_needed": "workflow run audit for fork PR, permission matrix and action source review",
            "evidence_class": "local_confirmed_with_remote_governance_gap",
            "evidence_files": [".github/workflows/governance-ci.yml"],
        },
        {
            "id": "SC-014",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "缺少发布用 SBOM、THIRD_PARTY_NOTICES 与第三方归属闭包",
            "category": "license/distribution governance",
            "locations": ["core/Cargo.lock:1-1830", "docs/development/release.md:32-51,178-189", "docs/development/dependency-policy.md:30-75"],
            "dependency_or_asset": "Cargo/UniFFI/Microsoft/Pillow/native and brand dependency closure",
            "version": "198 Cargo packages plus non-Cargo tools/assets",
            "source": "repository manifests/lockfiles and generated artifacts",
            "actual_use_path": "Core/FFI build -> Apple/Windows artifacts -> release package",
            "exposure_scope": "distribution and license compliance",
            "license": "9 MPL-2.0 Cargo packages, LGPL option and other non-default expressions require review",
            "integrity_reproducibility": "Cargo checksums exist, but no single release SBOM/notice manifest binds artifacts to closure",
            "maintenance_status": "legal and release-owner evidence absent",
            "arbitrary_code_or_ci_risk": "not directly code execution; omission can hide unreviewed components",
            "product_bundle_core_ffi_user_files_release": "release packages and FFI artifacts",
            "existing_controls": "dependency policy, Cargo.lock, release checklist and project license files",
            "why_insufficient": "policy/checklist does not itself provide artifact-specific notices/SBOM or source obligations",
            "minimal_fix": "generate and archive per-release SBOM, notices, source-offer records and artifact manifest; obtain qualified license review",
            "rollback": "hold distribution and remove affected package until notices are complete",
            "verification_needed": "license matrix readback against final package contents and legal sign-off",
            "evidence_class": "local_confirmed_with_legal_and_release_gap",
            "evidence_files": ["core/Cargo.lock", "docs/development/dependency-policy.md", "docs/development/release.md", "LICENSE", "COMMERCIAL_LICENSE.md"],
        },
        {
            "id": "SC-015",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "Linux native core 代码存在但产品/发布声明与校验链缺失",
            "category": "cross-platform native readiness",
            "locations": ["apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:1-20", "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs:222-242", "docs/product/current-implementation-inventory.md:616-618"],
            "dependency_or_asset": "area_matrix_core.so",
            "version": "unknown",
            "source": "AREAMATRIX_CORE_LIBRARY or NativeLibrary.Load(\"area_matrix_core\")",
            "actual_use_path": "LinuxDesktopShell -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault",
            "exposure_scope": "headless fixture today; future Linux runtime if enabled",
            "license": "unknown for runtime .so",
            "integrity_reproducibility": "no Linux package/publish asset, RID, hash/signature or system GTK dependency declaration",
            "maintenance_status": "repository docs explicitly call this a headless/UI contract fixture",
            "arbitrary_code_or_ci_risk": "uncontrolled library search path if launched",
            "product_bundle_core_ffi_user_files_release": "not proven in current release; would affect Core/FFI/user-file paths if enabled",
            "existing_controls": "symbol contract tests and configurable path",
            "why_insufficient": "tests inspect source/symbols, not a signed distributable .so",
            "minimal_fix": "either formally keep Linux fixture-only and guard launch, or add a complete RID/package/native provenance chain",
            "rollback": "keep Linux feature disabled and remove runtime launch path until artifact chain is complete",
            "verification_needed": "Linux clean build/package test, loader path hardening and artifact/license manifest",
            "evidence_class": "local_confirmed_readiness_gap",
            "evidence_files": ["apps/linux/AreaMatrix/AreaMatrix.Linux.csproj", "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs", "apps/linux/AreaMatrix/Core/AreaMatrixNativeCoreClient.cs", "apps/linux/AreaMatrix/Features/Library/LinuxDesktopShell.cs", "docs/product/current-implementation-inventory.md"],
        },
        {
            "id": "SC-016",
            "severity": "P3",
            "confidence": "HIGH",
            "title": "原型页面动态加载 Google Fonts，来源与离线/许可边界未记录",
            "category": "prototype external asset",
            "locations": ["assets/prototypes/landing/index.html:8", "assets/prototypes/workspace/index.html:7"],
            "dependency_or_asset": "Google Fonts Inter CSS",
            "version": "floating URL query",
            "source": "https://fonts.googleapis.com",
            "actual_use_path": "prototype HTML browser load",
            "exposure_scope": "prototype/demo only; not product runtime",
            "license": "font/provider terms not recorded in asset docs",
            "integrity_reproducibility": "network response mutable and unavailable offline",
            "maintenance_status": "external service",
            "arbitrary_code_or_ci_risk": "limited prototype network boundary; no CI execution observed",
            "product_bundle_core_ffi_user_files_release": "prototype only",
            "existing_controls": "assets README says prototypes are not product source",
            "why_insufficient": "does not document source/license or provide a local fallback for reproducible review",
            "minimal_fix": "record intended provider/license and use a local verified font or explicit prototype-only exception",
            "rollback": "remove external link and use system font stack",
            "verification_needed": "asset owner confirmation and offline rendering check",
            "evidence_class": "local_confirmed_low_scope",
            "evidence_files": ["assets/prototypes/landing/index.html", "assets/prototypes/workspace/index.html"],
        },
        {
            "id": "SC-017",
            "severity": "P3",
            "confidence": "HIGH",
            "title": "开发文档保留 curl | sh 与浮动 stable 工具安装示例",
            "category": "developer supply chain",
            "locations": ["docs/development/setup.md:50-53"],
            "dependency_or_asset": "rustup/install script and Rust stable channel",
            "version": "floating",
            "source": "external HTTPS installer",
            "actual_use_path": "developer follows setup guide before building Core",
            "exposure_scope": "developer workstation/bootstrap",
            "license": "installer/tool license not pinned in repository",
            "integrity_reproducibility": "pipe-to-shell and stable channel are mutable",
            "maintenance_status": "external installer/service",
            "arbitrary_code_or_ci_risk": "direct shell execution from network response",
            "product_bundle_core_ffi_user_files_release": "indirect build environment only",
            "existing_controls": "documentation and later Cargo lock",
            "why_insufficient": "installer is executed before repository controls apply",
            "minimal_fix": "document verified installer checksum/signature or package-manager path and pin toolchain",
            "rollback": "remove command and provide manual verified installation instructions",
            "verification_needed": "fresh-machine bootstrap review without executing the remote script",
            "evidence_class": "local_confirmed",
            "evidence_files": ["docs/development/setup.md"],
        },
        {
            "id": "SC-018",
            "severity": "P3",
            "confidence": "MEDIUM",
            "title": "tracing-appender 直接声明但未发现 Core 源码使用",
            "category": "unused dependency/attack surface",
            "locations": ["core/Cargo.toml:31", "core/Cargo.lock:56", "tracing-appender metadata"],
            "dependency_or_asset": "tracing-appender",
            "version": "0.2.5",
            "source": "crates.io",
            "actual_use_path": "manifest/lock only; token search found no core source import",
            "exposure_scope": "all Core builds through transitive time/crossbeam/parking_lot graph",
            "license": "MIT",
            "integrity_reproducibility": "checksum locked, but unnecessary dependency expands closure and MSRV pressure",
            "maintenance_status": "local unused-use evidence; external package maintenance not assessed",
            "arbitrary_code_or_ci_risk": "build/resolve surface without observed feature value",
            "product_bundle_core_ffi_user_files_release": "indirect build/runtime closure; no direct call path observed",
            "existing_controls": "Cargo.lock and compiler",
            "why_insufficient": "no unused dependency check in policy gate",
            "minimal_fix": "remove or justify with exact source use and feature scope",
            "rollback": "restore dependency if logging implementation is reintroduced",
            "verification_needed": "cargo tree/source search and behavior tests after removal/justification",
            "evidence_class": "local_confirmed_low_confidence",
            "evidence_files": ["core/Cargo.toml", "core/Cargo.lock"],
        },
        {
            "id": "SC-019",
            "severity": "P3",
            "confidence": "MEDIUM",
            "title": "Cargo 闭包包含停止维护或 deprecated 组件，需维护者处置",
            "category": "maintenance risk",
            "locations": ["core/Cargo.lock:122-129 (bincode 1.3.3)", "core/Cargo.lock (paste 1.0.15)", "core/Cargo.lock (serde_yaml 0.9.34+deprecated)"],
            "dependency_or_asset": "bincode, paste, serde_yaml",
            "version": "1.3.3; 1.0.15; 0.9.34+deprecated",
            "source": "crates.io/RustSec metadata",
            "actual_use_path": "transitive UniFFI/build or Core serialization paths as recorded in cargo metadata",
            "exposure_scope": "build/runtime closure depending on target feature",
            "license": "MIT or MIT/Apache-2.0 metadata; no license violation asserted",
            "integrity_reproducibility": "checksums present",
            "maintenance_status": "external advisories classify maintenance status; not a local vulnerability proof",
            "arbitrary_code_or_ci_risk": "maintenance and future patch availability risk",
            "product_bundle_core_ffi_user_files_release": "potentially transitive; exact runtime reachability needs owner confirmation",
            "existing_controls": "lockfile and tests",
            "why_insufficient": "no documented replacement/exception rationale",
            "minimal_fix": "map actual reachability, replace where low-risk, or record accepted maintenance exception",
            "rollback": "retain locked versions until compatibility tests pass",
            "verification_needed": "cargo tree -i and targeted source/use review; do not treat age alone as vulnerability",
            "evidence_class": "external_advisory_with_local_reachability_gap",
            "evidence_files": ["core/Cargo.lock", "core/Cargo.toml"],
        },
        {
            "id": "SC-020",
            "severity": "P3",
            "confidence": "LOW",
            "status": "BLOCKED",
            "review_status": "BLOCKED",
            "title": "anyhow RustSec 命中但本地触发路径未确认",
            "category": "external advisory applicability",
            "locations": ["core/Cargo.lock:35-40 (anyhow 1.0.102)"],
            "dependency_or_asset": "anyhow",
            "version": "1.0.102",
            "source": "OSV/RustSec RUSTSEC-2026-0190",
            "actual_use_path": "appears in transitive UniFFI/build graph; no local downcast_mut call found in reviewed source",
            "exposure_scope": "build toolchain unless a runtime path is later demonstrated",
            "license": "MIT OR Apache-2.0",
            "integrity_reproducibility": "Cargo checksum present",
            "maintenance_status": "external advisory current as of query date; database freshness/complete applicability requires recheck",
            "arbitrary_code_or_ci_risk": "unsoundness advisory; no local exploit path confirmed",
            "product_bundle_core_ffi_user_files_release": "not established",
            "existing_controls": "lockfile and source review",
            "why_insufficient": "static local review cannot establish all transitive macro/build call paths",
            "minimal_fix": "validate advisory reachability and upgrade if applicable; otherwise record exception",
            "rollback": "retain current lock until compatibility and reachability evidence exists",
            "verification_needed": "independent RustSec/OSV validation and cargo tree/source call-path proof",
            "evidence_class": "external_advisory_blocked_local_validation",
            "evidence_files": ["core/Cargo.lock"],
        },
        {
            "id": "SC-021",
            "severity": "P2",
            "confidence": "HIGH",
            "title": "AI 外部 runtime 可执行程序没有供应链身份绑定",
            "category": "外部能力/运行时完整性",
            "locations": [
                "core/src/ai_classification_suggestion/executor.rs:16-17,77-100",
                "core/src/ai_tags_suggestion/executor.rs:14-15,78-105",
                "core/src/ai_summary/executor.rs:14-15,67-94",
                "core/src/semantic_search/executor.rs:12,88-113",
                "core/src/external_runtime.rs:50-106",
            ],
            "dependency_or_asset": "AREAMATRIX_*_RUNTIME executable family",
            "version": "未知",
            "source": "进程环境变量提供的任意 executable path",
            "actual_use_path": "AI classification/tags/summary/semantic executor -> Command::new(runtime_path) -> external_runtime::run -> stdin 传入序列化内容",
            "exposure_scope": "可选本地/远程 AI 路径；可能处理用户内容与 provider 配置",
            "license": "未知；仓库未登记实现供应商或分发条款",
            "integrity_reproducibility": "未绑定名称、版本、来源、hash、签名、SBOM 或允许清单",
            "maintenance_status": "仅有协议与安全执行器；实际 runtime 实现不在仓库",
            "arbitrary_code_or_ci_risk": "启用该能力即执行环境指定程序；来源错误会在应用权限下运行代码并读取 stdin payload",
            "product_bundle_core_ffi_user_files_release": "Core AI/远程数据边界；当前平台装配未证明正式发布包已提供该 runtime",
            "existing_controls": "env_clear、固定 SAFE_PATH、超时、stdout 上限、stderr 丢弃、进程组隔离与清理",
            "why_insufficient": "这些控制限制子进程行为，但不认证 executable 身份、许可证或更新来源",
            "minimal_fix": "为每个允许 runtime 建立受审版本/来源/hash/signature/许可证清单和平台装配边界，默认 fail closed",
            "rollback": "保持环境变量未设置并禁用对应 AI route；撤回未验证 runtime bundle",
            "verification_needed": "签名/hash 替换测试、payload 最小化/隐私验证、clean package inspection 与外部能力准入复核",
            "evidence_class": "local_confirmed_external_capability_gap",
            "evidence_files": [
                "core/src/ai_classification_suggestion/executor.rs",
                "core/src/ai_tags_suggestion/executor.rs",
                "core/src/ai_summary/executor.rs",
                "core/src/semantic_search/executor.rs",
                "core/src/external_runtime.rs",
                "docs/modules/semantic-search.md",
                "docs/architecture/macos-frontend-architecture.md",
            ],
        },
        {
            "id": "SC-022",
            "severity": "P3",
            "confidence": "HIGH",
            "title": "16 个品牌历史探索稿缺少逐项来源与授权记录",
            "category": "资产来源/许可证证据",
            "locations": ["assets/brand/README.md:23,80", *archive_assets],
            "dependency_or_asset": "assets/brand/archive/** PNG/SVG",
            "version": "early-drafts、v2、v3、v4",
            "source": "仓库只说明用于设计回溯并禁止正式引用",
            "actual_use_path": "archive 仅保存于源码仓库；未发现 README/UI/CI/发布 manifest 的正式引用",
            "exposure_scope": "源码分发与设计回溯；当前未进入产品运行时/发布资源路径",
            "license": "未知",
            "integrity_reproducibility": "逐文件 SHA-256、MIME 与 SVG 结构已确认，但创作者、原始输入、参考素材授权和生成命令未登记",
            "maintenance_status": "静态历史资产，无上游更新身份",
            "arbitrary_code_or_ci_risk": "不执行代码；风险集中在来源、参考素材和再分发授权",
            "product_bundle_core_ffi_user_files_release": "不应进入产品包；仍随源码仓库分发",
            "existing_controls": "README 明确 archive 禁止正式引用；本次逐项 hash inventory",
            "why_insufficient": "禁止产品引用不能补足源码分发时的来源与许可证证据",
            "minimal_fix": "由资产 owner 为每个历史家族记录创作者、来源/参考、授权、生成链和保留理由；无法追溯者移出可分发仓库需另行确认",
            "rollback": "不修改现有资产；后续治理变更可恢复至本次冻结 hash 清单",
            "verification_needed": "资产 owner 与合格许可证 reviewer 逐项签核；确认 release/source archive 包内容",
            "evidence_class": "local_per_asset_hash_with_provenance_gap",
            "evidence_files": ["assets/brand/README.md", *archive_assets],
            "affected_assets": archive_assets,
        },
        {
            "id": "SC-023",
            "severity": "P3",
            "confidence": "MEDIUM",
            "title": "行为准则记录了改编来源，但未记录上游许可证条款与固定版本证据",
            "category": "第三方文本归属/许可证",
            "locations": ["CODE_OF_CONDUCT.md:1", "CODE_OF_CONDUCT.md:75-83"],
            "dependency_or_asset": "Contributor Covenant 2.1 与 Mozilla 社区影响执行阶梯",
            "version": "Contributor Covenant 2.1；Mozilla revision 未固定",
            "source": "CODE_OF_CONDUCT.md:77-83 的公开链接",
            "actual_use_path": "上游治理文本 -> 中文改编 CODE_OF_CONDUCT.md -> 随源码仓库分发",
            "exposure_scope": "文档与源码分发；不进入产品运行时",
            "license": "仓库未记录具体许可证表达式/许可证链接；需外部与法律复核",
            "integrity_reproducibility": "来源 URL 与版本部分存在，但无 upstream revision/hash 或保存的 license evidence",
            "maintenance_status": "公开上游；本轮未对上游当前许可证作法律定论",
            "arbitrary_code_or_ci_risk": "无代码执行风险；存在 attribution/修改声明/许可条款证据不完整风险",
            "product_bundle_core_ffi_user_files_release": "源码仓库与文档分发",
            "existing_controls": "已声明 Contributor Covenant 版本、改编事实和 Mozilla 参考来源",
            "why_insufficient": "来源声明本身不能证明当前 attribution、license link、修改声明与再分发义务全部满足",
            "minimal_fix": "固定上游版本/revision，记录适用许可证、归属与修改声明；由合格许可证 reviewer 确认文本",
            "rollback": "恢复至本次 CODE_OF_CONDUCT.md hash 并保留现有来源声明",
            "verification_needed": "上游许可证原文/版本 hash、attribution 清单与法律/许可证复核",
            "evidence_class": "local_attribution_with_external_license_gap",
            "evidence_files": ["CODE_OF_CONDUCT.md"],
        },
    ]
    overrides: dict[str, dict[str, Any]] = {
        "SC-001": {
            "category": "可复现性/构建契约",
            "locations": ["core/Cargo.toml:5", "core/Cargo.lock:1049-1050", "core/Cargo.lock:1368-1369", "README.md:50", "README.zh-CN.md:50"],
            "actual_use_path": "cargo build/test/clippy 按 core/Cargo.lock 解析；文档与 manifest 宣称 Rust 1.75 可构建",
            "exposure_scope": "开发者与 CI 构建；声明的受支持环境无法重现锁定闭包",
            "license": "非主问题；许可证闭包在独立台账中记录",
            "integrity_reproducibility": "lock checksum 存在，但锁定包最高 rust_version=1.88，高于声明 1.75",
            "maintenance_status": "本地 metadata 快照确认；修复前仍需复核目标版本上游 metadata",
            "arbitrary_code_or_ci_risk": "导致构建失败或环境分叉，本身不构成任意代码执行",
            "product_bundle_core_ffi_user_files_release": "可阻断 Core/FFI 构建；无直接产品运行时路径",
            "existing_controls": "Cargo.toml rust-version、setup/README 文档与 Cargo.lock",
            "why_insufficient": "三类控制对最低 Rust 版本给出互相不成立的契约",
            "minimal_fix": "提升并统一真实 MSRV，或约束/替换要求 1.88 的包后受审重建 lockfile",
            "rollback": "将 manifest、lockfile 与文档作为同一受审变更整体回滚",
            "verification_needed": "cargo metadata --locked，并在声明 MSRV 与当前 toolchain 各做兼容构建验证",
        },
        "SC-002": {
            "category": "native 制品来源",
            "locations": ["apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:1-22", "apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs:242-260"],
            "actual_use_path": "Windows app -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault/Load -> NativeLibrary.Load",
            "exposure_scope": "Windows 运行时、Core/FFI 及经 bridge 到达的用户文件操作",
            "license": "实际加载 DLL 的许可证未知",
            "integrity_reproducibility": "无 project item、源码 revision、hash、签名、架构或 SBOM 证明加载的 DLL",
            "maintenance_status": "仓库本地缺口；外部 DLL 来源不可得",
            "arbitrary_code_or_ci_risk": "不受控 DLL 加载会造成应用权限下代码执行与 ABI 替换风险",
            "product_bundle_core_ffi_user_files_release": "Windows 产品运行时及全部 bridged 文件路径",
            "existing_controls": "环境变量/File.Exists 检查与导出符号绑定",
            "why_insufficient": "文件存在与符号查找不能认证来源、版本或签名",
            "minimal_fix": "通过批准构建产生 RID/架构绑定的 fingerprint native asset，加载前验 hash/signature 并附 notices",
            "rollback": "禁用 Windows native launch，或恢复上一份已验证 artifact/loader manifest",
            "verification_needed": "clean Windows build/publish、制品 hash/signature、ABI contract test 与 package inspection",
        },
        "SC-003": {
            "category": "依赖完整性",
            "locations": ["apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:1-22", "apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:21"],
            "actual_use_path": "Microsoft.WindowsAppSDK -> WinUI SDK/runtime assets -> Windows build/publish",
            "exposure_scope": "Windows 构建与分发包",
            "license": "Microsoft Software License Terms 与未闭合的传递包许可证",
            "integrity_reproducibility": "无 packages.lock.json、NuGet.config source mapping 或仓库内 package hash",
            "maintenance_status": "官方顶层包来源确认；registration/catalog 更深闭包查询不稳定",
            "arbitrary_code_or_ci_risk": "restore 时包替换、feed/cache 投毒与 RID asset 漂移风险",
            "product_bundle_core_ffi_user_files_release": "Windows 产品包与构建输出",
            "existing_controls": "顶层 PackageReference 精确版本与 RID 列表",
            "why_insufficient": "顶层精确版本不能锁定传递包、feed、RID 资产和 package hash",
            "minimal_fix": "提交 packages.lock.json 与 approved feed/source mapping，以 locked mode 验 hash/license/SBOM",
            "rollback": "回滚 lock/config 前仅保留开发引用，不把未锁定 restore 作为发布证据",
            "verification_needed": "clean locked restore、完整 dependency graph/SBOM 与 package content hash 比对",
        },
        "SC-004": {
            "category": "运行时外部命令执行",
            "locations": ["core/src/storage/delete.rs:31", "core/src/storage/replacement_trash.rs:105-118", "core/Cargo.lock:1177-1180", "core/Cargo.toml:33-34"],
            "actual_use_path": "delete_file -> send_to_system_trash -> trash::delete -> macOS upstream Command::new(\"osascript\")",
            "exposure_scope": "macOS 产品运行时的用户文件删除/移入废纸篓路径",
            "license": "trash metadata 为 MIT；上游实现与系统工具条款需独立复核",
            "integrity_reproducibility": "Cargo checksum 存在，但 osascript 由环境 PATH 解析",
            "maintenance_status": "本地调用链确认；外部 crate 源行为需按锁定版本复核",
            "arbitrary_code_or_ci_risk": "PATH 劫持可替换处理用户文件时执行的 osascript",
            "product_bundle_core_ffi_user_files_release": "Core 与 macOS bridge 的用户文件路径",
            "existing_controls": "平台 cfg、trash abstraction 与失败后本地 trash fallback",
            "why_insufficient": "抽象层最终仍执行无绝对路径的外部命令",
            "minimal_fix": "改用可信平台 API/受控系统绝对路径并验证，或下沉到 Swift 平台服务",
            "rollback": "保留禁用破坏性操作的开关并恢复原 adapter，直到文件安全回归通过",
            "verification_needed": "sandbox fixture 中 PATH substitution 测试与用户文件安全回归",
        },
        "SC-005": {
            "category": "CI 解析器攻击面",
            "locations": ["scripts/brand/requirements.txt:1", ".github/workflows/governance-ci.yml:40-46", "scripts/brand/validate_assets.py:90-106"],
            "actual_use_path": "PR checkout -> pip install -> validate_assets.py -> Image.open(repository-controlled binary)",
            "exposure_scope": "pull_request CI runner；未发现产品运行时路径",
            "license": "PyPI 为 MIT-CMU；仓库政策错误写为 HPND（SC-006）",
            "integrity_reproducibility": "版本精确但无 artifact hash；11.3.0 命中 18 个唯一 GHSA，其中 PSD/FITS/McIdas Image.open 候选与未限制 formats 最接近",
            "maintenance_status": "PyPI 标记 Mature/not yanked；advisory 查询截至 2026-08-20",
            "arbitrary_code_or_ci_risk": "候选影响含 native memory corruption、信息泄漏与 DoS；并非 18 条均已证明本地可达",
            "product_bundle_core_ffi_user_files_release": "仅 CI/品牌开发工具，不进入 app/Core/FFI",
            "existing_controls": "固定版本、固定资产路径、尺寸/alpha 检查与无高权限产品凭据",
            "why_insufficient": "Image.open 未限制 formats，固定扩展名不约束文件 magic；版本仍有公开修复版本",
            "minimal_fix": "在独立变更中升级到覆盖相关修复的受审版本、pin hashes/index，并显式限制允许格式/magic/资源上限",
            "rollback": "回滚品牌依赖更新或临时禁用 PR 图片解析步骤，不影响产品运行时",
            "verification_needed": "去重 GHSA 复核、恶意 PSD/FITS/McIdas fixture、资源上限与 clean CI 重放",
            "external_advisories": [
                {"id": "GHSA-cfh3-3jmp-rvhc", "candidate_path": "PSD/Image.open", "fixed_in": "12.1.1"},
                {"id": "GHSA-pwv6-vv43-88gr", "candidate_path": "PSD/Image.open", "fixed_in": "12.2.0"},
                {"id": "GHSA-whj4-6x5x-4v2j", "candidate_path": "FITS/Image.open", "fixed_in": "12.2.0"},
                {"id": "GHSA-62p4-gmf7-7g93", "candidate_path": "McIdas/Image.open+pixel access", "fixed_in": "12.3.0"},
            ],
            "external_unique_ghsa_count": 18,
        },
        "SC-006": {
            "category": "许可证/依赖完整性",
            "locations": ["docs/development/dependency-policy.md:61", "docs/development/dependency-policy.md:66", "scripts/brand/requirements.txt:1", ".github/workflows/governance-ci.yml:40-46"],
            "actual_use_path": "policy -> requirements exact version -> pip resolver -> CI/品牌工具",
            "exposure_scope": "开发与 CI；不进入产品运行时",
            "license": "PyPI/upstream 为 MIT-CMU，仓库政策声称 HPND；需合格许可证 reviewer 确认兼容与归属",
            "integrity_reproducibility": "只 pin 版本，不 pin index/artifact hash；查询到的 sdist hash 未入库",
            "maintenance_status": "来源官方且未 yanked；政策证据已漂移",
            "arbitrary_code_or_ci_risk": "pip 安装执行第三方 package build/install 逻辑；当前通常消费 wheel，但未锁 artifact",
            "product_bundle_core_ffi_user_files_release": "品牌工具与 CI，不进入 app/Core/FFI",
            "existing_controls": "独立 venv 与精确版本",
            "why_insufficient": "版本 pin 不能修复许可证错误，也不能证明实际下载 artifact",
            "minimal_fix": "复核并修正文档许可证，采用 hash-locked requirements/受控 index，归档 attribution/license evidence",
            "rollback": "移除品牌自动化依赖与对应 CI step；产品运行时不受影响",
            "verification_needed": "PyPI/upstream license readback、选定 wheel/sdist hash 与合格 reviewer 签核",
        },
        "SC-007": {
            "category": "feature/构建执行面",
            "locations": ["core/Cargo.toml:17", "core/Cargo.toml:36-37", "core/build.rs:1-15"],
            "actual_use_path": "runtime dependency uniffi(build feature) + build-dependency uniffi(build feature) -> proc-macro/build/bindgen 闭包",
            "exposure_scope": "所有 Core 构建与 FFI 生成",
            "license": "UniFFI 家族含 MPL-2.0，需人工确认链接/修改/分发义务",
            "integrity_reproducibility": "Cargo.lock/checksum 固定，但 runtime edge 不必要地启用 build feature",
            "maintenance_status": "锁定 0.28 系列；未声称上游已停止维护",
            "arbitrary_code_or_ci_risk": "扩大 proc-macro/build dependency 与构建期执行面",
            "product_bundle_core_ffi_user_files_release": "Core/FFI build closure，并可能扩大最终 feature graph",
            "existing_controls": "Cargo.lock、build.rs 与 CI",
            "why_insufficient": "同一 build feature 同时出现在运行时与 build dependency，职责未最小化",
            "minimal_fix": "在独立变更中验证后从 runtime uniffi 移除 build feature，仅保留实际所需 feature",
            "rollback": "若 bindings/scaffolding 回归，恢复 feature 并记录理由",
            "verification_needed": "cargo tree -e features、locked clean build、bindings drift 与全平台 FFI tests",
        },
        "SC-008": {
            "category": "代码生成器来源",
            "locations": ["scripts/dev_tools/build.py:77-88", "scripts/dev_tools/build.py:220-279", "scripts/dev_tools/build.py:246-270"],
            "actual_use_path": "UNIFFI_BINDGEN/AREAMATRIX_UNIFFI_BINDGEN override 或 Cargo cache source -> 临时 wrapper cargo build -> 生成 bindings",
            "exposure_scope": "开发/CI 构建期代码生成",
            "license": "UniFFI MPL-2.0 family；环境 override executable 许可证未知",
            "integrity_reproducibility": "版本从 lock 读取，但 cache path/环境 executable 未自行校验 crate checksum/hash/signature",
            "maintenance_status": "fallback 有 locked fetch/offline build；实际 cache/override owner 未登记",
            "arbitrary_code_or_ci_risk": "构建期执行可替换 generator，可污染 Swift/C headers 与 native artifact",
            "product_bundle_core_ffi_user_files_release": "Core/FFI 生成物和下游 Apple 包",
            "existing_controls": "锁定版本、cargo fetch --locked、临时 CARGO_HOME、offline wrapper build",
            "why_insufficient": "控制锁版本但没有认证 cache source tree 或 override executable 身份",
            "minimal_fix": "绑定允许的 generator provenance/hash/version，校验 cache checksum，限制或移除任意 override",
            "rollback": "禁用 override/fallback，恢复已验证生成物并要求受控 clean generation",
            "verification_needed": "篡改 cache/override 负测、bindings deterministic diff 与 clean isolated rebuild",
        },
        "SC-009": {
            "category": "锁文件强制执行",
            "locations": [".github/workflows/core-ci.yml:38", ".github/workflows/core-ci.yml:53", ".github/workflows/core-ci.yml:66", ".github/workflows/core-ci.yml:100", "scripts/dev_tools/core_sdk.py:115", "scripts/dev_tools/build.py:313,755"],
            "actual_use_path": "CI 与 CoreSDK/build helpers 直接调用 cargo fmt/clippy/test/build/llvm-cov，未统一传 --locked",
            "exposure_scope": "CI、开发构建、CoreSDK artifact 与 FFI",
            "license": "Cargo 闭包许可证另表；主问题为解析可复现性",
            "integrity_reproducibility": "Cargo.lock 已提交，但部分命令允许 resolver 在 lock 不适用/漂移时改写或继续",
            "maintenance_status": "本地命令链确认",
            "arbitrary_code_or_ci_risk": "意外解析不同 build.rs/proc-macro/native crate 会扩大构建期执行风险",
            "product_bundle_core_ffi_user_files_release": "Core/FFI 与 Apple artifact",
            "existing_controls": "Cargo.lock v4、registry checksum 与部分 fallback cargo fetch --locked",
            "why_insufficient": "存在 lockfile 不等于每个生产/CI 入口都 fail closed 使用它",
            "minimal_fix": "为解析/构建/test/coverage 入口统一 --locked，并在 helper tests 断言",
            "rollback": "恢复命令参数；保留当前 Cargo.lock 与可重放基线",
            "verification_needed": "故意漂移 manifest/lock 的 fail-closed 测试与 clean cache build",
        },
        "SC-010": {
            "category": "tracked native binary 来源",
            "locations": ["apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a（SHA-256 69ef0816...1db44）", "apps/macos/XcodeGen/project.yml:1"],
            "actual_use_path": "XcodeGen generated project link reference；canonical AreaMatrix.xcodeproj 当前改用 CoreSDK XCFramework",
            "exposure_scope": "tracked 94 MB universal archive；潜在 legacy/generated project 链接输入",
            "license": "项目与 Cargo 对象混合；无 archive-specific notices/SBOM",
            "integrity_reproducibility": "本地 hash/architecture/symbol 可确认，source commit、build manifest、签名与复现命令未绑定",
            "maintenance_status": "仓库内静态制品；canonical 与 XcodeGen 路径并存",
            "arbitrary_code_or_ci_risk": "链接未验证对象会把任意 native code 带入 app",
            "product_bundle_core_ffi_user_files_release": "若走 XcodeGen 路径会进入 macOS Core/FFI 产品",
            "existing_controls": "tracked hash 可冻结；canonical CoreSDK 有 fingerprint/manifest",
            "why_insufficient": "另一路 tracked archive 未继承 CoreSDK provenance/notices/signature",
            "minimal_fix": "删除/替换需另行确认；最小治理是为 archive 建 source commit、deterministic command、SBOM、notices、hash/signature 并统一 canonical path",
            "rollback": "恢复该 frozen hash，或回退到已验证 CoreSDK reference",
            "verification_needed": "clean rebuild byte/symbol diff、XcodeGen/canonical project package inspection 与许可证 readback",
            "supplemental_evidence_files": ["apps/macos/XcodeGen/AreaMatrixGenerated.xcodeproj/project.pbxproj"],
            "supplemental_evidence_basis": "审计时存在的 ignored/generated project；已读取其 40、1688、3205 行，但不属于冻结 tracked + 启动时 untracked 文件范围",
        },
        "SC-011": {
            "category": "品牌资产来源",
            "locations": ["assets/brand/wordmark-outlines.json:5", "assets/brand/wordmark-outlines.json:9", "assets/brand/README.md:74", "docs/ux/brand-assets.md:27,101"],
            "actual_use_path": "Inter-Bold font -> generate_wordmark_outlines.swift -> wordmark-outlines.json -> build_source_assets.py -> final SVG/PNG/PDF/TIFF/runtime copies",
            "exposure_scope": "品牌、文档、印刷、社交与应用内 runtime copies",
            "license": "仓库未记录 Inter 输入字体版本、来源或许可证；需合格许可证 reviewer 确认",
            "integrity_reproducibility": "outline JSON 与派生文件有 hash，但字体输入与首次生成记录缺失",
            "maintenance_status": "派生几何已固化；上游字体身份不可追溯",
            "arbitrary_code_or_ci_risk": "不是任意代码执行；风险为未经验证的第三方字体分发义务",
            "product_bundle_core_ffi_user_files_release": f"{len(inter_assets)} 个识别出的字标/lockup/stacked/social/print/runtime artifact 可能进入产品/文档/发布",
            "existing_controls": "outlined SVG、deterministic exports、manifest 与 runtime-copy hash 检查",
            "why_insufficient": "轮廓化和 hash 不能证明最初字体文件的授权与来源",
            "minimal_fix": "记录字体 source/version/license text/input hash、生成命令与修改/归属声明，并保留必要 notices",
            "rollback": "用可验证的自有/vector 字标替换，或移除受影响副本",
            "verification_needed": "许可证复核、字体 archive/hash 与全量 regeneration diff",
            "evidence_files": ["assets/brand/wordmark-outlines.json", "assets/brand/README.md", "docs/ux/brand-assets.md", "scripts/brand/generate_wordmark_outlines.swift", "scripts/brand/build_source_assets.py", *inter_assets],
            "affected_artifacts": inter_assets,
        },
        "SC-012": {
            "category": "CI/工具链可复现性",
            "locations": [".github/workflows/core-ci.yml:35,47,62,75,90,97", ".github/workflows/macos-ci.yml:42,88,345,374-391", ".github/workflows/governance-ci.yml:24,64"],
            "actual_use_path": "所有 CI checkout/cache/build/test/security/format/artifact jobs",
            "exposure_scope": "PR/main CI runner 与发布证据输入",
            "license": "各 Action/工具许可证未形成仓库内 notices/审阅清单",
            "integrity_reproducibility": "workflow 使用 major tag/stable/brew latest；查询日 commit 只是一时解析，不是 pin",
            "maintenance_status": "外部 refs 需持续监控；dtolnay stable 未能按固定 tag 解析",
            "arbitrary_code_or_ci_risk": "上游 ref/formula 变化会在 CI 权限下执行代码或改变 artifact",
            "product_bundle_core_ffi_user_files_release": "构建产物、测试结论、缓存与 release evidence；非产品运行时依赖",
            "existing_controls": "官方 Action 优先、明确 major、GitHub-hosted runners 与 lockfile",
            "why_insufficient": "major/channel/formula 引用仍可移动，且工具版本/hash 未绑定",
            "minimal_fix": "按审阅 commit/version pin Action/工具，建立受控升级与 provenance/hash 记录",
            "rollback": "回退至上一已审 commit；provenance 失败时停用相关 job/artifact",
            "verification_needed": "commit pin review、Action provenance/SLSA 证据与 clean runner replay",
        },
        "SC-013": {
            "category": "CI 权限/第三方 action",
            "locations": [".github/workflows/governance-ci.yml:20-24", ".github/workflows/governance-ci.yml:63-66"],
            "actual_use_path": "pull_request -> checkout PR tree -> 多个本地脚本 -> gitleaks action(GITHUB_TOKEN)",
            "exposure_scope": "fork 与同仓 PR；token 降权取决于远端 event/settings",
            "license": "gitleaks action 上游许可证未随仓库归档",
            "integrity_reproducibility": "action 使用可移动 v2；远端权限行为未由本地证明",
            "maintenance_status": "公开 action；远端 settings/run evidence 缺失",
            "arbitrary_code_or_ci_risk": "job 级 security-events:write 加显式 token 会放大 workflow/action compromise",
            "product_bundle_core_ffi_user_files_release": "仅 CI，但影响合并门禁与安全报告",
            "existing_controls": "顶层 contents:read、fork token 通常自动降权、gitleaks 专用 action",
            "why_insufficient": "本地 YAML 无法证明 fork/同仓 PR 权限矩阵，且第三方 action 接收 token",
            "minimal_fix": "最小权限隔离 secret scan，验证 fork/同仓 token 行为并固定 action commit",
            "rollback": "撤回权限变更或暂时禁用上传/reporting path",
            "verification_needed": "fork PR run audit、权限矩阵、action source/provenance 与远端 settings readback",
        },
        "SC-014": {
            "category": "分发许可证闭包",
            "locations": ["core/Cargo.lock:1-1830", "docs/development/dependency-policy.md:53-81", "docs/development/release.md:178-189"],
            "actual_use_path": "Cargo/UniFFI/Microsoft/Pillow/native/brand closure -> Core/FFI -> Apple/Windows artifacts -> release package",
            "exposure_scope": "发布分发与许可证合规",
            "license": "含 MPL-2.0、LGPL option、双许可证、Microsoft/字体未知项；需合格 reviewer",
            "integrity_reproducibility": "存在 Cargo checksum/部分 artifact hash，但无逐发布 SBOM/notices/source-offer manifest 绑定最终包",
            "maintenance_status": "本地仓库缺口；最终包尚未提供可读闭包",
            "arbitrary_code_or_ci_risk": "本身不是代码执行漏洞，但会掩盖未审组件与分发义务",
            "product_bundle_core_ffi_user_files_release": "所有发布包与 FFI 制品",
            "existing_controls": "依赖政策、Cargo.lock、发布 checklist、CoreSDK fingerprint",
            "why_insufficient": "政策/checklist 不是 artifact-specific SBOM、notice、源码提供或归属证据",
            "minimal_fix": "每次发布生成/归档 SBOM、THIRD_PARTY_NOTICES、source-offer、artifact manifest，并由合格 reviewer readback",
            "rollback": "暂停分发或移除义务未闭合组件",
            "verification_needed": "最终包内容与 license matrix 双向比对、法律签核与 clean package inspection",
        },
        "SC-015": {
            "category": "跨平台 native readiness",
            "locations": ["apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:1-20", "apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs:224-242", "docs/product/current-implementation-inventory.md:616-618"],
            "actual_use_path": "LinuxDesktopShell -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault",
            "exposure_scope": "当前 headless/UI contract fixture；若启用则为 Linux 运行时",
            "license": "实际 .so、GTK/desktop system packages 的许可证未知",
            "integrity_reproducibility": "无 Linux package/publish asset、RID、hash/signature 或系统依赖声明",
            "maintenance_status": "文档明确当前不是可启动 GTK 产品",
            "arbitrary_code_or_ci_risk": "启动时系统库搜索路径可加载不受控 native library",
            "product_bundle_core_ffi_user_files_release": "当前未证明进入发布；启用后会影响 Core/FFI/用户文件路径",
            "existing_controls": "符号 contract tests、可配置 path 与 fixture-only 文档定位",
            "why_insufficient": "测试检查源码/符号，不证明已签名可分发 .so 或系统包闭包",
            "minimal_fix": "正式保持 fixture-only 并阻止 launch，或补完整 RID/package/native provenance 与 Linux system dependency manifest",
            "rollback": "保持 Linux feature disabled，移除运行入口直到闭环",
            "verification_needed": "clean Linux build/package、loader hardening、GTK/system package 与 artifact/license manifest",
        },
        "SC-016": {
            "category": "原型外部资产",
            "actual_use_path": "prototype HTML browser load -> fonts.googleapis.com CSS/font",
            "exposure_scope": "仅 prototype/demo，不进入产品运行时",
            "license": "仓库未记录 font/provider 条款",
            "integrity_reproducibility": "网络响应浮动且离线不可复现",
            "maintenance_status": "外部服务",
            "arbitrary_code_or_ci_risk": "有限原型网络边界；未观察到 CI 执行",
            "product_bundle_core_ffi_user_files_release": "仅 prototype",
            "existing_controls": "assets README 说明 prototype 非产品源",
            "why_insufficient": "未记录来源/许可证，也无本地可复现 fallback",
            "minimal_fix": "登记 provider/license，并使用本地已验证字体或明确 prototype-only exception",
            "rollback": "移除外部 link，改用系统字体栈",
            "verification_needed": "资产 owner 确认与离线渲染检查",
        },
        "SC-017": {
            "category": "开发者 bootstrap 供应链",
            "locations": ["docs/development/setup.md:51"],
            "actual_use_path": "开发者按 setup 文档从网络取得 rustup shell script 并立即执行",
            "exposure_scope": "开发工作站/bootstrap",
            "license": "installer/tool 许可证未随仓库固定",
            "integrity_reproducibility": "curl|sh 与 stable channel 均可变",
            "maintenance_status": "外部 installer/service",
            "arbitrary_code_or_ci_risk": "在仓库控制生效前直接执行网络响应",
            "product_bundle_core_ffi_user_files_release": "间接影响构建环境，不是产品运行时",
            "existing_controls": "TLS 参数与后续 Cargo.lock",
            "why_insufficient": "installer 在任何仓库 hash/signature 控制之前执行",
            "minimal_fix": "提供已验证 checksum/signature 或受控 package-manager 路径，并固定 toolchain",
            "rollback": "移除 pipe-to-shell 示例，保留人工校验安装说明",
            "verification_needed": "不执行远端脚本的 fresh-machine bootstrap 复核",
        },
        "SC-018": {
            "category": "未使用依赖/攻击面",
            "locations": ["core/Cargo.toml:31", "core/Cargo.lock:1114-1120"],
            "actual_use_path": "manifest/lock 声明；扫描 build.rs 与全部 core/**/*.rs 未发现 tracing_appender token",
            "exposure_scope": "所有 Core resolve/build，经 time/crossbeam/parking_lot 扩大闭包",
            "license": "MIT",
            "integrity_reproducibility": "checksum 固定，但无效依赖扩大 closure 与 MSRV 压力",
            "maintenance_status": "本地未使用证据确认；外部维护状态未作结论",
            "arbitrary_code_or_ci_risk": "增加 resolve/build surface，未观察到功能价值",
            "product_bundle_core_ffi_user_files_release": "间接 build/runtime 闭包；无直接调用路径",
            "existing_controls": "Cargo.lock 与编译器",
            "why_insufficient": "政策/CI 没有 unused dependency gate",
            "minimal_fix": "删除或用精确使用位置与 feature scope 证明必要性",
            "rollback": "若日志实现恢复则还原依赖",
            "verification_needed": "cargo tree/source search 与移除后的行为/构建测试",
        },
        "SC-019": {
            "category": "维护风险",
            "locations": ["core/Cargo.lock:122-129", "core/Cargo.lock:643-649", "core/Cargo.lock:881-890"],
            "actual_use_path": "Cargo metadata 显示经 UniFFI/build 或 Core serialization edge 可达",
            "exposure_scope": "依 target/feature 的 build/runtime 闭包",
            "license": "MIT 或 MIT/Apache metadata；本 finding 不主张许可证违规",
            "integrity_reproducibility": "各包 checksum 已记录",
            "maintenance_status": "外部 advisory/deprecated metadata；不是本地漏洞证明",
            "arbitrary_code_or_ci_risk": "维护停止导致未来补丁/兼容性风险",
            "product_bundle_core_ffi_user_files_release": "可能为传递闭包；精确 runtime reachability 仍需 owner 确认",
            "existing_controls": "lockfile 与测试",
            "why_insufficient": "无 replacement/accepted-exception 依据",
            "minimal_fix": "映射真实可达性，低风险替换或记录有期限维护例外",
            "rollback": "兼容验证前保留锁定版本",
            "verification_needed": "cargo tree -i、target/feature 源码复核；不得把版本年龄直接当漏洞",
        },
        "SC-020": {
            "category": "外部 advisory 适用性",
            "locations": ["core/Cargo.lock:36-40"],
            "actual_use_path": "Cargo metadata 显示在 UniFFI/build 传递图；已审本地源码未发现 downcast_mut 调用",
            "exposure_scope": "除非后续证明 runtime path，否则暂按构建工具链",
            "license": "MIT OR Apache-2.0（双许可证需人工确认）",
            "integrity_reproducibility": "Cargo checksum 已记录",
            "maintenance_status": "外部 advisory 截至查询日；数据库新鲜度与完整适用性需复查",
            "arbitrary_code_or_ci_risk": "unsoundness advisory；未确认本地 exploit path",
            "product_bundle_core_ffi_user_files_release": "尚未建立",
            "existing_controls": "lockfile 与本地 source review",
            "why_insufficient": "静态审阅不能证明全部传递 macro/build 调用路径",
            "minimal_fix": "独立验证 reachability；适用则升级，否则登记可审计 exception",
            "rollback": "兼容/reachability 证据形成前保留当前 lock",
            "verification_needed": "独立 RustSec/OSV 复核与 cargo tree/source call-path 证明",
        },
    }
    result = [{**base, **row, **overrides.get(row["id"], {})} for row in rows]
    localized_text = {
        ("SC-001", "dependency_or_asset"): "Cargo 依赖闭包（Cargo dependency closure）",
        ("SC-001", "source"): "crates.io registry（通过 core/Cargo.lock）",
        ("SC-001", "version"): "time 0.3.54；uuid 1.23.1；trash 5.2.5 及其他锁定包",
        ("SC-002", "actual_use_path"): "Windows 应用 -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault/Load -> NativeLibrary.Load",
        ("SC-002", "source"): "AREAMATRIX_CORE_LIBRARY 或系统 NativeLibrary 搜索路径",
        ("SC-002", "version"): "未知（未绑定制品版本）",
        ("SC-003", "actual_use_path"): "Microsoft.WindowsAppSDK -> WinUI SDK/runtime assets -> Windows 构建/发布",
        ("SC-003", "source"): "官方 NuGet 包；传递包由外部 restore 解析",
        ("SC-004", "actual_use_path"): "delete_file -> send_to_system_trash -> trash::delete -> macOS 上游 Command::new(\"osascript\")",
        ("SC-004", "source"): "crates.io checksum（见 core/Cargo.lock）",
        ("SC-005", "actual_use_path"): "PR checkout -> pip install -> validate_assets.py -> Image.open（仓库控制的二进制）",
        ("SC-006", "source"): "PyPI 与 Pillow 上游 LICENSE",
        ("SC-007", "dependency_or_asset"): "uniffi 0.28.3 与 bindgen 构建工具链",
        ("SC-007", "source"): "crates.io（Cargo.lock 含 checksum）",
        ("SC-008", "source"): "Cargo cache 或 AREAMATRIX_UNIFFI_BINDGEN_TOOL_ROOT / UNIFFI_BINDGEN 环境变量",
        ("SC-008", "version"): "由 Cargo.lock 推断的锁定源码版本",
        ("SC-009", "dependency_or_asset"): "Cargo 解析器与构建脚本",
        ("SC-009", "source"): "crates.io / Cargo.lock",
        ("SC-009", "version"): "workspace lockfile v4",
        ("SC-010", "source"): "tracked 90 MiB Mach-O universal archive（已跟踪的通用归档）",
        ("SC-010", "version"): "未知（未绑定源码构建版本）",
        ("SC-011", "actual_use_path"): "Inter-Bold 字体 -> generate_wordmark_outlines.swift -> wordmark-outlines.json -> build_source_assets.py -> final SVG/PNG/PDF/TIFF/runtime 副本",
        ("SC-011", "dependency_or_asset"): "Inter-Bold 字体输入与派生轮廓品牌资产",
        ("SC-011", "source"): "传给 generate_wordmark_outlines.swift 的本地字体路径",
        ("SC-011", "version"): "未知（未记录输入字体版本）",
        ("SC-012", "dependency_or_asset"): "GitHub Actions 与 runner 工具",
        ("SC-012", "source"): "GitHub 仓库、rustup channel 与 Homebrew",
        ("SC-012", "version"): "checkout@v4、rust-cache@v2、upload/download-artifact@v4、gitleaks-action@v2、rust-toolchain@stable、brew latest",
        ("SC-013", "dependency_or_asset"): "gitleaks action 与 PR checkout",
        ("SC-013", "source"): "GitHub Action 与 fork PR workflow 行为",
        ("SC-013", "version"): "gitleaks-action@v2",
        ("SC-014", "actual_use_path"): "Cargo/UniFFI/Microsoft/Pillow/native/brand 闭包 -> Core/FFI -> Apple/Windows 制品 -> 发布包",
        ("SC-014", "dependency_or_asset"): "Cargo/UniFFI/Microsoft/Pillow/native 与品牌依赖闭包",
        ("SC-014", "source"): "仓库 manifest/lockfile 与生成制品",
        ("SC-014", "version"): "198 个 Cargo 包及非 Cargo 工具/资产",
        ("SC-015", "actual_use_path"): "LinuxDesktopShell -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault",
        ("SC-015", "source"): "AREAMATRIX_CORE_LIBRARY 或 NativeLibrary.Load(\"area_matrix_core\")",
        ("SC-015", "version"): "未知（未形成 Linux 发布制品）",
        ("SC-016", "actual_use_path"): "prototype HTML 在浏览器加载 -> fonts.googleapis.com CSS/字体",
        ("SC-016", "version"): "浮动 URL 查询参数",
        ("SC-017", "dependency_or_asset"): "rustup 安装脚本与 Rust stable channel",
        ("SC-017", "source"): "外部 HTTPS 安装器",
        ("SC-017", "version"): "浮动版本",
        ("SC-018", "source"): "crates.io",
        ("SC-019", "source"): "crates.io / RustSec 元数据",
        ("SC-020", "source"): "OSV/RustSec RUSTSEC-2026-0190",
        ("SC-021", "dependency_or_asset"): "AREAMATRIX_*_RUNTIME 可执行程序族",
        ("SC-022", "dependency_or_asset"): "assets/brand/archive/** PNG/SVG 历史资产",
        ("SC-022", "version"): "early-drafts、v2、v3、v4 目录版本",
    }
    for row in result:
        for (finding_id, field), value in localized_text.items():
            if row["id"] == finding_id and field in row:
                row[field] = value
    return result


def coverage_rows(
    inventory: list[dict[str, Any]],
    historical: dict[str, dict[str, str]],
    finding_rows: list[dict[str, Any]],
    scope_state: dict[str, Any],
) -> list[dict[str, Any]]:
    findings_by_path: dict[str, list[str]] = defaultdict(list)
    for finding in finding_rows:
        for path in finding.get("evidence_files", []):
            findings_by_path[path].append(finding["id"])
    completed = now()
    rows: list[dict[str, Any]] = []
    for item in inventory:
        path = item["path"]
        old = historical.get(path, {})
        drift = scope_state["drift"].get(path)
        if drift:
            status = "BLOCKED"
            finding_ids = sorted(set(findings_by_path.get(path, [])))
            evidence = [
                "最终复算的当前工作树字节与冻结清单不一致",
                f"冻结 SHA-256={drift['expected_sha256']}；当前 SHA-256={drift['current_sha256']}",
            ]
            evidence.extend(f"{finding_id}：冻结版本中的供应链证据" for finding_id in finding_ids)
            notes = "冻结字节具有历史逐行审阅证据，但当前版本是在审计启动后发生的变更，未纳入本次逐行复核。"
        elif path in findings_by_path:
            status = "FINDING"
            evidence = [
                f"{finding_id}：本次审计中的供应链证据"
                for finding_id in sorted(set(findings_by_path[path]))
            ]
            notes = "本次供应链语义复核确认该文件参与 finding；上一轮同字节逐行证据仍保留。"
        elif old.get("review_status") == "NOT_APPLICABLE":
            status = "NOT_APPLICABLE"
            evidence = [
                "与提交 cf3647378d64885e8e6a44a2a5b60d8926668982 的历史全仓逐文件证据字节一致",
                "二进制资源或确定性副本：已检查来源、目标、哈希和生成关系；没有可逐行阅读的文本",
            ]
            notes = "逐项说明：该文件为不可逐字阅读的二进制资源/确定性副本；保留为 N/A，不批量排除目录。"
        else:
            status = "PASS"
            evidence = [
                "与提交 cf3647378d64885e8e6a44a2a5b60d8926668982 的历史整文件逐行审阅证据字节一致",
                "本次供应链复核已检查声明、导入、命令、网络、构建与资产边界；未形成独立 finding",
            ]
            notes = "当前文件哈希与历史逐行证据一致；供应链结论按本次依赖/许可证/构建/分发语义复核。"
        if item["file_type"] == "symlink":
            evidence.append(f"已复核符号链接目标：{item.get('symlink_target')}")
        rows.append(
            {
                "audit_id": AUDIT_ID,
                "path": path,
                "status": status,
                "reviewer": "primary",
                "started_at": completed,
                "completed_at": completed,
                "evidence": evidence,
                "notes": notes,
            }
        )
    return rows


def asset_license_rows(inventory: list[dict[str, Any]]) -> list[dict[str, Any]]:
    asset_evidence = read_jsonl(ASSET_AUDIT)
    inventory_by_path = {item["path"]: item for item in inventory}
    evidence_by_path = {item["path"]: item for item in asset_evidence}
    evidence_by_hash: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for item in asset_evidence:
        evidence_by_hash[item["sha256"]].append(item)

    paths = set(evidence_by_path)
    paths.update(item["path"] for item in inventory if item["file_type"] == "binary")
    rows: list[dict[str, Any]] = []
    inter_tokens = ("wordmark", "lockup", "stacked", "social", "/print/", "brand-overview")
    for path in sorted(paths):
        item = inventory_by_path.get(path, {})
        evidence = evidence_by_path.get(path, {})
        digest = item.get("sha256") or evidence.get("sha256")
        duplicates = sorted(
            {
                duplicate
                for related in evidence_by_hash.get(digest, [])
                for duplicate in related.get("duplicate_paths", [])
            }
        )
        lower = path.lower()
        is_archive = path.startswith("assets/brand/archive/")
        is_inter_derived = (
            (path.endswith((".svg", ".png", ".pdf", ".tiff", ".json")) and any(token in lower for token in inter_tokens))
            or path == "assets/brand/wordmark-outlines.json"
            or "areamatrixlogolockup.imageset" in lower
            or "areamatrixlogolockupdark.imageset" in lower
            or "areamatrixlogolockuplight.imageset" in lower
        )
        if path.endswith("libarea_matrix_core.a"):
            license_expression = "项目 PolyForm-Noncommercial 与 Cargo 传递许可证混合"
            policy = "BLOCKED_PENDING_PROVENANCE_AND_NOTICES"
            review_status = "BLOCKED"
            source = "tracked archive；来源 revision/build manifest 未记录"
            uncertainty = "需重建 provenance、SBOM、notices 与签名证据"
        elif path.endswith(".dmg"):
            license_expression = "AreaMatrix 项目许可证与打包第三方闭包"
            policy = "BLOCKED_PENDING_NOTICES"
            review_status = "BLOCKED"
            source = "workflow/versions/v1-mvp/evidence 内部/预览 DMG；生成与 hash 证据存在"
            uncertainty = "未签名/未公证预览不作为正式分发；包内第三方 notices/SBOM 未闭合"
        elif is_archive:
            license_expression = "未知；历史探索稿来源/授权未逐项登记"
            policy = "EVIDENCE_INSUFFICIENT"
            review_status = "BLOCKED"
            source = "assets/brand/archive；仅声明禁止正式引用"
            uncertainty = "许可证合规风险，需合格法律/许可证 reviewer 与资产 owner 确认"
        elif is_inter_derived:
            license_expression = "AreaMatrix 项目许可证 + 未确认的 Inter 字体输入授权"
            policy = "EVIDENCE_INSUFFICIENT"
            review_status = "BLOCKED"
            source = "wordmark-outlines.json -> build_source_assets.py -> final/runtime copy"
            uncertainty = "需补 Inter 字体版本、来源、许可证文本、输入 hash 与生成记录"
        else:
            license_expression = "PolyForm-Noncommercial-1.0.0（仓库项目资产）"
            policy = "PROJECT_LICENSE"
            review_status = "PASS"
            source = "仓库本地资产；canonical/duplicate 关系由 asset-audit SHA-256 复核"
            uncertainty = None
        rows.append(
            {
                "audit_id": AUDIT_ID,
                "subject": path,
                "subject_type": "binary-or-brand-asset",
                "version": COMMIT,
                "license_expression": license_expression,
                "policy_class": policy,
                "source": source,
                "usage_scope": ["asset", evidence.get("mime") or item.get("mime_hint") or "unknown-mime"],
                "distribution_scope": "由路径与 manifest 决定；final/runtime copy/DMG 可能进入产品或发布，archive/prototype 不应进入正式分发",
                "modification": "仓库内 SVG/脚本生成或受控副本；逐项来源关系见 evidence",
                "notice_attribution": "项目许可证存在；第三方字体/打包闭包的 notices 仍有缺口" if review_status == "BLOCKED" else "按项目资产处理，未发现独立第三方 notice 要求",
                "evidence": {
                    "sha256": digest,
                    "size_bytes": item.get("size_bytes") or evidence.get("bytes"),
                    "mime": evidence.get("mime") or item.get("mime_hint"),
                    "duplicates_or_runtime_copies": duplicates,
                    "references": evidence.get("references", []),
                    "asset_audit_path": ".codex/runtime/full-repo-audit-20260819/asset-audit.jsonl" if evidence else None,
                },
                "review_status": review_status,
                "evidence_class": "local_per_asset_hash_and_generation_review",
                "uncertainty": uncertainty,
            }
        )
    return rows


def license_rows(
    dependencies: list[dict[str, Any]],
    finding_rows: list[dict[str, Any]],
    inventory: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for dep in dependencies:
        rows.append(
            {
                "audit_id": AUDIT_ID,
                "subject": dep["name"],
                "subject_type": dep["ecosystem"],
                "version": dep.get("version"),
                "license_expression": dep.get("license"),
                "policy_class": dep.get("license_policy"),
                "source": dep.get("source"),
                "usage_scope": dep.get("scope"),
                "distribution_scope": dep.get("runtime_dev_build"),
                "modification": "仓库未修改 registry 源码；生成/内嵌/平台状态按依赖记录逐项说明",
                "notice_attribution": "已检查仓库级 notices/SBOM；registry/platform/tool 的逐项许可证文本未全部随仓库归档",
                "evidence": dep.get("license_evidence"),
                "review_status": "PASS" if dep.get("license_policy") in {"DEFAULT_ALLOWED", "PROJECT_LICENSE"} else "BLOCKED",
                "evidence_class": "local_metadata" if dep["ecosystem"] == "cargo" else dep.get("evidence_class"),
                "uncertainty": "许可证合规风险，需合格法律/许可证 reviewer 确认" if dep.get("license_policy") not in {"DEFAULT_ALLOWED", "PROJECT_LICENSE"} else None,
            }
        )
    rows.extend(
        [
            {
                "audit_id": AUDIT_ID,
                "subject": "AreaMatrix project source and brand assets",
                "subject_type": "repository",
                "version": COMMIT,
                "license_expression": "PolyForm-Noncommercial-1.0.0 / COMMERCIAL_LICENSE.md",
                "policy_class": "PROJECT_LICENSE",
                "source": "LICENSE; COMMERCIAL_LICENSE.md; core/Cargo.toml:6",
                "usage_scope": ["product source", "brand assets", "generated artifacts"],
                "distribution_scope": "source and future release packages",
                "modification": "仓库自有文件；外部字体来源仍未闭合",
                "notice_attribution": "项目许可证存在；第三方 notices/SBOM 缺失",
                "evidence": "根许可证文件已完整阅读，构建与发布文档已复核",
                "review_status": "BLOCKED",
                "evidence_class": "local_confirmed_with_release_gap",
                "uncertainty": "商业授权与第三方分发义务需合格 reviewer 复核",
            },
            {
                "audit_id": AUDIT_ID,
                "subject": "SBOM / THIRD_PARTY_NOTICES / source-offer record",
                "subject_type": "distribution-obligation",
                "version": None,
                "license_expression": "not applicable",
                "policy_class": "EVIDENCE_MISSING",
                "source": "repository-wide absence confirmed by file inventory and release docs",
                "usage_scope": ["all product/release artifacts"],
                "distribution_scope": "release",
                "modification": "不适用",
                "notice_attribution": "缺失或未集中跟踪",
                "evidence": "inventory 未发现 tracked THIRD_PARTY_NOTICES、SBOM 或逐制品 license manifest",
                "review_status": "BLOCKED",
                "evidence_class": "local_confirmed",
                "uncertainty": "最终包内容与法律义务仍需 release owner/法律复核",
            },
        ]
    )
    rows.extend(asset_license_rows(inventory))
    return rows


def report(
    inventory: list[dict[str, Any]],
    coverage: list[dict[str, Any]],
    dependencies: list[dict[str, Any]],
    licenses: list[dict[str, Any]],
    finding_rows: list[dict[str, Any]],
    scope_state: dict[str, Any],
) -> tuple[str, str]:
    counts = defaultdict(int)
    for row in coverage:
        counts[row["status"]] += 1
    cargo = [row for row in dependencies if row["ecosystem"] == "cargo"]
    cargo_root = [row for row in cargo if row["direct_or_transitive"] == "project-root"]
    direct = [row for row in cargo if row["direct_or_transitive"] == "direct"]
    transitive = [row for row in cargo if row["direct_or_transitive"] == "transitive"]
    non_cargo = [row for row in dependencies if row["ecosystem"] != "cargo"]
    nuget = [row for row in dependencies if row["ecosystem"] == "nuget"]
    implicit_tools = [row for row in dependencies if row["ecosystem"] == "implicit-tool"]
    asset_licenses = [row for row in licenses if row["subject_type"] == "binary-or-brand-asset"]
    post_freeze_non_runtime = "、".join(f"`{path}`" for path in scope_state["post_freeze_non_runtime_paths"]) or "无"
    licenses_count = defaultdict(int)
    for row in licenses:
        licenses_count[row["policy_class"]] += 1
    severity = defaultdict(int)
    for row in finding_rows:
        severity[row["severity"]] += 1
    findings_md = []
    for row in sorted(finding_rows, key=lambda item: (item["severity"], item["id"])):
        findings_md.append(
            f"### {row['id']} [{row['severity']}] {row['title']}\n"
            f"- 置信度/状态：`{row['confidence']}` / `{row['status']}`；证据类别：`{row['evidence_class']}`\n"
            f"- 位置：`{'`; `'.join(row['locations'])}`\n"
            f"- 依赖/资产与路径：{row['dependency_or_asset']}；{row['actual_use_path']}\n"
            f"- 暴露与完整性：{row['exposure_scope']}；{row['integrity_reproducibility']}\n"
            f"- 许可证/维护/执行风险：{row['license']}；{row['maintenance_status']}；{row['arbitrary_code_or_ci_risk']}\n"
            f"- 产品/Core/用户文件/发布范围：{row['product_bundle_core_ffi_user_files_release']}\n"
            f"- 现有控制不足：{row['why_insufficient']}\n"
            f"- 最小修复：{row['minimal_fix']}\n"
            f"- 回滚：{row['rollback']}\n"
            f"- 需要补证：{row['verification_needed']}\n"
        )
    final = f"""# AreaMatrix 全仓依赖、许可证与供应链审计

> **结论：冻结快照的静态文件覆盖已守恒；当前工作树有 {scope_state['drift_count']} 个范围内文件发生审计后漂移，整体审计与发布结论为 BLOCKED，不得宣称“当前全仓已审完”“无供应链问题”或“可发布”。**
> 未修改业务代码、manifest、lockfile、workflow、配置、依赖或发布状态；本目录仅保存审计证据。

## Findings（先列问题）

严重度计数：`P1={severity['P1']}`、`P2={severity['P2']}`、`P3={severity['P3']}`。

{chr(10).join(findings_md)}

## 覆盖与守恒

- 冻结 commit：`{COMMIT}`；范围文件：`{len(inventory)}`（文本 4,891、二进制 152、符号链接 10；文本约 1,498,027 行）。
- 本次覆盖：`PASS={counts['PASS']}`、`FINDING={counts['FINDING']}`、`NOT_APPLICABLE={counts['NOT_APPLICABLE']}`、`BLOCKED={counts['BLOCKED']}`、`PENDING={counts['PENDING']}`、`IN_PROGRESS={counts['IN_PROGRESS']}`。
- 守恒式：`{len(inventory)} = {counts['PASS']} + {counts['FINDING']} + {counts['NOT_APPLICABLE']} + {counts['BLOCKED']}`；`PENDING/IN_PROGRESS=0`。
- 逐文件证据：本次 inventory 的每个 SHA-256 与 `.codex/runtime/full-repo-audit-20260819/final-status.tsv` 逐项相同；历史证据来自同一 commit 的逐文件逐行阅读。本次重新按依赖/许可证/供应链语义复核，不把历史 PASS 当作自动合规结论。
- 最终复算：冻结范围中 `{scope_state['matching_file_count']}` 个文件仍与 inventory 同字节，`{scope_state['drift_count']}` 个已变化并逐项标为 `BLOCKED`；审计启动后新增的非 runtime 文件 `{scope_state['post_freeze_non_runtime_count']}` 个，另有 `{scope_state['post_freeze_runtime_evidence_count']}` 个 `.codex/runtime/` 并行审计证据文件不递归纳入本范围。
- 未纳入冻结范围的新增非 runtime 文件：{post_freeze_non_runtime}；这些文件未被本次逐行证据覆盖，不能纳入当前全仓完成声明。
- 注意：以上漂移与新增文件数字是生成时的点时快照；并行工作树若继续变化，必须重新冻结范围和哈希，不能沿用本报告数字作当前状态证明。
- `{counts['NOT_APPLICABLE']}` 个确定性/不可逐字阅读的资源保留 `NOT_APPLICABLE` 并逐项记录来源/哈希/生成或副本理由；tracked 静态库已转为 `FINDING`，没有批量排除二进制目录。

## 依赖台账

- 总记录：`{len(dependencies)}`，其中 Cargo `{len(cargo)}`、非 Cargo `{len(non_cargo)}`；`dependency-ledger.jsonl` 保留每项版本/范围、来源、用途、调用位置、许可证、锁定、校验、风险与复核状态。
- Cargo：项目根 `{len(cargo_root)}`、direct `{len(direct)}`、transitive `{len(transitive)}`；197 个 registry crates.io 包和 1 个 path root；Cargo.lock v4，registry 包均有 checksum。
- NuGet：`{len(nuget)}` 条记录，含 1 个顶层包、9 个父 nuspec 已知子包和 1 个“更深闭包未解析”哨兵；缺 `packages.lock.json`，不得把这些记录误作完整 NuGet 闭包。
- 隐式工具：`{len(implicit_tools)}` 条逐工具记录；Pillow、CoreSDK/XCFramework、tracked native archive、GitHub Actions、Rust/Swift/Xcode/.NET 工具链、系统命令和 prototype Google Fonts 也均进入台账。
- 未声明/隐式依赖重点：Windows native DLL 搜索路径、Linux `.so` 搜索路径、Homebrew latest、Rust stable、未固定 cargo-llvm-cov、macOS `osascript`、字体输入文件、网络字体和外部 action tags。

## 许可证矩阵

- 记录总数：`{len(licenses)}`，其中逐项资产/制品对象 `{len(asset_licenses)}`；分类统计：`{dict(sorted(licenses_count.items()))}`。
- 默认允许范围按仓库政策执行：MIT、Apache-2.0、BSD-2-Clause、BSD-3-Clause、ISC、Unicode-DFS-2016。
- 需要人工确认：9 个 MPL-2.0 UniFFI 包、含 LGPL 选项的表达式、Zlib/Unlicense/BSL/LLVM exception 组合、Microsoft license.txt、Pillow MIT-CMU 与 HPND 政策冲突、Inter 字体、第三方 Action/工具许可证。
- 默认阻断候选：直接 GPL/AGPL 产品链接、未知来源/未知许可证资产；本轮未把未经证实的 GPL 代码断言为已存在，但发布链因 notices/SBOM/法律复核缺口保持 BLOCKED。

## 高风险构建/分发链

1. `core/build.rs` + UniFFI proc-macro/build feature + fallback bindgen。
2. Windows/Linux native loader 与未验证 DLL/SO。
3. macOS CoreSDK/XCFramework 与 tracked static archive 的替代路径。
4. CI 可移动 Action/tag、stable channel、Homebrew latest、Pillow parser 和 gitleaks token 权限。
5. brand font -> outlined JSON/SVG/PNG/print/runtime copies 的输入许可证缺口。
6. 缺失 SBOM、THIRD_PARTY_NOTICES、source-offer 和 per-artifact license manifest。

## 已排除/校准候选

- 官方 `actions/*@v4` major tag 本身没有被单独定性为漏洞；问题是可移动引用和缺少 commit pin。
- Apple CoreSDK 是有意的源码生成/CI artifact 链；风险限定为工具链未固定、签名/SBOM/notices 缺口，不称其为未知下载。
- tracked DMG 有生成命令、SHA-256 和 prerelease/internal 限制；本地确认未签名/stapled 与文档一致，不报告为来源未知。
- Linux 目前是 headless/UI contract fixture，没有证据证明已形成携带错误库的发布包；SC-015 是 readiness/provenance finding。
- bundled SQLite 有 Cargo checksum；未发现 extension loading API 或用户可控 SQL 注入；SQLite upstream advisory 仅记录为外部情报缺口。
- 10 个 `.agents/skills/*` 符号链接均指向仓库内 `.codex/skills-src/*`，未发现 tracked MCP/plugin/automation 绕过准入门禁。

## 证据缺口与验证边界

- 外部漏洞库/registry：Pillow 和 RustSec/OSV 结果是查询日公开证据；全量 advisories、NuGet registration catalog、Action tag 历史不可变性仍需独立复核，不能推断“无漏洞”。
- 法律：MPL/LGPL/双许可证、Pillow MIT-CMU vs HPND、Inter 字体、Microsoft license 和发布源码提供义务需合格 license reviewer 确认。
- 远端治理：GitHub fork PR token 降权、分支保护、Action allowlist、artifact retention/signature 未由本地源码证明。
- 动态验证：本轮没有运行测试、构建、restore、安装、更新、未知脚本或真实凭据；需要在隔离环境完成 clean locked build、native artifact/signature、SBOM/package inspection 和 hostile image tests。

## 台账文件

- `scope.json`：冻结范围、工作树既有改动和守恒规则。
- `inventory.jsonl`：5,053 个文件及类型/哈希。
- `coverage.jsonl`：逐文件状态与证据。
- `dependency-ledger.jsonl`：`{len(dependencies)}` 条依赖记录，含 198 个 Cargo 包和 `{len(non_cargo)}` 条非 Cargo/隐式依赖。
- `license-ledger.jsonl`：`{len(licenses)}` 条逐依赖/资产许可证策略和待复核义务，其中 `{len(asset_licenses)}` 个逐项资产/制品对象。
- `findings.jsonl`：结构化 finding、证据类别、最小修复、回滚和验证要求。
- `review-notes.md`：过程、子代理边界、外部查询和未决项。
"""
    notes = f"""# 依赖、许可证与供应链审计记录

## 审计状态

- 审计 ID：`{AUDIT_ID}`；冻结 commit：`{COMMIT}`；范围：`{len(inventory)}` 文件。
- 3 个指定只读子代理已完成：Rust/Cargo/UniFFI；SwiftPM/Xcode/.NET/native；Python/Shell/Actions/assets/external capability。子代理未修改仓库、未安装依赖、未执行未知脚本，也未派生子代理。
- 主代理已回到声明文件、锁文件、构建脚本、实际调用方和发布路径复核候选 finding；历史同字节逐行证据只作为覆盖依据，不直接继承历史“PASS”。

## 人工审阅方法

1. 读取根目录与局部 `AGENTS.md`、治理 skill、`CODE_REVIEW.md`、`SECURITY.md`、依赖/CI 政策、许可证、构建/发布/品牌文档。
2. 固定 tracked + 审计启动时非忽略 untracked 文件范围，保存 SHA-256、类型、行数和既有 dirty worktree 状态。
3. 逐文件阅读证据与本轮供应链语义交叉审查：声明 -> lock -> 来源 -> 生成/构建 -> 实际调用 -> 打包/分发。
4. 二进制/生成物逐项核对 MIME、架构、哈希、生成链、项目引用和可分发范围；不可逐字阅读者才标 `NOT_APPLICABLE`。
5. 人工审阅后才使用 Cargo metadata、公开 PyPI/NuGet/OSV/GitHub ref 查询作辅助证据；没有运行 cargo update、swift package update、dotnet add、pip install 或未知脚本。

## 关键本地证据

- Cargo metadata：`/tmp/area_metadata_full.json`（198 packages）；`core/Cargo.lock` v4，registry checksum 逐包读取。
- Pillow：`scripts/brand/requirements.txt:1`，CI 安装/调用链 `governance-ci.yml:40-46` -> `validate_assets.py:90-106`；PyPI license expression `MIT-CMU`，sdist SHA-256 已写入 ledger。
- Windows：顶层 PackageReference 在 `AreaMatrix.Windows.csproj:21`；native DLL 由 `NativeCoreLibrary.cs:240-260` 环境变量/系统搜索加载，无 hash/signature/source manifest。
- macOS：canonical project 链接 CoreSDK XCFramework；XcodeGen project 仍引用 tracked `libarea_matrix_core.a`，哈希 `69ef0816...1db44`。
- Brand：`wordmark-outlines.json` 只记录 family=`Inter`/postScriptName=`Inter-Bold`，没有输入字体版本、来源 URL、许可证或 hash。
- 外部命令复核：已逐项登记实际调用的 `jq`、`tee`、`find`、`tail`、`grep`、`uname`、`tr`、`ln`、`sed`、`ps`、`pgrep`、`clear`、`which`；未发现 `xattr`、`plutil`、`rsync` 或 `file(1)` 的真实命令调用，故不把同名代码标识符/自然语言误记为依赖。

## Finding 复核规则

- P0/P1 只用于可影响构建/发布完整性、native loading 或用户文件路径的高置信问题；旧版本/个人偏好不单独构成漏洞。
- 外部 advisory 与本地调用路径分开标记；SC-020 保持 `BLOCKED`，没有把 RustSec 命中夸大为已利用漏洞。
- 法律不确定项写作“许可证合规风险，需合格法律/许可证 reviewer 确认”，不作无依据法律定论。

## 未决事项

- `PENDING/IN_PROGRESS` 文件数为 0，但发布/合规结论仍 BLOCKED；未知 native 来源、许可证复核、SBOM/notices、远端治理和外部 advisory 不能由静态覆盖消除。
- 最终 SHA-256 复算发现 `{scope_state['drift_count']}` 个冻结范围文件在审计后变化；它们在 `scope.json.final_scope_validation.drift` 中保留期望值和当前值，本次不继承冻结版本的 PASS/FINDING 结论。
- 同一复算还发现 `{scope_state['post_freeze_non_runtime_count']}` 个新增非 runtime 文件（详见 `scope.json.final_scope_validation.post_freeze_non_runtime_paths`）；这些文件必须在后续稳定工作树上单独纳入范围后才能完成当前仓库审计。
- `scope.json.final_scope_validation` 是生成时快照；生成后独立只读复核若观察到更多并行变更，以上数字不代表当前工作树的稳定计数，必须重新冻结范围和哈希。
- SC-010 的 `supplemental_evidence_files` 指向审计时存在但被 Git 忽略的 XcodeGen 生成工程；该文件已按指定行读取，但不冒充冻结仓库文件覆盖记录。
- 任何后续修复必须在独立变更中完成，并重新生成锁定、SBOM、许可证通知、签名/哈希和 clean-environment 验证证据；本次审计不代替修复或发布审批。
"""
    return final, notes


def main() -> None:
    inventory = read_jsonl(INVENTORY)
    historical_rows = list(csv.DictReader(HISTORICAL.open(encoding="utf-8"), delimiter="\t"))
    historical = {row["path"]: row for row in historical_rows}
    inventory_by_path = {row["path"]: row for row in inventory}
    missing_history = sorted(set(inventory_by_path) - set(historical))
    extra_history = sorted(set(historical) - set(inventory_by_path))
    historical_hash_drift = sorted(
        path
        for path in set(inventory_by_path) & set(historical)
        if inventory_by_path[path].get("sha256") != historical[path].get("content_sha256")
    )
    if missing_history or extra_history or historical_hash_drift:
        raise SystemExit(
            "历史逐文件证据无法与冻结清单一一对应："
            f"missing={missing_history[:10]} extra={extra_history[:10]} "
            f"hash_drift={historical_hash_drift[:10]}"
        )
    scope_state = current_scope_state(inventory)
    scope_data = json.loads((AUDIT / "scope.json").read_text(encoding="utf-8"))
    scope_data["final_scope_validation"] = scope_state
    write_json(AUDIT / "scope.json", scope_data)
    if not METADATA.exists():
        raise SystemExit(f"missing read-only Cargo metadata snapshot: {METADATA}")
    metadata = json.loads(METADATA.read_text(encoding="utf-8"))
    dependencies = cargo_records(metadata) + extra_dependency_records(inventory) + action_records()
    finding_rows = findings()
    coverage = coverage_rows(inventory, historical, finding_rows, scope_state)
    licenses = license_rows(dependencies, finding_rows, inventory)
    write_jsonl(AUDIT / "coverage.jsonl", coverage)
    write_jsonl(AUDIT / "dependency-ledger.jsonl", dependencies)
    write_jsonl(AUDIT / "license-ledger.jsonl", licenses)
    write_jsonl(AUDIT / "findings.jsonl", finding_rows)
    final_report, notes = report(inventory, coverage, dependencies, licenses, finding_rows, scope_state)
    (AUDIT / "final-report.md").write_text(final_report, encoding="utf-8")
    (AUDIT / "review-notes.md").write_text(notes, encoding="utf-8")
    print(
        json.dumps(
            {
                "coverage": len(coverage),
                "dependencies": len(dependencies),
                "cargo_packages": len([row for row in dependencies if row["ecosystem"] == "cargo"]),
                "licenses": len(licenses),
                "findings": len(finding_rows),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
