from __future__ import annotations

import sys

from .contracts import binding_summary, task_kind
from .paths import (
    AUDIT_RULES,
    CODING_STANDARDS,
    DEPENDENCY_GRAPH,
    ENGINEERING_QUALITY_RULES,
    MANIFEST_ROOT,
    ROOT,
    SKILL_SOURCE_ROOT,
    TASK_SLICING_RULES,
    VALIDATION_DRIVER_SKILL,
    ManifestEntry,
    TaskFile,
)
from .rendering import print_repo_local_skill_paths, print_validation_driver_reference
from .repository import filter_labels, ordered_labels


def print_phase_verify_prompt(
    phase: str,
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> int:
    normalized, labels = phase_labels(phase, tasks, manifests)
    if not labels:
        print(f"unknown or empty phase: {phase}", file=sys.stderr)
        return 1
    print_phase_header(normalized, labels)
    print_phase_start_steps(normalized)
    print_phase_task_list(labels, tasks, manifests)
    print_phase_shared_rules()
    print_phase_acceptance_rules()
    print_phase_output_format()
    return 0


def phase_labels(
    phase: str,
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> tuple[str, list[str]]:
    normalized = phase if phase.startswith("phase-") else f"phase-{phase}"
    labels = filter_labels(ordered_labels(tasks, manifests), tasks, normalized)
    return normalized, labels


def print_phase_header(normalized: str, labels: list[str]) -> None:
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
    print(f"- Repo-local Skills：`{SKILL_SOURCE_ROOT}`")
    print(f"- Validation Driver：`{VALIDATION_DRIVER_SKILL}`")
    print(f"- 依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"- Phase Manifest：`{MANIFEST_ROOT / (normalized + '.md')}`")
    print()
    print("你的任务不是继续实现，而是严格验收该阶段所有 task 是否已经真正达到完成标准。")
    print("这次是验收，不是修复：禁止修改文件，禁止边验边改。")
    print()


def print_phase_start_steps(normalized: str) -> None:
    print("## 开始前必须按顺序完成")
    print()
    print(f"1. 读取共享规则：`{AUDIT_RULES}`")
    print(f"2. 读取任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"3. 读取工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"4. 读取编码规范：`{CODING_STANDARDS}`")
    print(f"5. 读取 validation-driver：`{VALIDATION_DRIVER_SKILL}`；不要读取 `/Users/as/.codex/skills-src/...`。")
    print(f"6. 读取依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"7. 读取 phase manifest：`{MANIFEST_ROOT / (normalized + '.md')}`")
    print("8. 按下方顺序逐个验收 task。")
    print("9. 每个 task 都必须回到 task 文件、manifest 章节、实际文件三者交叉验收。")
    print("10. 已存在 capability specs 的 task 必须额外交叉检查 UX 页面、Core 能力规格和对应 control map。")
    print("11. 任一 task 不通过，则阶段不通过。")
    print()


def print_phase_task_list(
    labels: list[str],
    tasks: dict[str, TaskFile],
    manifests: dict[str, ManifestEntry],
) -> None:
    print("## 阶段任务清单")
    print()
    for label in labels:
        print_phase_task_item(label, tasks[label], manifests[label])
    print()


def print_phase_task_item(label: str, task: TaskFile, entry: ManifestEntry) -> None:
    deps = ", ".join(entry.depends) if entry.depends else "None"
    ux_binding, capability_binding = binding_summary(entry)
    print(
        f"- `{label}` | {task.title} | type: `{task_kind(task, entry)}` | "
        f"risk: `{entry.risk}` | depends: `{deps}`"
    )
    print(f"  - task: `{task.path}`")
    print(f"  - manifest: `{entry.manifest_path}` -> `## {entry.label}`")
    print(f"  - UX: `{ux_binding}` | Core: `{capability_binding}`")


def print_phase_shared_rules() -> None:
    print("## 共享验收规则")
    print()
    print(AUDIT_RULES.read_text(encoding="utf-8").strip())
    print()
    print("## 工程质量规则")
    print()
    print(ENGINEERING_QUALITY_RULES.read_text(encoding="utf-8").strip())
    print()
    print_repo_local_skill_paths()
    print_validation_driver_reference()


def print_phase_acceptance_rules() -> None:
    print("## 单任务验收要求")
    print()
    print("对每个 task，必须检查：")
    print()
    for item in single_task_checks():
        print(item)
    print()
    print("## 阶段验收原则")
    print()
    for item in phase_principles():
        print(f"- {item}")
    print()


def single_task_checks() -> list[str]:
    return [
        "1. `Exact Docs` 是否逐个阅读并作为 SSOT。",
        "2. 当前存在的 `Existing Code` 是否逐个阅读。",
        "3. `Expected New Paths` 是否已真实落地。",
        "4. `Forbidden Touches` 是否被违规触碰。",
        "5. task 核对清单是否逐项满足。",
        "6. task 完成标准是否逐项满足。",
        "7. `Validation` 是否运行，失败或缺失是否足以阻断。",
        "8. task 是否同时满足 UX 页面、Core 能力规格和对应 control map。",
        "9. task 是否满足工程质量规则和编码规范；一次性实现、占位、硬编码通过态必须阻断。",
    ]


def phase_principles() -> list[str]:
    return [
        "无法证明通过，就判定不通过。",
        "不接受只看 diff。",
        "不接受占位、空壳、链路未打通。",
        "真实闭环仍使用 mock、fixture 或硬编码状态时，必须判定不通过。",
        "任一 task 的工程质量不达标，阶段不通过。",
        "任一 Mission-Critical task 缺少验证证据，阶段默认不通过。",
        "任一 task 不通过，阶段不通过。",
    ]


def print_phase_output_format() -> None:
    print("## 最后必须按这个格式输出")
    print()
    print("一、阶段验收结论")
    print()
    print("- 通过")
    print("  或")
    print("- 不通过")
    print_report_block("二、验收范围", ["Phase", "任务数量", "对应 task 文件路径"])
    print_report_block("三、阶段完成度摘要", ["通过任务数", "不通过任务数", "阻塞任务数", "缺失验证任务数"])
    print_report_block("四、逐任务验收结果", ["Task", "结果：通过 / 不通过", "证据", "阻塞项"])
    print_report_block("五、工程质量汇总", ["不达标任务", "主要质量问题", "涉及文件", "为什么阻断阶段通过"])
    print_report_block("六、阶段阻塞项", ["P0/P1 标题", "说明", "绝对路径与行号", "为什么导致阶段不通过"])
    print_report_block("七、验证情况", ["跑了哪些验证", "哪些通过", "哪些失败", "哪些缺失"])
    print()
    print("八、最终判定说明")
    print()
    print("- 本阶段已达到验收标准。")
    print("  或")
    print("- 本阶段尚未达到验收标准，不能视为完成。")


def print_report_block(title: str, bullets: list[str]) -> None:
    print()
    print(title)
    print()
    for bullet in bullets:
        print(f"- {bullet}")
