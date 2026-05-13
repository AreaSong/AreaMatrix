from __future__ import annotations

from pathlib import Path
import re

from .contracts import (
    entry_capability_ids,
    entry_page_ids,
    is_core_integration_verify,
    load_page_contracts,
    page_contract_summary,
    secondary_capability_note,
    task_detail_kind,
    task_kind,
)
from .paths import ManifestEntry, PageContract, TaskFile, ROOT, label_sort_key, rel


def capability_specs() -> dict[str, Path]:
    specs: dict[str, Path] = {}
    for path in sorted((ROOT / "docs" / "core" / "capability-specs").glob("**/C*.md")):
        match = re.search(r"(C[1-4]-\d+)", path.name)
        if match:
            specs[match.group(1)] = path
    return specs


def capability_task_labels(
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> dict[str, list[str]]:
    labels: dict[str, list[str]] = {}
    for label, entry in manifests.items():
        if label in tasks:
            add_capability_labels(labels, label, entry)
    for capability in labels:
        labels[capability].sort(key=label_sort_key)
    return labels


def add_capability_labels(labels: dict[str, list[str]], label: str, entry: ManifestEntry) -> None:
    for capability in entry_capability_ids(entry):
        labels.setdefault(capability, []).append(label)


def required_core_task_tokens(capability: str) -> list[str]:
    if capability.startswith("C1-"):
        return ["contract-api", "implementation", "validation", "integration-verify"]
    return ["contract-api", "implementation", "failure-edge", "validation", "integration-verify"]


def missing_core_task_tokens(
    capability: str,
    tasks: dict[str, TaskFile],
    labels: list[str],
) -> list[str]:
    titles = "\n".join(tasks[label].title.lower() for label in labels if label in tasks)
    return [token for token in required_core_task_tokens(capability) if token not in titles]


def core_coverage_stats(
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> dict[str, int]:
    specs = capability_specs()
    labels_by_capability = capability_task_labels(tasks, manifests)
    core_verify_labels = core_integration_verify_labels(tasks, manifests)
    return {
        "capabilities": len(specs),
        "capability_without_task": count_missing_capabilities(specs, labels_by_capability),
        "bad_c1_groups": count_bad_groups(labels_by_capability, tasks, c1=True),
        "bad_c234_groups": count_bad_groups(labels_by_capability, tasks, c1=False),
        "core_integration_verify": len(core_verify_labels),
        "core_verify_misclassified": count_misclassified_core_verify(core_verify_labels, tasks, manifests),
        "core_verify_secondary_blocking": count_secondary_blocking(core_verify_labels, tasks, manifests),
    }


def core_integration_verify_labels(
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> list[str]:
    return [
        label
        for label, task in tasks.items()
        if label in manifests and is_core_integration_verify(task, manifests[label])
    ]


def count_missing_capabilities(specs: dict[str, Path], labels_by_capability: dict[str, list[str]]) -> int:
    return len([capability for capability in specs if capability not in labels_by_capability])


def count_bad_groups(
    labels_by_capability: dict[str, list[str]],
    tasks: dict[str, TaskFile],
    c1: bool,
) -> int:
    bad = []
    for capability, labels in labels_by_capability.items():
        is_c1 = capability.startswith("C1-")
        if is_c1 == c1 and missing_core_task_tokens(capability, tasks, labels):
            bad.append(capability)
    return len(bad)


def count_misclassified_core_verify(
    labels: list[str],
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> int:
    return len([
        label for label in labels if task_detail_kind(tasks[label], manifests[label]) != "core-integration-verify"
    ])


def count_secondary_blocking(
    labels: list[str],
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> int:
    return len([
        label
        for label in labels
        if "阻断" in secondary_capability_note(tasks[label], manifests[label], page_contract_summary(tasks[label], manifests[label])[2])
    ])


def validate_core_task_coverage(
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> list[str]:
    errors = validate_capability_task_groups(tasks, manifests)
    errors.extend(validate_core_verify_tasks(tasks, manifests))
    return errors


def validate_capability_task_groups(
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> list[str]:
    errors: list[str] = []
    labels_by_capability = capability_task_labels(tasks, manifests)
    for capability, path in sorted(capability_specs().items()):
        labels = labels_by_capability.get(capability, [])
        if not labels:
            errors.append(f"{rel(path)}: capability has no prompt task")
            continue
        missing = missing_core_task_tokens(capability, tasks, labels)
        if missing:
            errors.append(f"{capability}: missing Core task types: {', '.join(missing)}")
    return errors


def validate_core_verify_tasks(
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> list[str]:
    errors: list[str] = []
    for label, task in sorted(tasks.items(), key=lambda item: label_sort_key(item[0])):
        entry = manifests.get(label)
        if entry and is_core_integration_verify(task, entry):
            errors.extend(validate_one_core_verify(label, task, entry))
    return errors


def validate_one_core_verify(label: str, task: TaskFile, entry: ManifestEntry) -> list[str]:
    errors: list[str] = []
    capabilities = entry_capability_ids(entry)
    if len(capabilities) != 1:
        errors.append(f"{label}: Core integration verify must bind exactly one Core capability, got {', '.join(capabilities) or 'None'}")
    if task_detail_kind(task, entry) != "core-integration-verify":
        errors.append(f"{label}: Core integration verify misclassified as {task_detail_kind(task, entry)}")
    missing_caps = page_contract_summary(task, entry)[2]
    if "阻断" in secondary_capability_note(task, entry, missing_caps):
        errors.append(f"{label}: Core integration verify has blocking secondary capability note")
    return errors


def validate_page_contract_coverage(
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> list[str]:
    errors: list[str] = []
    for contract in load_page_contracts().values():
        errors.extend(validate_one_page_contract(contract, tasks, manifests))
    return errors


def validate_one_page_contract(
    contract: PageContract,
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> list[str]:
    errors = validate_prompt_labels(contract, tasks, manifests)
    feature_labels, verify_labels, covered, extra, verify_errors = page_feature_audit(contract, tasks, manifests)
    expected = set(contract.capabilities)
    errors.extend(page_coverage_errors(contract, expected, feature_labels, verify_labels, covered, extra))
    errors.extend(f"{contract_location(contract)}: {error}" for error in verify_errors)
    return errors


def validate_prompt_labels(
    contract: PageContract,
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> list[str]:
    if not contract.prompt_labels:
        return [f"{contract_location(contract)}: missing prompt labels"]
    errors: list[str] = []
    for label in contract.prompt_labels:
        if label not in tasks:
            errors.append(f"{contract_location(contract)}: unknown prompt label {label}")
        elif label not in manifests:
            errors.append(f"{contract_location(contract)}: missing manifest for {label}")
    return errors


def contract_location(contract: PageContract) -> str:
    return f"{rel(contract.control_map_path)}:{contract.line_no} {contract.page_id}"


def page_feature_audit(
    contract: PageContract,
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> tuple[list[str], list[str], set[str], set[str], list[str]]:
    feature_labels: list[str] = []
    verify_labels: list[str] = []
    feature_caps: set[str] = set()
    verify_errors: list[str] = []
    expected = set(contract.capabilities)
    for label in contract.prompt_labels:
        collect_page_feature(label, contract, expected, tasks, manifests, feature_labels, verify_labels, feature_caps, verify_errors)
    return feature_labels, verify_labels, feature_caps, feature_caps - expected, verify_errors


def collect_page_feature(
    label: str,
    contract: PageContract,
    expected: set[str],
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
    feature_labels: list[str],
    verify_labels: list[str],
    feature_caps: set[str],
    verify_errors: list[str],
) -> None:
    task = tasks.get(label)
    entry = manifests.get(label)
    if not task or not entry or contract.page_id not in entry_page_ids(entry):
        return
    caps = set(entry_capability_ids(entry))
    if task_kind(task, entry) == "integration":
        verify_labels.append(label)
        validate_page_verify(label, expected, caps, verify_errors)
    else:
        feature_labels.append(label)
        feature_caps.update(caps)


def validate_page_verify(
    label: str,
    expected: set[str],
    caps: set[str],
    verify_errors: list[str],
) -> None:
    if expected and caps != expected:
        verify_errors.append(
            f"{label} should cover {', '.join(sorted(expected))}, got {', '.join(sorted(caps)) or 'None'}"
        )
    if not expected and caps:
        verify_errors.append(f"{label} should be UI-only, got {', '.join(sorted(caps))}")


def page_coverage_errors(
    contract: PageContract,
    expected: set[str],
    feature_labels: list[str],
    verify_labels: list[str],
    covered: set[str],
    extra: set[str],
) -> list[str]:
    errors: list[str] = []
    add_missing_page_coverage(contract, expected, covered, errors)
    add_extra_page_coverage(contract, extra, errors)
    if len(expected) > 1 and not verify_labels:
        errors.append(f"{contract_location(contract)}: multi-capability page is missing page integration verify")
    if not feature_labels:
        errors.append(f"{contract_location(contract)}: missing page-feature task")
    return errors


def add_missing_page_coverage(
    contract: PageContract,
    expected: set[str],
    covered: set[str],
    errors: list[str],
) -> None:
    missing = sorted(expected - covered)
    if missing:
        errors.append(f"{contract_location(contract)}: prompt coverage missing Core capabilities: {', '.join(missing)}")


def add_extra_page_coverage(contract: PageContract, extra: set[str], errors: list[str]) -> None:
    extra_values = sorted(extra)
    if extra_values:
        errors.append(f"{contract_location(contract)}: prompt coverage has extra Core capabilities: {', '.join(extra_values)}")
