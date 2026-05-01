from __future__ import annotations

from pathlib import Path
import re

from .paths import (
    CAPABILITY_DOC_RE,
    CAPABILITY_ID_RE,
    CORE_VERIFY_RE,
    LABEL_IN_TEXT_RE,
    PAGE_ID_RE,
    PAGE_VERIFY_RE,
    ROOT,
    UX_DOC_RE,
    ManifestEntry,
    PageContract,
    TaskFile,
)


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
        read_control_map(path, contracts)
    return contracts


def read_control_map(path: Path, contracts: dict[str, PageContract]) -> None:
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.startswith("| S"):
            continue
        contract = parse_control_map_row(path, line_no, line)
        if contract:
            contracts[contract.page_id] = contract


def parse_control_map_row(path: Path, line_no: int, line: str) -> PageContract | None:
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    if len(cells) < 6 or not PAGE_ID_RE.match(cells[0]):
        return None
    capabilities = unique_capabilities(cells[2])
    prompt_cell = cells[7] if len(cells) > 8 else cells[-1]
    return PageContract(
        cells[0],
        cells[1],
        tuple(capabilities),
        tuple(extract_labels(prompt_cell)),
        path,
        line_no,
    )


def unique_capabilities(value: str) -> list[str]:
    result: list[str] = []
    for capability in CAPABILITY_ID_RE.findall(value):
        if capability not in result:
            result.append(capability)
    return result


def task_kind(task: TaskFile, entry: ManifestEntry) -> str:
    haystack = f"{task.title} {entry.source_task} {entry.raw}".lower()
    tokens = ["integration-verify", "integration verify", "集成验收", "验收"]
    return "integration" if any(token in haystack for token in tokens) else "atomic"


def task_identity_text(task: TaskFile, entry: ManifestEntry) -> str:
    return f"{task.title} {entry.source_task}".lower()


def is_core_integration_verify(task: TaskFile, entry: ManifestEntry) -> bool:
    is_integration = task_kind(task, entry) == "integration"
    return is_integration and bool(CORE_VERIFY_RE.search(task_identity_text(task, entry)))


def is_page_integration_verify(task: TaskFile, entry: ManifestEntry) -> bool:
    is_integration = task_kind(task, entry) == "integration"
    return is_integration and bool(PAGE_VERIFY_RE.search(task_identity_text(task, entry)))


def task_detail_kind(task: TaskFile, entry: ManifestEntry) -> str:
    pages = entry_page_ids(entry)
    capabilities = entry_capability_ids(entry)
    source = task_identity_text(task, entry)
    if task_kind(task, entry) == "integration":
        return integration_detail_kind(task, entry, source)
    if pages:
        return "page-feature"
    if "contract-api" in source:
        return "core-contract"
    if "failure" in source or "edge" in source:
        return "core-failure-edge"
    if "validation" in source:
        return "core-validation"
    return "core-implementation" if capabilities else "atomic"


def integration_detail_kind(task: TaskFile, entry: ManifestEntry, source: str) -> str:
    if is_core_integration_verify(task, entry):
        return "core-integration-verify"
    if is_page_integration_verify(task, entry):
        return "page-integration"
    if "foundation" in source:
        return "foundation-verify"
    return "stage-verify"


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
    errors: list[str] = []
    page_ids = entry_page_ids(entry)
    capability_ids = entry_capability_ids(entry)
    validate_page_granularity(task, page_ids, capability_ids, errors)
    validate_capability_granularity(task, page_ids, capability_ids, errors)
    return errors


def validate_page_granularity(
    task: TaskFile,
    page_ids: list[str],
    capability_ids: list[str],
    errors: list[str],
) -> None:
    if len(page_ids) > 1:
        errors.append(f"{task.label}: atomic task binds multiple UX pages: {', '.join(page_ids)}")
    if not page_ids:
        return
    expected = set(load_page_contracts().get(page_ids[0], empty_contract(page_ids[0])).capabilities)
    extra = sorted(set(capability_ids) - expected)
    if extra:
        errors.append(f"{task.label}: UI task references Core capabilities not declared for {page_ids[0]}: {', '.join(extra)}")
    if len(capability_ids) > 1:
        errors.append(f"{task.label}: page-feature atomic task binds multiple Core capabilities: {', '.join(capability_ids)}")
    if expected and not capability_ids:
        errors.append(f"{task.label}: page-feature atomic task does not bind a Core capability for {page_ids[0]}")


def empty_contract(page_id: str) -> PageContract:
    return PageContract(page_id, "", (), (), ROOT, 0)


def validate_capability_granularity(
    task: TaskFile,
    page_ids: list[str],
    capability_ids: list[str],
    errors: list[str],
) -> None:
    if not page_ids and len(capability_ids) > 1:
        errors.append(f"{task.label}: atomic task binds multiple Core capabilities: {', '.join(capability_ids)}")
    product_phase = task.phase in {"phase-1", "phase-2", "phase-4"}
    if product_phase and not page_ids and not capability_ids:
        errors.append(f"{task.label}: atomic product task must bind one UX page or one Core capability")


def page_contract_summary(task: TaskFile, entry: ManifestEntry) -> tuple[str, str, str, str]:
    pages = entry_page_ids(entry)
    covered = set(entry_capability_ids(entry))
    expected, page_parts = expected_capabilities_for_pages(pages)
    missing = [] if task_detail_kind(task, entry) == "core-integration-verify" else sorted(expected - covered)
    extra = sorted(covered - expected) if pages else []
    return (
        "; ".join(page_parts) if page_parts else "None",
        ", ".join(sorted(covered)) if covered else "None",
        ", ".join(missing) if missing else "None",
        ", ".join(extra) if extra else "None",
    )


def expected_capabilities_for_pages(pages: list[str]) -> tuple[set[str], list[str]]:
    expected: set[str] = set()
    page_parts: list[str] = []
    page_contracts = load_page_contracts()
    for page_id in pages:
        contract = page_contracts.get(page_id)
        if not contract:
            page_parts.append(f"{page_id}: not in control map")
            continue
        expected.update(contract.capabilities)
        capability_text = ", ".join(contract.capabilities) if contract.capabilities else "None"
        page_parts.append(f"{page_id}: {capability_text}")
    return expected, page_parts


def secondary_capability_note(task: TaskFile, entry: ManifestEntry, missing_caps: str) -> str:
    detail_kind = task_detail_kind(task, entry)
    if detail_kind in {"stage-verify", "foundation-verify"}:
        return "None"
    if missing_caps == "None":
        return no_secondary_missing_note(task, entry, detail_kind)
    if detail_kind == "page-feature":
        return f"{missing_caps}（page-feature task：同页其他能力由其他 task 与 page integration verify 覆盖）"
    if detail_kind == "core-integration-verify":
        return f"{missing_caps}（消费页面中的其他能力不属于当前 Core task 验收范围；不作为当前 Core verify 的阻断项）"
    return f"{missing_caps}（当前 task 缺少 secondary capability docs，验收时必须阻断）"


def no_secondary_missing_note(task: TaskFile, entry: ManifestEntry, detail_kind: str) -> str:
    if detail_kind == "core-integration-verify" and entry_page_ids(entry):
        return "消费页面中的其他能力不属于当前 Core task 验收范围；仅检查当前能力是否满足这些页面对该能力的需求"
    return "None"

