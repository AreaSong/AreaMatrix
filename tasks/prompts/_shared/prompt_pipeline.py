#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone
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
DEPENDENCY_GRAPH = SHARED_ROOT / "dependency-graph.md"
PROGRESS_PATH = SHARED_ROOT / "progress.json"

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
MANIFEST_HEADING_RE = re.compile(r"^##\s+(.+)$", re.M)
UX_DOC_RE = re.compile(r"/(S(?:[1-3]-\d+|4-[A-Z]+-\d+)-[^/]+)\.md$")
CAPABILITY_DOC_RE = re.compile(r"/(C[1-4]-\d+)-[^/]+\.md$")


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


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def strip_bullet(line: str) -> str | None:
    stripped = line.strip()
    if not stripped.startswith("- "):
        return None
    value = stripped[2:].strip()
    if value == "None":
        return None
    if value.startswith("`") and value.endswith("`"):
        return value[1:-1]
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


def task_kind(task: TaskFile, entry: ManifestEntry) -> str:
    haystack = f"{task.title} {entry.source_task} {entry.raw}".lower()
    if any(token in haystack for token in ["integration", "verify", "集成", "验收"]):
        return "integration"
    return "atomic"


def binding_summary(entry: ManifestEntry) -> tuple[str, str]:
    ux_ids = unique_doc_ids(entry.exact_docs, UX_DOC_RE)
    capability_ids = unique_doc_ids(entry.exact_docs, CAPABILITY_DOC_RE)
    return (
        ", ".join(ux_ids) if ux_ids else "None",
        ", ".join(capability_ids) if capability_ids else "None",
    )


def validate_granularity(task: TaskFile, entry: ManifestEntry) -> list[str]:
    if task_kind(task, entry) == "integration":
        return []
    ux_ids = unique_doc_ids(entry.exact_docs, UX_DOC_RE)
    capability_ids = unique_doc_ids(entry.exact_docs, CAPABILITY_DOC_RE)
    errors: list[str] = []
    if len(ux_ids) > 1:
        errors.append(f"{task.label}: atomic task binds multiple UX pages: {', '.join(ux_ids)}")
    if len(capability_ids) > 1:
        errors.append(
            f"{task.label}: atomic task binds multiple Core capabilities: {', '.join(capability_ids)}"
        )
    if task.phase in {"phase-1", "phase-2", "phase-4"} and not ux_ids and not capability_ids:
        errors.append(f"{task.label}: atomic product task must bind one UX page or one Core capability")
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
    if not DEPENDENCY_GRAPH.exists():
        errors.append(f"missing dependency graph: {rel(DEPENDENCY_GRAPH)}")

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
    kind = task_kind(task, entry)

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
    print(f"- Phase：`{task.phase}`")
    print(f"- Task 标识：`{task.label}`")
    print(f"- Task 文件：`{task.path}`")
    print(f"- 共享规则：`{AUDIT_RULES}`")
    print(f"- 任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"- 依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"- Phase Manifest：`{entry.manifest_path}`")
    print(f"- Manifest 章节：`## {entry.label}`")
    print(f"- 依赖任务：`{deps}`")
    print(f"- 风险等级：`{entry.risk}`")
    print(f"- 绑定 UX 页面：`{ux_binding}`")
    print(f"- 绑定 Core 能力：`{capability_binding}`")
    print("- 是否允许修改文件：`是，仅限 Expected New Paths；integration task 只做集成 wiring 或验收材料`")
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
    print(f"4. 读取依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"5. 读取 phase manifest：`{entry.manifest_path}`")
    print(f"6. 在 manifest 中定位章节：`## {entry.label}`")
    print("7. 逐个读取该章节下的 `Exact Docs`。")
    print("8. 逐个读取当前存在的 `Existing Code`。")
    print("9. 确认改动只会落在 `Expected New Paths`。")
    print("10. 确认不会触碰 `Forbidden Touches`。")
    print("11. 若风险等级为 High 或 Mission-Critical，先给出风险、验证和回滚思路，再继续。")
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
    print("- Integration task 只能做集成 wiring、验收补齐或阶段证据整理；不得新增未绑定功能。")
    print("- 对已存在 capability specs 的任务，必须交叉检查 UX 页面、Core 能力规格和对应 control map。")
    print("- 再读取存在的 `Existing Code`。")
    print("- 只在 `Expected New Paths` 内新增或修改。")
    print("- 不触碰 `Forbidden Touches`，除非重新确认。")
    print("- 禁止提前实现后续任务的功能，尤其是工程骨架任务不得塞入业务逻辑。")
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
    print("四、验证情况")
    print()
    print("- 跑了哪些验证")
    print("- 哪些通过")
    print("- 哪些失败")
    print("- 哪些无法运行及原因")
    print()
    print("五、风险与后续")
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
    kind = task_kind(task, entry)

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
    print(f"- Phase：`{task.phase}`")
    print(f"- Task 标识：`{task.label}`")
    print(f"- Task 文件：`{task.path}`")
    print(f"- 共享规则：`{AUDIT_RULES}`")
    print(f"- 任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"- 依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"- Phase Manifest：`{entry.manifest_path}`")
    print(f"- Manifest 章节：`## {entry.label}`")
    print(f"- 依赖任务：`{deps}`")
    print(f"- 风险等级：`{entry.risk}`")
    print(f"- 绑定 UX 页面：`{ux_binding}`")
    print(f"- 绑定 Core 能力：`{capability_binding}`")
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
    print(f"4. 读取依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"5. 读取 phase manifest：`{entry.manifest_path}`")
    print(f"6. 在 manifest 中定位章节：`## {entry.label}`")
    print("7. 逐个读取该章节下的 `Exact Docs`。")
    print("8. 逐个读取该章节下当前存在的 `Existing Code`。")
    print("9. 检查 `Expected New Paths` 是否已按任务完成标准落地；缺失即记录证据。")
    print("10. 检查 `Forbidden Touches` 是否被违规修改。")
    print("11. 基于 task 文件中的核对清单与完成标准逐项验收。")
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
    print("## 任务切片规则")
    print()
    print(TASK_SLICING_RULES.read_text(encoding="utf-8").strip())
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
    print("- 任何高风险边界缺少测试或证据时，默认不通过。")
    print("- 可以运行只读验证或测试命令；不得运行会重写 repo-tracked 文件的 formatter、codegen 或修复命令。")
    print()
    print("## 你必须检查")
    print()
    print("1. 是否真的按 manifest 做了逐文件覆盖，而不是只做了局部。")
    print("2. task 的核对清单是否逐项满足。")
    print("3. task 的完成标准是否逐项满足。")
    print("4. 是否仍存在文档有而代码无、代码有而文档无、链路未打通、验证缺失等问题。")
    print("5. 当前仓库状态是否足以把该 task 判定为完成。")
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
    print("五、阻塞项")
    print()
    print("- 若有问题，逐条列出 P0/P1 标题、说明、绝对路径、行号、为什么导致不通过")
    print("- 如果没有，明确写“未发现阻塞项”")
    print()
    print("六、验证情况")
    print()
    print("- 跑了哪些验证")
    print("- 哪些通过")
    print("- 哪些失败")
    print("- 哪些缺失")
    print()
    print("七、最终判定说明")
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
    print(f"3. 读取依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"4. 读取 phase manifest：`{MANIFEST_ROOT / (normalized + '.md')}`")
    print("5. 按下方顺序逐个验收 task。")
    print("6. 每个 task 都必须回到 task 文件、manifest 章节、实际文件三者交叉验收。")
    print("7. 已存在 capability specs 的 task 必须额外交叉检查 UX 页面、Core 能力规格和对应 control map。")
    print("8. 任一 task 不通过，则阶段不通过。")
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
    print()
    print("## 阶段验收原则")
    print()
    print("- 无法证明通过，就判定不通过。")
    print("- 不接受只看 diff。")
    print("- 不接受占位、空壳、链路未打通。")
    print("- 真实闭环仍使用 mock、fixture 或硬编码状态时，必须判定不通过。")
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
    print("五、阶段阻塞项")
    print()
    print("- P0/P1 标题")
    print("- 说明")
    print("- 绝对路径与行号")
    print("- 为什么导致阶段不通过")
    print()
    print("六、验证情况")
    print()
    print("- 跑了哪些验证")
    print("- 哪些通过")
    print("- 哪些失败")
    print("- 哪些缺失")
    print()
    print("七、最终判定说明")
    print()
    print("- 本阶段已达到验收标准。")
    print("  或")
    print("- 本阶段尚未达到验收标准，不能视为完成。")
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
    if args.command == "mark":
        return command_mark(args)
    if args.command == "status":
        return command_status(args)
    parser.error(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
