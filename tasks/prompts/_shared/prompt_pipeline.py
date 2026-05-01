#!/usr/bin/env python3
from __future__ import annotations

import argparse
from contextlib import redirect_stdout
from dataclasses import dataclass, field
from datetime import datetime, timezone
import io
import json
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[3]
PROMPTS_ROOT = ROOT / "tasks" / "prompts"
SHARED_ROOT = PROMPTS_ROOT / "_shared"
MANIFEST_ROOT = SHARED_ROOT / "manifests"
AUDIT_RULES = SHARED_ROOT / "audit-rules.md"
TASK_SLICING_RULES = SHARED_ROOT / "task-slicing-rules.md"
ENGINEERING_QUALITY_RULES = SHARED_ROOT / "engineering-quality-rules.md"
DEPENDENCY_GRAPH = SHARED_ROOT / "dependency-graph.md"
CODING_STANDARDS = ROOT / "docs" / "development" / "coding-standards.md"
PROGRESS_PATH = SHARED_ROOT / "progress.json"
COPY_READY_ROOT = SHARED_ROOT / "copy-ready"
VERIFY_READY_ROOT = SHARED_ROOT / "verify-ready"

ALLOWED_NEW_ROOTS = (
    "AGENTS.md",
    "README.md",
    "README.zh-CN.md",
    "CHANGELOG.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "LICENSE",
    ".ai-governance/",
    ".codex/",
    ".github/",
    "apps/",
    "core/",
    "docs/",
    "scripts/",
    "specs/",
    "tasks/",
)

HIGH_RISK_PATH_PATTERNS = (
    "adopt",
    "ai-summary",
    "area_matrix.udl",
    "core-api",
    "data-model",
    "db",
    "ffi",
    "fs-watcher",
    "icloud",
    "migration",
    "privacy",
    "recovery",
    "source-of-truth",
    "staging",
    "storage",
    "sync",
    "transactional",
    "local-ai",
    "stage3-ai",
)

TASK_RE = re.compile(r"^task-(\d+)-")
BATCH_RE = re.compile(r"^(\d+-\d+)-")
PHASE_RE = re.compile(r"^phase-(\d+)$")
LABEL_RE = re.compile(r"^(\d+-\d+)/task-(\d+)$")
LABEL_IN_TEXT_RE = re.compile(r"(\d+-\d+)/task-(\d+)")
MANIFEST_HEADING_RE = re.compile(r"^##\s+(.+)$", re.M)
UX_DOC_RE = re.compile(r"/(S(?:[1-3]-\d+|4-[A-Z]+-\d+)-[^/]+)\.md$")
CAPABILITY_DOC_RE = re.compile(r"/(C[1-4]-\d+)-[^/]+\.md$")
PAGE_ID_RE = re.compile(r"^S(?:[1-3]-\d+|4-[A-Z]+-\d+)$")
CAPABILITY_ID_RE = re.compile(r"C[1-4]-\d+")
CORE_VERIFY_RE = re.compile(r"\bC[1-4]-\d+\b.*\bintegration-verify\b", re.IGNORECASE)
PAGE_VERIFY_RE = re.compile(
    r"\bS(?:[1-3]-\d+|4-[A-Z]+-\d+)\b.*\bpage[- ]integration[- ]verify\b",
    re.IGNORECASE,
)
MARKDOWN_LINK_RE = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
EXTERNAL_LINK_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


@dataclass(frozen=True)
class TaskFile:
    label: str
    phase: str
    phase_number: int
    batch: str
    path: Path
    title: str


@dataclass
class ManifestEntry:
    label: str
    manifest_path: Path
    source_task: str = ""
    depends: list[str] = field(default_factory=list)
    sections: dict[str, list[str]] = field(default_factory=dict)
    raw: str = ""

    @property
    def risk(self) -> str:
        values = self.sections.get("Risk Level", [])
        return values[0] if values else "Unspecified"

    @property
    def exact_docs(self) -> list[str]:
        return self.sections.get("Exact Docs", [])

    @property
    def existing_code(self) -> list[str]:
        return self.sections.get("Existing Code", [])

    @property
    def expected_new_paths(self) -> list[str]:
        return self.sections.get("Expected New Paths", [])

    @property
    def validation(self) -> list[str]:
        return self.sections.get("Validation", [])

    @property
    def forbidden_touches(self) -> list[str]:
        return self.sections.get("Forbidden Touches", [])


@dataclass(frozen=True)
class PageContract:
    page_id: str
    page_name: str
    capabilities: tuple[str, ...]
    prompt_labels: tuple[str, ...]
    control_map_path: Path
    line_no: int


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def strip_bullet(line: str) -> str | None:
    stripped = line.strip()
    if not stripped.startswith("- "):
        return None
    value = stripped[2:].strip()
    if value.startswith("`") and value.endswith("`"):
        value = value[1:-1].strip()
    if value == "None":
        return None
    return value


def label_sort_key(label: str) -> tuple[int, int, int]:
    match = LABEL_RE.match(label)
    if not match:
        return (999, 999, 999)
    batch = match.group(1)
    first, second = batch.split("-")
    return (int(first), int(second), int(match.group(2)))


def task_title(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return path.stem


def scan_task_files() -> dict[str, TaskFile]:
    tasks: dict[str, TaskFile] = {}
    for phase_dir in sorted(PROMPTS_ROOT.glob("phase-*")):
        if not phase_dir.is_dir():
            continue
        phase_match = PHASE_RE.match(phase_dir.name)
        if not phase_match:
            continue
        phase_number = int(phase_match.group(1))
        for task_path in sorted(phase_dir.glob("*/*.md")):
            task_match = TASK_RE.match(task_path.name)
            batch_match = BATCH_RE.match(task_path.parent.name)
            if not task_match or not batch_match:
                continue
            batch = batch_match.group(1)
            label = f"{batch}/task-{task_match.group(1)}"
            if label in tasks:
                raise ValueError(f"duplicate task label: {label}")
            tasks[label] = TaskFile(
                label=label,
                phase=phase_dir.name,
                phase_number=phase_number,
                batch=batch,
                path=task_path,
                title=task_title(task_path),
            )
    return tasks


def parse_depends(line: str) -> list[str]:
    if "None" in line:
        return []
    return re.findall(r"`([^`]+)`", line)


def parse_manifest(path: Path) -> dict[str, ManifestEntry]:
    text = path.read_text(encoding="utf-8")
    headings = list(MANIFEST_HEADING_RE.finditer(text))
    entries: dict[str, ManifestEntry] = {}
    for index, heading in enumerate(headings):
        label = heading.group(1).strip()
        start = heading.start()
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        raw = text[start:end].rstrip()
        entry = ManifestEntry(label=label, manifest_path=path, raw=raw)
        section = ""
        for line in raw.splitlines()[1:]:
            if line.startswith("> source task:"):
                values = re.findall(r"`([^`]+)`", line)
                entry.source_task = values[0] if values else ""
                continue
            if line.startswith("> depends:"):
                entry.depends = parse_depends(line)
                continue
            if line.startswith("### "):
                section = line[4:].strip()
                entry.sections.setdefault(section, [])
                continue
            value = strip_bullet(line)
            if value and section:
                entry.sections.setdefault(section, []).append(value)
        entries[label] = entry
    return entries


def load_manifests() -> dict[str, ManifestEntry]:
    entries: dict[str, ManifestEntry] = {}
    for path in sorted(MANIFEST_ROOT.glob("phase-*.md")):
        for label, entry in parse_manifest(path).items():
            if label in entries:
                raise ValueError(f"duplicate manifest label: {label}")
            entries[label] = entry
    return entries


def is_allowed_new_path(value: str) -> bool:
    normalized = value.rstrip("*")
    return any(normalized == root.rstrip("/") or normalized.startswith(root) for root in ALLOWED_NEW_ROOTS)


def looks_high_risk(entry: ManifestEntry) -> bool:
    haystack = " ".join(
        [entry.source_task, *entry.exact_docs, *entry.existing_code, *entry.expected_new_paths]
    ).lower()
    return any(pattern in haystack for pattern in HIGH_RISK_PATH_PATTERNS)


def unique_doc_ids(values: list[str], pattern: re.Pattern[str]) -> list[str]:
    result: list[str] = []
    for value in values:
        match = pattern.search(value)
        if match and match.group(1) not in result:
            result.append(match.group(1))
    return result


def page_id_from_doc_id(doc_id: str) -> str:
    parts = doc_id.split("-")
    if doc_id.startswith("S4-"):
        return "-".join(parts[:3])
    return "-".join(parts[:2])


def entry_page_ids(entry: ManifestEntry) -> list[str]:
    result: list[str] = []
    for doc_id in unique_doc_ids(entry.exact_docs, UX_DOC_RE):
        page_id = page_id_from_doc_id(doc_id)
        if page_id not in result:
            result.append(page_id)
    return result


def entry_capability_ids(entry: ManifestEntry) -> list[str]:
    return unique_doc_ids(entry.exact_docs, CAPABILITY_DOC_RE)


def extract_labels(value: str) -> list[str]:
    result: list[str] = []
    for batch, number in LABEL_IN_TEXT_RE.findall(value):
        label = f"{batch}/task-{number}"
        if label not in result:
            result.append(label)
    return result


def load_page_contracts() -> dict[str, PageContract]:
    contracts: dict[str, PageContract] = {}
    for path in sorted((ROOT / "docs" / "architecture").glob("*control-map.md")):
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.startswith("| S"):
                continue
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) < 6 or not PAGE_ID_RE.match(cells[0]):
                continue
            capabilities: list[str] = []
            for capability in CAPABILITY_ID_RE.findall(cells[2]):
                if capability not in capabilities:
                    capabilities.append(capability)
            prompt_cell = cells[7] if len(cells) > 8 else cells[-1]
            contracts[cells[0]] = PageContract(
                page_id=cells[0],
                page_name=cells[1],
                capabilities=tuple(capabilities),
                prompt_labels=tuple(extract_labels(prompt_cell)),
                control_map_path=path,
                line_no=line_no,
            )
    return contracts


def task_kind(task: TaskFile, entry: ManifestEntry) -> str:
    haystack = f"{task.title} {entry.source_task} {entry.raw}".lower()
    if any(token in haystack for token in ["integration-verify", "integration verify", "集成验收", "验收"]):
        return "integration"
    return "atomic"


def task_identity_text(task: TaskFile, entry: ManifestEntry) -> str:
    return f"{task.title} {entry.source_task}".lower()


def is_core_integration_verify(task: TaskFile, entry: ManifestEntry) -> bool:
    return task_kind(task, entry) == "integration" and bool(CORE_VERIFY_RE.search(task_identity_text(task, entry)))


def is_page_integration_verify(task: TaskFile, entry: ManifestEntry) -> bool:
    return task_kind(task, entry) == "integration" and bool(PAGE_VERIFY_RE.search(task_identity_text(task, entry)))


def task_detail_kind(task: TaskFile, entry: ManifestEntry) -> str:
    pages = entry_page_ids(entry)
    capabilities = entry_capability_ids(entry)
    source = task_identity_text(task, entry)
    if task_kind(task, entry) == "integration":
        if is_core_integration_verify(task, entry):
            return "core-integration-verify"
        if is_page_integration_verify(task, entry):
            return "page-integration"
        if "foundation" in source:
            return "foundation-verify"
        return "stage-verify"
    if pages:
        return "page-feature"
    if "contract-api" in source:
        return "core-contract"
    if "failure" in source or "edge" in source:
        return "core-failure-edge"
    if "validation" in source:
        return "core-validation"
    if capabilities:
        return "core-implementation"
    return "atomic"


def binding_summary(entry: ManifestEntry) -> tuple[str, str]:
    ux_ids = unique_doc_ids(entry.exact_docs, UX_DOC_RE)
    capability_ids = entry_capability_ids(entry)
    return (
        ", ".join(ux_ids) if ux_ids else "None",
        ", ".join(capability_ids) if capability_ids else "None",
    )


def validate_granularity(task: TaskFile, entry: ManifestEntry) -> list[str]:
    if task_kind(task, entry) == "integration":
        return []
    page_ids = entry_page_ids(entry)
    capability_ids = entry_capability_ids(entry)
    page_contracts = load_page_contracts()
    errors: list[str] = []
    if len(page_ids) > 1:
        errors.append(f"{task.label}: atomic task binds multiple UX pages: {', '.join(page_ids)}")
    if page_ids:
        expected = set(page_contracts.get(page_ids[0], PageContract(page_ids[0], "", (), (), ROOT, 0)).capabilities)
        extra = sorted(set(capability_ids) - expected)
        if extra:
            errors.append(
                f"{task.label}: UI task references Core capabilities not declared for {page_ids[0]}: {', '.join(extra)}"
            )
        if len(capability_ids) > 1:
            errors.append(
                f"{task.label}: page-feature atomic task binds multiple Core capabilities: {', '.join(capability_ids)}"
            )
        if expected and not capability_ids:
            errors.append(f"{task.label}: page-feature atomic task does not bind a Core capability for {page_ids[0]}")
    elif len(capability_ids) > 1:
        errors.append(
            f"{task.label}: atomic task binds multiple Core capabilities: {', '.join(capability_ids)}"
        )
    if task.phase in {"phase-1", "phase-2", "phase-4"} and not page_ids and not capability_ids:
        errors.append(f"{task.label}: atomic product task must bind one UX page or one Core capability")
    return errors


def page_contract_summary(task: TaskFile, entry: ManifestEntry) -> tuple[str, str, str, str]:
    page_contracts = load_page_contracts()
    pages = entry_page_ids(entry)
    covered = set(entry_capability_ids(entry))
    expected: set[str] = set()
    page_parts: list[str] = []
    for page_id in pages:
        contract = page_contracts.get(page_id)
        if not contract:
            page_parts.append(f"{page_id}: not in control map")
            continue
        expected.update(contract.capabilities)
        page_parts.append(
            f"{page_id}: {', '.join(contract.capabilities) if contract.capabilities else 'None'}"
        )
    if task_detail_kind(task, entry) == "core-integration-verify":
        missing: list[str] = []
    else:
        missing = sorted(expected - covered)
    extra = sorted(covered - expected) if pages else []
    return (
        "; ".join(page_parts) if page_parts else "None",
        ", ".join(sorted(covered)) if covered else "None",
        ", ".join(missing) if missing else "None",
        ", ".join(extra) if extra else "None",
    )


def secondary_capability_note(task: TaskFile, entry: ManifestEntry, missing_caps: str) -> str:
    detail_kind = task_detail_kind(task, entry)
    if detail_kind in {"stage-verify", "foundation-verify"}:
        return "None"
    if missing_caps == "None":
        if detail_kind == "core-integration-verify" and entry_page_ids(entry):
            return "消费页面中的其他能力不属于当前 Core task 验收范围；仅检查当前能力是否满足这些页面对该能力的需求"
        return "None"
    if detail_kind == "page-feature":
        return f"{missing_caps}（page-feature task：同页其他能力由其他 task 与 page integration verify 覆盖）"
    if detail_kind == "core-integration-verify":
        return f"{missing_caps}（消费页面中的其他能力不属于当前 Core task 验收范围；不作为当前 Core verify 的阻断项）"
    return f"{missing_caps}（当前 task 缺少 secondary capability docs，验收时必须阻断）"


def copy_permission_note(detail_kind: str) -> str:
    if detail_kind == "page-integration":
        return "是，仅限 Expected New Paths；只允许整页集成 wiring、验收补齐或测试证据，不得新增 control map 之外功能"
    if detail_kind in {"core-integration-verify", "stage-verify", "foundation-verify"}:
        return "原则上不修改产品实现；如需补充证据，仅限 Expected New Paths 中的测试、脚本或开发文档，建议优先使用 verify --task 做只读验收"
    if detail_kind == "integration":
        return "是，仅限 Expected New Paths；只允许既有闭环的集成 wiring、验收补齐或测试证据，不得新增未绑定功能"
    return "是，仅限 Expected New Paths"


def integration_execution_requirement(detail_kind: str) -> str:
    if detail_kind == "page-integration":
        return "- Page integration task 只能做整页 wiring、验收补齐或测试证据；不得新增 control map 之外功能。"
    if detail_kind == "core-integration-verify":
        return "- Core integration verify 以验收当前 Core 能力为主；不得补产品实现，消费页面中的其他能力不属于当前 task 范围。"
    if detail_kind in {"stage-verify", "foundation-verify"}:
        return "- Stage/foundation verify 以阶段验收为主；不得补产品实现，若需证据只补测试、脚本或开发文档。"
    if detail_kind == "integration":
        return "- Integration task 只能做既有闭环的集成 wiring、验收补齐或测试证据；不得新增未绑定功能。"
    return "- Integration task 只能做集成 wiring、验收补齐或阶段证据整理；不得新增未绑定功能。"


def page_feature_audit(
    contract: PageContract, tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]
) -> tuple[list[str], list[str], set[str], set[str], list[str]]:
    feature_labels: list[str] = []
    verify_labels: list[str] = []
    feature_caps: set[str] = set()
    verify_errors: list[str] = []
    expected = set(contract.capabilities)
    for label in contract.prompt_labels:
        task = tasks.get(label)
        entry = manifests.get(label)
        if not task or not entry:
            continue
        pages = entry_page_ids(entry)
        caps = set(entry_capability_ids(entry))
        if contract.page_id not in pages:
            continue
        if task_kind(task, entry) == "integration":
            verify_labels.append(label)
            if expected and caps != expected:
                verify_errors.append(
                    f"{label} should cover {', '.join(sorted(expected))}, got {', '.join(sorted(caps)) or 'None'}"
                )
            if not expected and caps:
                verify_errors.append(f"{label} should be UI-only, got {', '.join(sorted(caps))}")
        else:
            feature_labels.append(label)
            feature_caps.update(caps)
    extra = feature_caps - expected
    return feature_labels, verify_labels, feature_caps, extra, verify_errors


def capability_specs() -> dict[str, Path]:
    specs: dict[str, Path] = {}
    for path in sorted((ROOT / "docs" / "core" / "capability-specs").glob("**/C*.md")):
        match = re.search(r"(C[1-4]-\d+)", path.name)
        if match:
            specs[match.group(1)] = path
    return specs


def capability_task_labels(
    tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]
) -> dict[str, list[str]]:
    labels: dict[str, list[str]] = {}
    for label, entry in manifests.items():
        if label not in tasks:
            continue
        for capability in entry_capability_ids(entry):
            labels.setdefault(capability, []).append(label)
    for capability in labels:
        labels[capability].sort(key=label_sort_key)
    return labels


def required_core_task_tokens(capability: str) -> list[str]:
    if capability.startswith("C1-"):
        return ["contract-api", "implementation", "validation", "integration-verify"]
    return ["contract-api", "implementation", "failure-edge", "validation", "integration-verify"]


def missing_core_task_tokens(
    capability: str, tasks: dict[str, TaskFile], labels: list[str]
) -> list[str]:
    titles = "\n".join(tasks[label].title.lower() for label in labels if label in tasks)
    return [token for token in required_core_task_tokens(capability) if token not in titles]


def core_coverage_stats(
    tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]
) -> dict[str, int]:
    specs = capability_specs()
    labels_by_capability = capability_task_labels(tasks, manifests)
    missing_capability_tasks = [capability for capability in specs if capability not in labels_by_capability]
    bad_c1 = [
        capability
        for capability, labels in labels_by_capability.items()
        if capability.startswith("C1-") and missing_core_task_tokens(capability, tasks, labels)
    ]
    bad_c234 = [
        capability
        for capability, labels in labels_by_capability.items()
        if not capability.startswith("C1-") and missing_core_task_tokens(capability, tasks, labels)
    ]
    core_verify_labels = [
        label
        for label, task in tasks.items()
        if label in manifests and is_core_integration_verify(task, manifests[label])
    ]
    misclassified = [
        label
        for label in core_verify_labels
        if task_detail_kind(tasks[label], manifests[label]) != "core-integration-verify"
    ]
    secondary_blocking = [
        label
        for label in core_verify_labels
        if "阻断" in secondary_capability_note(
            tasks[label],
            manifests[label],
            page_contract_summary(tasks[label], manifests[label])[2],
        )
    ]
    return {
        "capabilities": len(specs),
        "capability_without_task": len(missing_capability_tasks),
        "bad_c1_groups": len(bad_c1),
        "bad_c234_groups": len(bad_c234),
        "core_integration_verify": len(core_verify_labels),
        "core_verify_misclassified": len(misclassified),
        "core_verify_secondary_blocking": len(secondary_blocking),
    }


def validate_core_task_coverage(
    tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]
) -> list[str]:
    errors: list[str] = []
    specs = capability_specs()
    labels_by_capability = capability_task_labels(tasks, manifests)
    for capability in sorted(specs):
        labels = labels_by_capability.get(capability, [])
        if not labels:
            errors.append(f"{rel(specs[capability])}: capability has no prompt task")
            continue
        missing = missing_core_task_tokens(capability, tasks, labels)
        if missing:
            errors.append(f"{capability}: missing Core task types: {', '.join(missing)}")
    for label, task in sorted(tasks.items(), key=lambda item: label_sort_key(item[0])):
        entry = manifests.get(label)
        if not entry or not is_core_integration_verify(task, entry):
            continue
        capabilities = entry_capability_ids(entry)
        if len(capabilities) != 1:
            errors.append(
                f"{label}: Core integration verify must bind exactly one Core capability, got {', '.join(capabilities) or 'None'}"
            )
        if task_detail_kind(task, entry) != "core-integration-verify":
            errors.append(f"{label}: Core integration verify misclassified as {task_detail_kind(task, entry)}")
        missing_caps = page_contract_summary(task, entry)[2]
        if "阻断" in secondary_capability_note(task, entry, missing_caps):
            errors.append(f"{label}: Core integration verify has blocking secondary capability note")
    return errors


def validate_page_contract_coverage(
    tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]
) -> list[str]:
    errors: list[str] = []
    for contract in load_page_contracts().values():
        if not contract.prompt_labels:
            errors.append(
                f"{rel(contract.control_map_path)}:{contract.line_no} {contract.page_id}: missing prompt labels"
            )
            continue
        for label in contract.prompt_labels:
            if label not in tasks:
                errors.append(
                    f"{rel(contract.control_map_path)}:{contract.line_no} {contract.page_id}: unknown prompt label {label}"
                )
                continue
            entry = manifests.get(label)
            if not entry:
                errors.append(
                    f"{rel(contract.control_map_path)}:{contract.line_no} {contract.page_id}: missing manifest for {label}"
                )
                continue
        feature_labels, verify_labels, covered, extra, verify_errors = page_feature_audit(contract, tasks, manifests)
        expected = set(contract.capabilities)
        missing = sorted(expected - covered)
        extra_values = sorted(extra)
        if missing:
            errors.append(
                f"{rel(contract.control_map_path)}:{contract.line_no} {contract.page_id}: prompt coverage missing Core capabilities: {', '.join(missing)}"
            )
        if extra_values:
            errors.append(
                f"{rel(contract.control_map_path)}:{contract.line_no} {contract.page_id}: prompt coverage has extra Core capabilities: {', '.join(extra_values)}"
            )
        if len(expected) > 1 and not verify_labels:
            errors.append(
                f"{rel(contract.control_map_path)}:{contract.line_no} {contract.page_id}: multi-capability page is missing page integration verify"
            )
        if not feature_labels:
            errors.append(
                f"{rel(contract.control_map_path)}:{contract.line_no} {contract.page_id}: missing page-feature task"
            )
        for verify_error in verify_errors:
            errors.append(f"{rel(contract.control_map_path)}:{contract.line_no} {contract.page_id}: {verify_error}")
    return errors


def validate_graph(tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]) -> list[str]:
    errors: list[str] = []
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(label: str, trail: list[str]) -> None:
        if label in visited:
            return
        if label in visiting:
            errors.append("dependency cycle: " + " -> ".join([*trail, label]))
            return
        visiting.add(label)
        for dep in manifests[label].depends:
            if dep not in tasks:
                errors.append(f"{label}: unknown dependency {dep}")
                continue
            visit(dep, [*trail, label])
        visiting.remove(label)
        visited.add(label)

    for label in sorted(tasks, key=label_sort_key):
        if label in manifests:
            visit(label, [])
    return errors


def markdown_link_audit_paths() -> list[Path]:
    paths: list[Path] = [
        PROMPTS_ROOT / "README.md",
        SHARED_ROOT / "README.md",
        AUDIT_RULES,
        TASK_SLICING_RULES,
        ENGINEERING_QUALITY_RULES,
        DEPENDENCY_GRAPH,
        CODING_STANDARDS,
        MANIFEST_ROOT / "README.md",
    ]
    paths.extend(sorted(MANIFEST_ROOT.glob("phase-*.md")))
    paths.extend(sorted((ROOT / "docs" / "ux" / "page-specs").glob("*.md")))
    paths.extend(sorted((ROOT / "docs" / "core" / "capability-specs").glob("*.md")))
    paths.extend(sorted((ROOT / "docs" / "architecture").glob("*control-map.md")))

    result: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        if path not in seen:
            result.append(path)
            seen.add(path)
    return result


def markdown_link_target(raw_target: str) -> str | None:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1].strip()
    if not target or target.startswith("#") or EXTERNAL_LINK_RE.match(target):
        return None
    if " " in target:
        target = target.split()[0].strip()
    target = target.split("#", 1)[0].strip()
    return target or None


def validate_markdown_links() -> list[str]:
    errors: list[str] = []
    for path in markdown_link_audit_paths():
        if not path.exists():
            errors.append(f"missing markdown audit path: {rel(path)}")
            continue
        in_fence = False
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.strip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for raw_target in MARKDOWN_LINK_RE.findall(line):
                target = markdown_link_target(raw_target)
                if not target:
                    continue
                resolved = (path.parent / target).resolve()
                try:
                    resolved.relative_to(ROOT)
                except ValueError:
                    errors.append(f"{rel(path)}:{line_no} markdown link escapes repo: {raw_target}")
                    continue
                if not resolved.exists():
                    errors.append(f"{rel(path)}:{line_no} broken markdown link: {raw_target}")
    return errors


def collect_doctor_findings() -> tuple[list[str], list[str], dict[str, TaskFile], dict[str, ManifestEntry]]:
    errors: list[str] = []
    warnings: list[str] = []

    try:
        tasks = scan_task_files()
    except ValueError as exc:
        return [str(exc)], [], {}, {}

    try:
        manifests = load_manifests()
    except ValueError as exc:
        return [str(exc)], [], tasks, {}

    if not AUDIT_RULES.exists():
        errors.append(f"missing audit rules: {rel(AUDIT_RULES)}")
    if not TASK_SLICING_RULES.exists():
        errors.append(f"missing task slicing rules: {rel(TASK_SLICING_RULES)}")
    if not ENGINEERING_QUALITY_RULES.exists():
        errors.append(f"missing engineering quality rules: {rel(ENGINEERING_QUALITY_RULES)}")
    if not DEPENDENCY_GRAPH.exists():
        errors.append(f"missing dependency graph: {rel(DEPENDENCY_GRAPH)}")
    if not CODING_STANDARDS.exists():
        errors.append(f"missing coding standards: {rel(CODING_STANDARDS)}")

    for label, task in sorted(tasks.items(), key=lambda item: label_sort_key(item[0])):
        entry = manifests.get(label)
        if not entry:
            errors.append(f"{label}: missing manifest entry")
            continue
        if entry.source_task and entry.source_task != rel(task.path):
            errors.append(f"{label}: source task mismatch: {entry.source_task} != {rel(task.path)}")
        for doc in entry.exact_docs:
            if not (ROOT / doc).exists():
                errors.append(f"{label}: missing Exact Docs path: {doc}")
        for value in entry.expected_new_paths:
            if not is_allowed_new_path(value):
                errors.append(f"{label}: Expected New Paths outside allowed roots: {value}")
        if looks_high_risk(entry) and entry.risk not in {"High", "Mission-Critical"}:
            errors.append(f"{label}: high-risk-looking task is not marked High/Mission-Critical")
        for section in [
            "Exact Docs",
            "Existing Code",
            "Expected New Paths",
            "Forbidden Touches",
            "Risk Level",
            "Validation",
        ]:
            if section not in entry.sections:
                errors.append(f"{label}: missing manifest section {section}")
        errors.extend(validate_granularity(task, entry))

    for label in sorted(set(manifests) - set(tasks), key=label_sort_key):
        warnings.append(f"{label}: manifest entry has no task file")

    errors.extend(validate_graph(tasks, manifests))
    errors.extend(validate_page_contract_coverage(tasks, manifests))
    errors.extend(validate_core_task_coverage(tasks, manifests))
    errors.extend(validate_markdown_links())
    return errors, warnings, tasks, manifests


def ordered_labels(tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]) -> list[str]:
    result: list[str] = []
    temporary: set[str] = set()
    permanent: set[str] = set()

    def visit(label: str) -> None:
        if label in permanent or label not in tasks:
            return
        if label in temporary:
            raise ValueError(f"dependency cycle at {label}")
        temporary.add(label)
        for dep in manifests[label].depends:
            visit(dep)
        temporary.remove(label)
        permanent.add(label)
        result.append(label)

    for label in sorted(tasks, key=label_sort_key):
        visit(label)
    return result


def filter_labels(labels: list[str], tasks: dict[str, TaskFile], phase: str | None) -> list[str]:
    if not phase:
        return labels
    normalized = phase if phase.startswith("phase-") else f"phase-{phase}"
    return [label for label in labels if tasks[label].phase == normalized]


def load_progress() -> dict[str, object]:
    if not PROGRESS_PATH.exists():
        return {"version": 1, "tasks": {}}
    return json.loads(PROGRESS_PATH.read_text(encoding="utf-8"))


def save_progress(progress: dict[str, object]) -> None:
    PROGRESS_PATH.write_text(
        json.dumps(progress, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def task_status(progress: dict[str, object], label: str) -> str:
    tasks = progress.get("tasks", {})
    if not isinstance(tasks, dict):
        return "pending"
    value = tasks.get(label)
    if not isinstance(value, dict):
        return "pending"
    status = value.get("status")
    return status if isinstance(status, str) else "pending"


def ready_for_next(label: str, manifests: dict[str, ManifestEntry], progress: dict[str, object]) -> bool:
    return all(task_status(progress, dep) == "completed" for dep in manifests[label].depends)


def markdown_section(text: str, heading: str) -> str:
    pattern = re.compile(rf"^##\s+{re.escape(heading)}\s*$", re.M)
    match = pattern.search(text)
    if not match:
        return "未在 task 文件中找到该章节；验收时必须回到 task 正文自行定位。"
    next_match = re.search(r"^##\s+", text[match.end() :], re.M)
    end = match.end() + next_match.start() if next_match else len(text)
    return text[match.end() : end].strip() or "该章节为空。"


def print_copy_prompt(task: TaskFile, entry: ManifestEntry) -> None:
    task_text = task.path.read_text(encoding="utf-8")
    checklist = markdown_section(task_text, "核对清单")
    completion = markdown_section(task_text, "完成标准")
    validation = markdown_section(task_text, "验证")
    deps = ", ".join(entry.depends) if entry.depends else "None"
    ux_binding, capability_binding = binding_summary(entry)
    expected_caps, covered_caps, missing_caps, extra_caps = page_contract_summary(task, entry)
    secondary_note = secondary_capability_note(task, entry, missing_caps)
    kind = task_kind(task, entry)
    detail_kind = task_detail_kind(task, entry)

    print(f"# Copy-ready Prompt: {task.label}")
    print()
    print("你现在进入 AreaMatrix 的单任务执行模式。")
    print()
    print("## 工作目录")
    print()
    print(f"`{ROOT}`")
    print()
    print("## 本次执行对象")
    print()
    print("- 类型：单任务执行")
    print(f"- 任务类型：`{kind}`")
    print(f"- 任务细分：`{detail_kind}`")
    print(f"- Phase：`{task.phase}`")
    print(f"- Task 标识：`{task.label}`")
    print(f"- Task 文件：`{task.path}`")
    print(f"- 共享规则：`{AUDIT_RULES}`")
    print(f"- 任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"- 工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"- 编码规范：`{CODING_STANDARDS}`")
    print(f"- 依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"- Phase Manifest：`{entry.manifest_path}`")
    print(f"- Manifest 章节：`## {entry.label}`")
    print(f"- 依赖任务：`{deps}`")
    print(f"- 风险等级：`{entry.risk}`")
    print(f"- 绑定 UX 页面：`{ux_binding}`")
    print(f"- 绑定 Core 能力：`{capability_binding}`")
    print(f"- Control map 期望 Core 能力：`{expected_caps}`")
    print(f"- 当前 task 覆盖 Core 能力：`{covered_caps}`")
    print(f"- Secondary capability 状态：`{secondary_note}`")
    print(f"- Control map 之外能力：`{extra_caps}`")
    print(f"- 是否允许修改文件：`{copy_permission_note(detail_kind)}`")
    print(
        "- Manifest 计数："
        f"文档 `{len(entry.exact_docs)}` 个，"
        f"现有代码 `{len(entry.existing_code)}` 项，"
        f"预期新增路径 `{len(entry.expected_new_paths)}` 项，"
        f"禁止触碰路径 `{len(entry.forbidden_touches)}` 项，"
        f"验证命令 `{len(entry.validation)}` 个"
    )
    print()
    print("## 开始前必须按顺序完成")
    print()
    print(f"1. 读取 task 文件：`{task.path}`")
    print(f"2. 读取共享规则：`{AUDIT_RULES}`")
    print(f"3. 读取任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"4. 读取工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"5. 读取编码规范：`{CODING_STANDARDS}`")
    print(f"6. 读取依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"7. 读取 phase manifest：`{entry.manifest_path}`")
    print(f"8. 在 manifest 中定位章节：`## {entry.label}`")
    print("9. 逐个读取该章节下的 `Exact Docs`。")
    print("10. 逐个读取当前存在的 `Existing Code`。")
    print("11. 确认改动只会落在 `Expected New Paths`。")
    print("12. 确认不会触碰 `Forbidden Touches`。")
    print("13. 若风险等级为 High 或 Mission-Critical，先给出风险、验证和回滚思路；若自动执行器已注入静默授权，则记录后直接继续。")
    print()
    print("## 本次任务标题")
    print()
    print(f"- {task.title}")
    print()
    print("## 必须实现的核对清单")
    print()
    print(checklist)
    print()
    print("## 必须满足的完成标准")
    print()
    print(completion)
    print()
    print("## 任务要求的验证")
    print()
    print(validation)
    print()
    print("## 共享规则")
    print()
    print(AUDIT_RULES.read_text(encoding="utf-8").strip())
    print()
    print("## 任务切片规则")
    print()
    print(TASK_SLICING_RULES.read_text(encoding="utf-8").strip())
    print()
    print("## 工程质量规则")
    print()
    print(ENGINEERING_QUALITY_RULES.read_text(encoding="utf-8").strip())
    print()
    print("## 任务正文")
    print()
    print(task_text.strip())
    print()
    print("## Manifest")
    print()
    print(entry.raw)
    print()
    print("## 执行要求")
    print()
    print("- 先逐个读取 `Exact Docs`。")
    print("- Atomic task 只能实现本任务绑定的单页或单能力；不得顺手完成相邻页面或能力。")
    print("- 页面功能 task 只能处理一个 `S* + C*` 功能点；页面 integration task 才检查整页多能力闭环。")
    print(integration_execution_requirement(detail_kind))
    print("- 对已存在 capability specs 的任务，必须交叉检查 UX 页面、Core 能力规格和对应 control map。")
    print("- 再读取存在的 `Existing Code`。")
    print("- 只在 `Expected New Paths` 内新增或修改。")
    print("- 不触碰 `Forbidden Touches`，除非重新确认。")
    print("- 禁止提前实现后续任务的功能，尤其是工程骨架任务不得塞入业务逻辑。")
    print("- 必须按工程质量规则和编码规范实现；不得交付一次性脚本化代码、占位逻辑或硬编码通过态。")
    print("- 代码注释只解释 WHY、风险边界或权衡；新增 public Rust API 必须补 rustdoc。")
    print("- 必须显式处理错误、边界条件和失败路径；不得静默吞错。")
    print("- 完成后运行 `Validation` 中列出的检查，并汇报无法运行的项。")
    print()
    print("## 完成后必须输出")
    print()
    print("一、执行结论")
    print()
    print("- 已完成")
    print("  或")
    print("- 未完成")
    print()
    print("二、执行范围")
    print()
    print("- 单任务")
    print("- 修改文件清单")
    print()
    print("三、完成情况")
    print()
    print("- 核对清单逐项结果")
    print("- 完成标准逐项结果")
    print("- 是否触碰 Forbidden Touches")
    print()
    print("四、工程质量")
    print()
    print("- 代码结构与逻辑是否清晰")
    print("- 注释 / rustdoc / 文档同步情况")
    print("- 错误处理与边界处理情况")
    print("- 是否存在占位、硬编码、mock-only 或一次性实现")
    print()
    print("五、验证情况")
    print()
    print("- 跑了哪些验证")
    print("- 哪些通过")
    print("- 哪些失败")
    print("- 哪些无法运行及原因")
    print()
    print("六、风险与后续")
    print()
    print("- 剩余风险")
    print("- 建议下一个任务")


def print_verify_prompt(task: TaskFile, entry: ManifestEntry) -> None:
    task_text = task.path.read_text(encoding="utf-8")
    checklist = markdown_section(task_text, "核对清单")
    completion = markdown_section(task_text, "完成标准")
    validation = markdown_section(task_text, "验证")
    deps = ", ".join(entry.depends) if entry.depends else "None"
    ux_binding, capability_binding = binding_summary(entry)
    expected_caps, covered_caps, missing_caps, extra_caps = page_contract_summary(task, entry)
    secondary_note = secondary_capability_note(task, entry, missing_caps)
    kind = task_kind(task, entry)
    detail_kind = task_detail_kind(task, entry)

    print(f"# Verify-ready Prompt: {task.label}")
    print()
    print("你现在进入 AreaMatrix 的单任务验收模式。")
    print()
    print("## 工作目录")
    print()
    print(f"`{ROOT}`")
    print()
    print("## 本次验收对象")
    print()
    print("- 类型：单任务验收")
    print(f"- 任务类型：`{kind}`")
    print(f"- 任务细分：`{detail_kind}`")
    print(f"- Phase：`{task.phase}`")
    print(f"- Task 标识：`{task.label}`")
    print(f"- Task 文件：`{task.path}`")
    print(f"- 共享规则：`{AUDIT_RULES}`")
    print(f"- 任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"- 工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"- 编码规范：`{CODING_STANDARDS}`")
    print(f"- 依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"- Phase Manifest：`{entry.manifest_path}`")
    print(f"- Manifest 章节：`## {entry.label}`")
    print(f"- 依赖任务：`{deps}`")
    print(f"- 风险等级：`{entry.risk}`")
    print(f"- 绑定 UX 页面：`{ux_binding}`")
    print(f"- 绑定 Core 能力：`{capability_binding}`")
    print(f"- Control map 期望 Core 能力：`{expected_caps}`")
    print(f"- 当前 task 覆盖 Core 能力：`{covered_caps}`")
    print(f"- Secondary capability 状态：`{secondary_note}`")
    print(f"- Control map 之外能力：`{extra_caps}`")
    print("- 是否允许修改文件：`否，本模式只读验收`")
    print(
        "- Manifest 计数："
        f"文档 `{len(entry.exact_docs)}` 个，"
        f"现有代码 `{len(entry.existing_code)}` 项，"
        f"预期新增路径 `{len(entry.expected_new_paths)}` 项，"
        f"禁止触碰路径 `{len(entry.forbidden_touches)}` 项，"
        f"验证命令 `{len(entry.validation)}` 个"
    )
    print()
    print("你的任务不是继续实现，而是严格验收这个 task 当前是否已经真正达到完成标准。")
    print("这次是验收，不是修复：禁止修改文件，禁止边验边改。")
    print()
    print("## 开始前必须按顺序完成")
    print()
    print(f"1. 读取 task 文件：`{task.path}`")
    print(f"2. 读取共享规则：`{AUDIT_RULES}`")
    print(f"3. 读取任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"4. 读取工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"5. 读取编码规范：`{CODING_STANDARDS}`")
    print(f"6. 读取依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"7. 读取 phase manifest：`{entry.manifest_path}`")
    print(f"8. 在 manifest 中定位章节：`## {entry.label}`")
    print("9. 逐个读取该章节下的 `Exact Docs`。")
    print("10. 逐个读取该章节下当前存在的 `Existing Code`。")
    print("11. 检查 `Expected New Paths` 是否已按任务完成标准落地；缺失即记录证据。")
    print("12. 检查 `Forbidden Touches` 是否被违规修改。")
    print("13. 基于 task 文件中的核对清单、完成标准和工程质量规则逐项验收。")
    print()
    print("## 本次任务标题")
    print()
    print(f"- {task.title}")
    print()
    print("## 必须逐项验收的核对清单")
    print()
    print(checklist)
    print()
    print("## 必须满足的完成标准")
    print()
    print(completion)
    print()
    print("## 任务要求的验证")
    print()
    print(validation)
    print()
    print("## Manifest")
    print()
    print(entry.raw)
    print()
    print("## 共享规则")
    print()
    print(AUDIT_RULES.read_text(encoding="utf-8").strip())
    print()
    print("## 任务切片规则")
    print()
    print(TASK_SLICING_RULES.read_text(encoding="utf-8").strip())
    print()
    print("## 工程质量规则")
    print()
    print(ENGINEERING_QUALITY_RULES.read_text(encoding="utf-8").strip())
    print()
    print("## 验收原则")
    print()
    print("- 无法证明通过，就判定不通过。")
    print("- 不接受“看起来差不多”。")
    print("- 不接受只看 diff；必须回到 task、manifest、实际文件三者交叉验收。")
    print("- 文档仍然是 SSOT。")
    print("- 不接受 UI 占位、接口空壳、链路未打通的伪完成。")
    print("- `Existing Code` 为 None 不等于无需验收；应检查 `Expected New Paths` 是否已被真实实现。")
    print("- 已存在 capability specs 的任务必须交叉验收 UX 页面、Core 能力规格和对应 control map；真实闭环仍用 mock 时判定不通过。")
    print("- page-feature task 只验收一个 `S* + C*` 功能点；page integration task 必须覆盖 control map 中该页面声明的全部 Core 能力。")
    print("- 多能力页面缺少 page integration verify 或缺任何 page-feature task 时，默认不通过。")
    print("- 任何高风险边界缺少测试或证据时，默认不通过。")
    print("- 代码只满足单次运行、缺少可维护结构、错误处理、注释或必要测试时，默认不通过。")
    print("- 严重违反 `docs/development/coding-standards.md` 的实现不能判定为完成。")
    print("- 可以运行只读验证或测试命令；不得运行会重写 repo-tracked 文件的 formatter、codegen 或修复命令。")
    print()
    print("## 你必须检查")
    print()
    print("1. 是否真的按 manifest 做了逐文件覆盖，而不是只做了局部。")
    print("2. task 的核对清单是否逐项满足。")
    print("3. task 的完成标准是否逐项满足。")
    print("4. 是否仍存在文档有而代码无、代码有而文档无、链路未打通、验证缺失等问题。")
    print("5. 工程质量是否达到长期维护标准，而不是单次运行实例。")
    print("6. 当前仓库状态是否足以把该 task 判定为完成。")
    print()
    print("## 最后必须按这个格式输出")
    print()
    print("一、验收结论")
    print()
    print("- 通过")
    print("  或")
    print("- 不通过")
    print()
    print("二、验收范围")
    print()
    print("- 单任务")
    print("- 对应文件路径")
    print()
    print("三、完成度摘要")
    print()
    print("- 已覆盖项数")
    print("- 未覆盖项数")
    print("- 通过项数")
    print("- 不通过项数")
    print("- 阻塞项数")
    print()
    print("四、逐项验收结果")
    print()
    print("- 项目")
    print("- 结果：通过 / 不通过")
    print("- 证据")
    print("- 涉及文件")
    print()
    print("五、工程质量验收")
    print()
    print("- 代码结构与逻辑：通过 / 不通过，证据")
    print("- 注释 / rustdoc / 文档同步：通过 / 不通过，证据")
    print("- 错误处理与边界处理：通过 / 不通过，证据")
    print("- 测试与验证覆盖：通过 / 不通过，证据")
    print("- 占位、硬编码、mock-only、一次性实现检查：通过 / 不通过，证据")
    print()
    print("六、阻塞项")
    print()
    print("- 若有问题，逐条列出 P0/P1 标题、说明、绝对路径、行号、为什么导致不通过")
    print("- 如果没有，明确写“未发现阻塞项”")
    print()
    print("七、验证情况")
    print()
    print("- 跑了哪些验证")
    print("- 哪些通过")
    print("- 哪些失败")
    print("- 哪些缺失")
    print()
    print("八、最终判定说明")
    print()
    print("- 本次执行已达到验收标准。")
    print("  或")
    print("- 本次执行尚未达到验收标准，不能视为完成。")
    print()
    print("## 禁止事项")
    print()
    print("- 禁止边验收边修。")
    print("- 禁止因为已经做了很多就放宽标准。")
    print("- 禁止把“可后续优化”包装成通过。")
    print("- 禁止省略证据。")
    print("- 禁止给模糊结论。")


def capture_task_prompt(task: TaskFile, entry: ManifestEntry, mode: str) -> str:
    buffer = io.StringIO()
    with redirect_stdout(buffer):
        if mode == "copy":
            print_copy_prompt(task, entry)
        elif mode == "verify":
            print_verify_prompt(task, entry)
        else:
            raise ValueError(f"unknown prompt mode: {mode}")
    text = buffer.getvalue()
    return text if text.endswith("\n") else text + "\n"


def prompt_export_filename(label: str) -> str:
    return label.replace("/", "-") + ".md"


def clear_phase_export_dir(root: Path, phase: str) -> Path:
    phase_dir = root / phase
    phase_dir.mkdir(parents=True, exist_ok=True)
    for prompt_path in phase_dir.glob("*.md"):
        prompt_path.unlink()
    return phase_dir


def print_phase_verify_prompt(phase: str, tasks: dict[str, TaskFile], manifests: dict[str, ManifestEntry]) -> int:
    normalized = phase if phase.startswith("phase-") else f"phase-{phase}"
    labels = filter_labels(ordered_labels(tasks, manifests), tasks, normalized)
    if not labels:
        print(f"unknown or empty phase: {phase}", file=sys.stderr)
        return 1

    print(f"# Phase Verify-ready Prompt: {normalized}")
    print()
    print("你现在进入 AreaMatrix 的阶段验收模式。")
    print()
    print("## 工作目录")
    print()
    print(f"`{ROOT}`")
    print()
    print("## 本次验收对象")
    print()
    print("- 类型：阶段验收")
    print(f"- Phase：`{normalized}`")
    print(f"- 任务数：`{len(labels)}`")
    print(f"- 共享规则：`{AUDIT_RULES}`")
    print(f"- 任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"- 工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"- 编码规范：`{CODING_STANDARDS}`")
    print(f"- 依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"- Phase Manifest：`{MANIFEST_ROOT / (normalized + '.md')}`")
    print()
    print("你的任务不是继续实现，而是严格验收该阶段所有 task 是否已经真正达到完成标准。")
    print("这次是验收，不是修复：禁止修改文件，禁止边验边改。")
    print()
    print("## 开始前必须按顺序完成")
    print()
    print(f"1. 读取共享规则：`{AUDIT_RULES}`")
    print(f"2. 读取任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"3. 读取工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"4. 读取编码规范：`{CODING_STANDARDS}`")
    print(f"5. 读取依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"6. 读取 phase manifest：`{MANIFEST_ROOT / (normalized + '.md')}`")
    print("7. 按下方顺序逐个验收 task。")
    print("8. 每个 task 都必须回到 task 文件、manifest 章节、实际文件三者交叉验收。")
    print("9. 已存在 capability specs 的 task 必须额外交叉检查 UX 页面、Core 能力规格和对应 control map。")
    print("10. 任一 task 不通过，则阶段不通过。")
    print()
    print("## 阶段任务清单")
    print()
    for label in labels:
        task = tasks[label]
        entry = manifests[label]
        deps = ", ".join(entry.depends) if entry.depends else "None"
        ux_binding, capability_binding = binding_summary(entry)
        print(
            f"- `{label}` | {task.title} | type: `{task_kind(task, entry)}` | "
            f"risk: `{entry.risk}` | depends: `{deps}`"
        )
        print(f"  - task: `{task.path}`")
        print(f"  - manifest: `{entry.manifest_path}` -> `## {entry.label}`")
        print(f"  - UX: `{ux_binding}` | Core: `{capability_binding}`")
    print()
    print("## 共享验收规则")
    print()
    print(AUDIT_RULES.read_text(encoding="utf-8").strip())
    print()
    print("## 工程质量规则")
    print()
    print(ENGINEERING_QUALITY_RULES.read_text(encoding="utf-8").strip())
    print()
    print("## 单任务验收要求")
    print()
    print("对每个 task，必须检查：")
    print()
    print("1. `Exact Docs` 是否逐个阅读并作为 SSOT。")
    print("2. 当前存在的 `Existing Code` 是否逐个阅读。")
    print("3. `Expected New Paths` 是否已真实落地。")
    print("4. `Forbidden Touches` 是否被违规触碰。")
    print("5. task 核对清单是否逐项满足。")
    print("6. task 完成标准是否逐项满足。")
    print("7. `Validation` 是否运行，失败或缺失是否足以阻断。")
    print("8. task 是否同时满足 UX 页面、Core 能力规格和对应 control map。")
    print("9. task 是否满足工程质量规则和编码规范；一次性实现、占位、硬编码通过态必须阻断。")
    print()
    print("## 阶段验收原则")
    print()
    print("- 无法证明通过，就判定不通过。")
    print("- 不接受只看 diff。")
    print("- 不接受占位、空壳、链路未打通。")
    print("- 真实闭环仍使用 mock、fixture 或硬编码状态时，必须判定不通过。")
    print("- 任一 task 的工程质量不达标，阶段不通过。")
    print("- 任一 Mission-Critical task 缺少验证证据，阶段默认不通过。")
    print("- 任一 task 不通过，阶段不通过。")
    print()
    print("## 最后必须按这个格式输出")
    print()
    print("一、阶段验收结论")
    print()
    print("- 通过")
    print("  或")
    print("- 不通过")
    print()
    print("二、验收范围")
    print()
    print("- Phase")
    print("- 任务数量")
    print("- 对应 task 文件路径")
    print()
    print("三、阶段完成度摘要")
    print()
    print("- 通过任务数")
    print("- 不通过任务数")
    print("- 阻塞任务数")
    print("- 缺失验证任务数")
    print()
    print("四、逐任务验收结果")
    print()
    print("- Task")
    print("- 结果：通过 / 不通过")
    print("- 证据")
    print("- 阻塞项")
    print()
    print("五、工程质量汇总")
    print()
    print("- 不达标任务")
    print("- 主要质量问题")
    print("- 涉及文件")
    print("- 为什么阻断阶段通过")
    print()
    print("六、阶段阻塞项")
    print()
    print("- P0/P1 标题")
    print("- 说明")
    print("- 绝对路径与行号")
    print("- 为什么导致阶段不通过")
    print()
    print("七、验证情况")
    print()
    print("- 跑了哪些验证")
    print("- 哪些通过")
    print("- 哪些失败")
    print("- 哪些缺失")
    print()
    print("八、最终判定说明")
    print()
    print("- 本阶段已达到验收标准。")
    print("  或")
    print("- 本阶段尚未达到验收标准，不能视为完成。")
    return 0


def command_export(args: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        print("export: doctor failed")
        for error in errors:
            print(f"- ERROR: {error}")
        for warning in warnings:
            print(f"- WARN: {warning}")
        return 1

    labels = ordered_labels(tasks, manifests)
    if not args.all:
        labels = filter_labels(labels, tasks, args.phase)
    if not labels:
        target = "all phases" if args.all else args.phase
        print(f"export: no tasks found for {target}", file=sys.stderr)
        return 1

    phases = sorted({tasks[label].phase for label in labels})
    phase_dirs: dict[tuple[str, str], Path] = {}
    for phase in phases:
        phase_dirs[("copy", phase)] = clear_phase_export_dir(COPY_READY_ROOT, phase)
        phase_dirs[("verify", phase)] = clear_phase_export_dir(VERIFY_READY_ROOT, phase)

    copy_count = 0
    verify_count = 0
    for label in labels:
        task = tasks[label]
        entry = manifests[label]
        filename = prompt_export_filename(label)

        copy_path = phase_dirs[("copy", task.phase)] / filename
        copy_path.write_text(capture_task_prompt(task, entry, "copy"), encoding="utf-8")
        copy_count += 1

        verify_path = phase_dirs[("verify", task.phase)] / filename
        verify_path.write_text(capture_task_prompt(task, entry, "verify"), encoding="utf-8")
        verify_count += 1

    print("export: OK")
    print(f"- phases: {', '.join(phases)}")
    print(f"- copy-ready: {copy_count}")
    print(f"- verify-ready: {verify_count}")
    print(f"- copy root: {rel(COPY_READY_ROOT)}")
    print(f"- verify root: {rel(VERIFY_READY_ROOT)}")
    if warnings:
        print("- warnings:")
        for warning in warnings:
            print(f"  - {warning}")
    return 0


def command_doctor(_: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        print("doctor: FAILED")
        for error in errors:
            print(f"- ERROR: {error}")
        for warning in warnings:
            print(f"- WARN: {warning}")
        return 1

    high_risk = [entry for entry in manifests.values() if entry.risk in {"High", "Mission-Critical"}]
    print("doctor: OK")
    print(f"- tasks: {len(tasks)}")
    print(f"- manifests: {len(manifests)}")
    print(f"- high risk tasks: {len(high_risk)}")
    if warnings:
        for warning in warnings:
            print(f"- WARN: {warning}")
    return 0


def command_plan(args: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        print("plan: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    labels = ordered_labels(tasks, manifests)
    if not args.all:
        labels = filter_labels(labels, tasks, args.phase)
    for label in labels:
        task = tasks[label]
        entry = manifests[label]
        deps = ", ".join(entry.depends) if entry.depends else "None"
        print(f"{label} [{task.phase}] {task.title}")
        print(f"  risk: {entry.risk}; depends: {deps}")
    if warnings:
        print("\nWarnings:")
        for warning in warnings:
            print(f"- {warning}")
    return 0


def command_next(_: argparse.Namespace) -> int:
    errors, _, tasks, manifests = collect_doctor_findings()
    if errors:
        print("next: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    progress = load_progress()
    for label in ordered_labels(tasks, manifests):
        status = task_status(progress, label)
        if status == "completed":
            continue
        if ready_for_next(label, manifests, progress):
            task = tasks[label]
            entry = manifests[label]
            print(f"{label} [{task.phase}] {task.title}")
            print(f"risk: {entry.risk}")
            print(f"status: {status}")
            print(f"render: python3 tasks/prompts/_shared/prompt_pipeline.py render --task {label}")
            print(f"verify: python3 tasks/prompts/_shared/prompt_pipeline.py verify --task {label}")
            return 0
    print("No ready pending task.")
    return 0


def command_render(args: argparse.Namespace) -> int:
    errors, _, tasks, manifests = collect_doctor_findings()
    if errors:
        print("render: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    label = args.task
    if label not in tasks:
        print(f"unknown task: {label}", file=sys.stderr)
        return 1
    task = tasks[label]
    entry = manifests[label]
    if args.mode == "verify":
        print_verify_prompt(task, entry)
    else:
        print_copy_prompt(task, entry)
    return 0


def command_verify(args: argparse.Namespace) -> int:
    errors, _, tasks, manifests = collect_doctor_findings()
    if errors:
        print("verify: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    if args.phase:
        return print_phase_verify_prompt(args.phase, tasks, manifests)
    args.mode = "verify"
    return command_render(args)


def command_mark(args: argparse.Namespace) -> int:
    errors, _, tasks, manifests = collect_doctor_findings()
    if errors:
        print("mark: doctor failed; run doctor for details", file=sys.stderr)
        return 1
    if args.task not in tasks:
        print(f"unknown task: {args.task}", file=sys.stderr)
        return 1
    if args.status == "completed":
        missing = [dep for dep in manifests[args.task].depends if task_status(load_progress(), dep) != "completed"]
        if missing and not args.force:
            print(f"cannot mark completed; dependencies are not completed: {', '.join(missing)}", file=sys.stderr)
            print("use --force only if this is intentional", file=sys.stderr)
            return 1
    progress = load_progress()
    task_map = progress.setdefault("tasks", {})
    if not isinstance(task_map, dict):
        print("invalid progress file: tasks must be an object", file=sys.stderr)
        return 1
    task_map[args.task] = {
        "status": args.status,
        "note": args.note or "",
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    save_progress(progress)
    print(f"marked {args.task} as {args.status}")
    return 0


def command_status(_: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        print("status: doctor failed")
        for error in errors:
            print(f"- ERROR: {error}")
        return 1
    by_phase: dict[str, int] = {}
    by_risk: dict[str, int] = {}
    progress = load_progress()
    by_status: dict[str, int] = {}
    for label, task in tasks.items():
        by_phase[task.phase] = by_phase.get(task.phase, 0) + 1
        risk = manifests[label].risk
        by_risk[risk] = by_risk.get(risk, 0) + 1
        status = task_status(progress, label)
        by_status[status] = by_status.get(status, 0) + 1
    print("Prompt library status")
    print(f"- tasks: {len(tasks)}")
    print("- phases:")
    for phase in sorted(by_phase):
        print(f"  - {phase}: {by_phase[phase]}")
    print("- risks:")
    for risk in ["Low", "Medium", "High", "Mission-Critical", "Unspecified"]:
        if risk in by_risk:
            print(f"  - {risk}: {by_risk[risk]}")
    print("- progress:")
    for status in ["pending", "in_progress", "blocked", "failed", "completed"]:
        if status in by_status:
            print(f"  - {status}: {by_status[status]}")
    next_label = "None"
    for label in ordered_labels(tasks, manifests):
        if task_status(progress, label) != "completed" and ready_for_next(label, manifests, progress):
            next_label = label
            break
    print(f"- first task: {next_label}")
    print(f"- progress file: {rel(PROGRESS_PATH) if PROGRESS_PATH.exists() else 'not created'}")
    if warnings:
        print("- warnings:")
        for warning in warnings:
            print(f"  - {warning}")
    return 0


def command_audit(args: argparse.Namespace) -> int:
    errors, warnings, tasks, manifests = collect_doctor_findings()
    if errors:
        print("audit: doctor failed")
        for error in errors:
            print(f"- ERROR: {error}")
        return 1
    if not args.pages:
        args.pages = True
    if args.pages:
        print("Page Prompt Coverage Audit")
        print("| Page | Feature Tasks | Page Verify | Expected Core | Feature Covered | Missing | Extra | Status |")
        print("|---|---|---|---|---|---|---|---|")
        for contract in load_page_contracts().values():
            feature_labels, verify_labels, covered, extra, verify_errors = page_feature_audit(
                contract, tasks, manifests
            )
            expected = set(contract.capabilities)
            missing = sorted(expected - covered)
            extra_values = sorted(extra)
            needs_verify = len(expected) > 1
            status = "OK" if not missing and not extra_values and not verify_errors and (not needs_verify or verify_labels) else "FAILED"
            print(
                "| "
                + " | ".join(
                    [
                        contract.page_id,
                        ", ".join(f"`{label}`" for label in feature_labels) or "None",
                        ", ".join(f"`{label}`" for label in verify_labels) or ("Not required" if not needs_verify else "Missing"),
                        ", ".join(contract.capabilities) or "None",
                        ", ".join(sorted(covered)) or "None",
                        ", ".join(missing) or "None",
                        ", ".join(extra_values) or "None",
                        status,
                    ]
                )
                + " |"
            )
        print()
    stats = core_coverage_stats(tasks, manifests)
    print("Core Prompt Coverage Audit")
    print("| Metric | Count |")
    print("|---|---:|")
    print(f"| capabilities | {stats['capabilities']} |")
    print(f"| capability_without_task | {stats['capability_without_task']} |")
    print(f"| bad_c1_groups | {stats['bad_c1_groups']} |")
    print(f"| bad_c2_c3_c4_groups | {stats['bad_c234_groups']} |")
    print(f"| core_integration_verify | {stats['core_integration_verify']} |")
    print(f"| core_verify_misclassified | {stats['core_verify_misclassified']} |")
    print(f"| core_verify_secondary_blocking | {stats['core_verify_secondary_blocking']} |")
    if warnings:
        print("\nWarnings:")
        for warning in warnings:
            print(f"- {warning}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manual prompt runner for AreaMatrix.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("doctor", help="Validate prompt library health.")
    subparsers.add_parser("next", help="Print the next dependency-ready task.")

    plan_parser = subparsers.add_parser("plan", help="Print execution plan.")
    plan_parser.add_argument("--phase", help="Filter to a phase, for example phase-0 or 0.")
    plan_parser.add_argument("--all", action="store_true", help="Print all phases.")

    render_parser = subparsers.add_parser("render", help="Render a copy-ready or verify-ready prompt.")
    render_parser.add_argument("--task", required=True, help="Task label, for example 0-1/task-01.")
    render_parser.add_argument(
        "--mode",
        choices=["copy", "verify"],
        default="copy",
        help="Prompt mode. copy executes work; verify audits completed work without edits.",
    )

    verify_parser = subparsers.add_parser("verify", help="Render a task or phase verify-ready prompt.")
    verify_target = verify_parser.add_mutually_exclusive_group(required=True)
    verify_target.add_argument("--task", help="Task label, for example 0-1/task-01.")
    verify_target.add_argument("--phase", help="Phase label, for example phase-0 or 0.")

    export_parser = subparsers.add_parser("export", help="Export copy-ready and verify-ready prompts to files.")
    export_target = export_parser.add_mutually_exclusive_group(required=True)
    export_target.add_argument("--all", action="store_true", help="Export prompts for all phases.")
    export_target.add_argument("--phase", help="Export prompts for one phase, for example phase-0 or 0.")

    mark_parser = subparsers.add_parser("mark", help="Record manual task progress.")
    mark_parser.add_argument("--task", required=True, help="Task label, for example 0-1/task-01.")
    mark_parser.add_argument(
        "--status",
        required=True,
        choices=["pending", "in_progress", "blocked", "failed", "completed"],
        help="Manual progress status.",
    )
    mark_parser.add_argument("--note", default="", help="Optional progress note.")
    mark_parser.add_argument("--force", action="store_true", help="Allow completion before dependencies are completed.")

    audit_parser = subparsers.add_parser("audit", help="Print prompt coverage audit reports.")
    audit_parser.add_argument("--pages", action="store_true", help="Audit page to Core capability coverage.")

    subparsers.add_parser("status", help="Print prompt library summary.")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.command == "doctor":
        return command_doctor(args)
    if args.command == "plan":
        return command_plan(args)
    if args.command == "next":
        return command_next(args)
    if args.command == "render":
        return command_render(args)
    if args.command == "verify":
        return command_verify(args)
    if args.command == "export":
        return command_export(args)
    if args.command == "mark":
        return command_mark(args)
    if args.command == "status":
        return command_status(args)
    if args.command == "audit":
        return command_audit(args)
    parser.error(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
