from __future__ import annotations

from contextlib import redirect_stdout
from dataclasses import dataclass
import io
from pathlib import Path

from .contracts import (
    binding_summary,
    page_contract_summary,
    secondary_capability_note,
    task_detail_kind,
    task_kind,
)
from .paths import (
    AUDIT_RULES,
    CODING_STANDARDS,
    DEPENDENCY_GRAPH,
    ENGINEERING_QUALITY_RULES,
    REPO_LOCAL_SKILLS,
    ROOT,
    SKILL_SOURCE_ROOT,
    TASK_SLICING_RULES,
    VALIDATION_DRIVER_MATRIX,
    VALIDATION_DRIVER_REPORT,
    VALIDATION_DRIVER_SKILL,
    ManifestEntry,
    TaskFile,
)
from .repository import markdown_section, skill_file


@dataclass(frozen=True)
class PromptContext:
    task_text: str
    checklist: str
    completion: str
    validation: str
    deps: str
    ux_binding: str
    capability_binding: str
    expected_caps: str
    covered_caps: str
    missing_caps: str
    extra_caps: str
    secondary_note: str
    kind: str
    detail_kind: str


def build_prompt_context(task: TaskFile, entry: ManifestEntry) -> PromptContext:
    task_text = task.path.read_text(encoding="utf-8")
    expected, covered, missing, extra = page_contract_summary(task, entry)
    ux_binding, capability_binding = binding_summary(entry)
    return PromptContext(
        task_text=task_text,
        checklist=markdown_section(task_text, "核对清单"),
        completion=markdown_section(task_text, "完成标准"),
        validation=markdown_section(task_text, "验证"),
        deps=", ".join(entry.depends) if entry.depends else "None",
        ux_binding=ux_binding,
        capability_binding=capability_binding,
        expected_caps=expected,
        covered_caps=covered,
        missing_caps=missing,
        extra_caps=extra,
        secondary_note=secondary_capability_note(task, entry, missing),
        kind=task_kind(task, entry),
        detail_kind=task_detail_kind(task, entry),
    )


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


def print_repo_local_skill_paths() -> None:
    print("## Repo-local Skill 路径")
    print()
    print(f"- Skill 源事实目录：`{SKILL_SOURCE_ROOT}`")
    print(f"- Skill 发现入口：`{ROOT / '.agents' / 'skills'}`")
    print("- 禁止猜测全局路径：不要读取 `/Users/as/.codex/skills-src/...`。")
    print("- 若需要使用 AreaMatrix repo-local skill，只读取以下路径：")
    for name in REPO_LOCAL_SKILLS:
        print(f"  - `{name}`：`{skill_file(name)}`")
    print()


def print_validation_driver_reference() -> None:
    print("## Validation Driver 规则")
    print()
    print("验收和验证选择必须使用 repo-local validation-driver；本节已内嵌关键规则，避免误读全局 skill 路径。")
    print()
    print("### Skill")
    print()
    print(VALIDATION_DRIVER_SKILL.read_text(encoding="utf-8").strip())
    print()
    print("### Validation Matrix")
    print()
    print(VALIDATION_DRIVER_MATRIX.read_text(encoding="utf-8").strip())
    print()
    print("### Report Format")
    print()
    print(VALIDATION_DRIVER_REPORT.read_text(encoding="utf-8").strip())
    print()


def print_copy_prompt(task: TaskFile, entry: ManifestEntry) -> None:
    ctx = build_prompt_context(task, entry)
    print(f"# Copy-ready Prompt: {task.label}")
    print()
    print("你现在进入 AreaMatrix 的单任务执行模式。")
    print_common_intro(task, entry, ctx, "本次执行对象", copy_permission_note(ctx.detail_kind))
    print_copy_start_steps(task, entry)
    print_task_requirement_sections(task, ctx, "必须实现的核对清单")
    print_copy_body(task, entry, ctx)


def print_verify_prompt(task: TaskFile, entry: ManifestEntry) -> None:
    ctx = build_prompt_context(task, entry)
    print(f"# Verify-ready Prompt: {task.label}")
    print()
    print("你现在进入 AreaMatrix 的单任务验收模式。")
    print_common_intro(task, entry, ctx, "本次验收对象", "否，本模式只读验收")
    print("你的任务不是继续实现，而是严格验收这个 task 当前是否已经真正达到完成标准。")
    print("这次是验收，不是修复：禁止修改文件，禁止边验边改。")
    print()
    print_verify_start_steps(task, entry)
    print_task_requirement_sections(task, ctx, "必须逐项验收的核对清单")
    print_verify_body(entry, ctx)


def print_common_intro(
    task: TaskFile,
    entry: ManifestEntry,
    ctx: PromptContext,
    title: str,
    edit_permission: str,
) -> None:
    print_workdir()
    print(f"## {title}")
    print()
    print_common_metadata(task, entry, ctx, edit_permission)
    print_manifest_counts(entry)
    print()


def print_workdir() -> None:
    print()
    print("## 工作目录")
    print()
    print(f"`{ROOT}`")
    print()


def print_common_metadata(
    task: TaskFile,
    entry: ManifestEntry,
    ctx: PromptContext,
    edit_permission: str,
) -> None:
    print("- 类型：单任务执行" if edit_permission != "否，本模式只读验收" else "- 类型：单任务验收")
    print(f"- 任务类型：`{ctx.kind}`")
    print(f"- 任务细分：`{ctx.detail_kind}`")
    print(f"- Phase：`{task.phase}`")
    print(f"- Task 标识：`{task.label}`")
    print(f"- Task 文件：`{task.path}`")
    print(f"- 共享规则：`{AUDIT_RULES}`")
    print(f"- 任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"- 工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"- 编码规范：`{CODING_STANDARDS}`")
    print(f"- Repo-local Skills：`{SKILL_SOURCE_ROOT}`")
    print(f"- Validation Driver：`{VALIDATION_DRIVER_SKILL}`")
    print(f"- 依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"- Phase Manifest：`{entry.manifest_path}`")
    print(f"- Manifest 章节：`## {entry.label}`")
    print(f"- 依赖任务：`{ctx.deps}`")
    print(f"- 风险等级：`{entry.risk}`")
    print(f"- 绑定 UX 页面：`{ctx.ux_binding}`")
    print(f"- 绑定 Core 能力：`{ctx.capability_binding}`")
    print(f"- Control map 期望 Core 能力：`{ctx.expected_caps}`")
    print(f"- 当前 task 覆盖 Core 能力：`{ctx.covered_caps}`")
    print(f"- Secondary capability 状态：`{ctx.secondary_note}`")
    print(f"- Control map 之外能力：`{ctx.extra_caps}`")
    print(f"- 是否允许修改文件：`{edit_permission}`")


def print_manifest_counts(entry: ManifestEntry) -> None:
    print(
        "- Manifest 计数："
        f"文档 `{len(entry.exact_docs)}` 个，"
        f"现有代码 `{len(entry.existing_code)}` 项，"
        f"预期新增路径 `{len(entry.expected_new_paths)}` 项，"
        f"禁止触碰路径 `{len(entry.forbidden_touches)}` 项，"
        f"验证命令 `{len(entry.validation)}` 个"
    )


def print_copy_start_steps(task: TaskFile, entry: ManifestEntry) -> None:
    print_start_steps_header()
    print(f"1. 读取 task 文件：`{task.path}`")
    print_common_start_steps(entry)
    print("10. 逐个读取该章节下的 `Exact Docs`。")
    print("11. 逐个读取当前存在的 `Existing Code`。")
    print("12. 确认改动只会落在 `Expected New Paths`。")
    print("13. 确认不会触碰 `Forbidden Touches`。")
    print("14. 若风险等级为 High 或 Mission-Critical，先给出风险、验证和回滚思路；若自动执行器已注入静默授权，则记录后直接继续。")
    print()


def print_verify_start_steps(task: TaskFile, entry: ManifestEntry) -> None:
    print_start_steps_header()
    print(f"1. 读取 task 文件：`{task.path}`")
    print_verify_common_start_steps(entry)
    print("10. 逐个读取该章节下的 `Exact Docs`。")
    print("11. 逐个读取该章节下当前存在的 `Existing Code`。")
    print("12. 检查 `Expected New Paths` 是否已按任务完成标准落地；缺失即记录证据。")
    print("13. 检查 `Forbidden Touches` 是否被违规修改。")
    print("14. 基于 task 文件中的核对清单、完成标准、工程质量规则和 validation-driver 逐项验收。")
    print()


def print_start_steps_header() -> None:
    print("## 开始前必须按顺序完成")
    print()


def print_common_start_steps(entry: ManifestEntry) -> None:
    print(f"2. 读取共享规则：`{AUDIT_RULES}`")
    print(f"3. 读取任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"4. 读取工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"5. 读取编码规范：`{CODING_STANDARDS}`")
    print(f"6. 读取 repo-local skill 路径说明：`{SKILL_SOURCE_ROOT}`；不要读取 `/Users/as/.codex/skills-src/...`。")
    print(f"7. 读取依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"8. 读取 phase manifest：`{entry.manifest_path}`")
    print(f"9. 在 manifest 中定位章节：`## {entry.label}`")


def print_verify_common_start_steps(entry: ManifestEntry) -> None:
    print(f"2. 读取共享规则：`{AUDIT_RULES}`")
    print(f"3. 读取任务切片规则：`{TASK_SLICING_RULES}`")
    print(f"4. 读取工程质量规则：`{ENGINEERING_QUALITY_RULES}`")
    print(f"5. 读取编码规范：`{CODING_STANDARDS}`")
    print(f"6. 读取 validation-driver：`{VALIDATION_DRIVER_SKILL}`；不要读取 `/Users/as/.codex/skills-src/...`。")
    print(f"7. 读取依赖关系：`{DEPENDENCY_GRAPH}`")
    print(f"8. 读取 phase manifest：`{entry.manifest_path}`")
    print(f"9. 在 manifest 中定位章节：`## {entry.label}`")


def print_task_requirement_sections(task: TaskFile, ctx: PromptContext, checklist_title: str) -> None:
    print("## 本次任务标题")
    print()
    print(f"- {task.title}")
    print_named_section(checklist_title, ctx.checklist)
    print_named_section("必须满足的完成标准", ctx.completion)
    print_named_section("任务要求的验证", ctx.validation)


def print_named_section(title: str, body: str) -> None:
    print()
    print(f"## {title}")
    print()
    print(body)


def print_copy_body(task: TaskFile, entry: ManifestEntry, ctx: PromptContext) -> None:
    print_shared_docs(include_validation=False)
    print("## 任务正文")
    print()
    print(ctx.task_text.strip())
    print()
    print("## Manifest")
    print()
    print(entry.raw)
    print()
    print_execution_requirements(ctx.detail_kind)
    print_execution_report_format()


def print_verify_body(entry: ManifestEntry, ctx: PromptContext) -> None:
    print("## Manifest")
    print()
    print(entry.raw)
    print()
    print_shared_docs(include_validation=True)
    print_verify_principles()
    print_verify_checks()
    print_verify_runtime_evidence_note()
    print_verify_fast_full_gate_note()
    print_verify_output_format()
    print_verify_forbidden()


def print_shared_docs(include_validation: bool) -> None:
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
    print_repo_local_skill_paths()
    if include_validation:
        print_validation_driver_reference()


def print_execution_requirements(detail_kind: str) -> None:
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
    print("- 验证边界以本 task 的 `Validation` 为上限；普通 atomic Core task 只运行 `./dev check task <label>`，不得自行升级到 `cargo test --workspace`、`cargo clippy --all-targets --all-features`、`./dev check core` 或 `./dev check all`。")
    print("- 只有 Core integration verify、Mission-Critical 文件安全/DB/staging/recovery/sync/import/migration/reindex 边界、stage/foundation closeout、release，或 manifest 明确要求 broad gate 时，才允许运行全量或宽门禁。")
    print("- 若 `./dev check task <label>` 报缺少 targeted test mapping，应把它作为验证映射缺口处理；不要用 `cargo test --workspace` 兜底，除非人工显式设置 `AREAMATRIX_TASK_CHECK_FULL_FALLBACK=1`。")
    print()


def print_execution_report_format() -> None:
    print("## 完成后必须输出")
    print()
    print("一、执行结论")
    print()
    print("- 已完成")
    print("  或")
    print("- 未完成")
    print_report_section("二、执行范围", ["单任务", "修改文件清单"])
    print_report_section("三、完成情况", ["核对清单逐项结果", "完成标准逐项结果", "是否触碰 Forbidden Touches"])
    print_report_section(
        "四、工程质量",
        ["代码结构与逻辑是否清晰", "注释 / rustdoc / 文档同步情况", "错误处理与边界处理情况", "是否存在占位、硬编码、mock-only 或一次性实现"],
    )
    print_report_section("五、验证情况", ["跑了哪些验证", "哪些通过", "哪些失败", "哪些无法运行及原因"])
    print_report_section("六、风险与后续", ["剩余风险", "建议下一个任务"])


def print_report_section(title: str, bullets: list[str]) -> None:
    print()
    print(title)
    print()
    for bullet in bullets:
        print(f"- {bullet}")


def print_verify_principles() -> None:
    print("## 验收原则")
    print()
    for item in verify_principles():
        print(f"- {item}")
    print()


def verify_principles() -> list[str]:
    return [
        "无法证明通过，就判定不通过。",
        "不接受“看起来差不多”。",
        "不接受只看 diff；必须回到 task、manifest、实际文件三者交叉验收。",
        "文档仍然是 SSOT。",
        "不接受 UI 占位、接口空壳、链路未打通的伪完成。",
        "`Existing Code` 为 None 不等于无需验收；应检查 `Expected New Paths` 是否已被真实实现。",
        "已存在 capability specs 的任务必须交叉验收 UX 页面、Core 能力规格和对应 control map；真实闭环仍用 mock 时判定不通过。",
        "page-feature task 只验收一个 `S* + C*` 功能点；page integration task 必须覆盖 control map 中该页面声明的全部 Core 能力。",
        "多能力页面缺少 page integration verify 或缺任何 page-feature task 时，默认不通过。",
        "任何高风险边界缺少测试或证据时，默认不通过。",
        "代码只满足单次运行、缺少可维护结构、错误处理、注释或必要测试时，默认不通过。",
        "严重违反 `docs/development/coding-standards.md` 的实现不能判定为完成。",
        "可以运行只读验证或测试命令；不得运行会重写 repo-tracked 文件的 formatter、codegen 或修复命令。",
    ]


def print_verify_checks() -> None:
    print("## 你必须检查")
    print()
    for item in verify_checks():
        print(item)
    print()


def print_verify_runtime_evidence_note() -> None:
    print("## Task-loop 收口证据时序")
    print()
    print("- 当 verify-ready 由 `./task-loop` 调用时，本验收发生在 runner 写入 `completed` progress、summary 和 Git checkpoint 之前。")
    print("- 完整任务流程是：copy-ready 实现 -> task-scoped check 验证实现证据 -> verify-ready 只读验收 -> `VERIFY_RESULT: PASS` 后 runner 才写 completed progress、summary 和 Git checkpoint。")
    print("- 不得仅因为 `progress.json` 仍是 `in_progress`、新增文件尚未 `git add`、或 `git_checkpoint_status` 尚未写入而判定不通过。")
    print("- 这些 runner 收口证据会在本验收输出 `VERIFY_RESULT: PASS` 后由 task-loop 继续写入；若收口失败，应归因到 runner checkpoint 阶段。")
    print("- 仍需严格阻断与本 task 无关、危险或无法解释的脏改动，以及 Forbidden Touches、验证失败、代码质量、安全、隐私、依赖、CI 或 review blocker。")
    print()


def print_verify_fast_full_gate_note() -> None:
    print("## Task-scoped 验证分层")
    print()
    print("- 普通 atomic Core task 的完成门禁是 `./dev check task <label>`，默认只跑 prompt doctor、diff check 和该能力映射的精确 Rust test target。")
    print("- Core capability integration verify 会在精确 Rust test target 之外加跑 Core quality gate：`cargo fmt --all -- --check` 和 `cargo clippy --all-targets --all-features -- -D warnings`。")
    print("- Mission-Critical 且触碰用户文件、DB、staging、recovery、sync、import、migration、reindex 等边界时，`./dev check task <label>` 会升级到 Core quality gate。")
    print("- Stage/foundation closeout、release 或 manifest 显式要求 broad gate 时才使用 `./dev check all`。非 stage task 不应把 `./dev check all` 当默认验收命令。")
    print("- 若 Core task 没有 targeted test mapping，应判定为验证映射缺口；不要静默退回 `cargo test --workspace`，除非人工显式设置 emergency fallback。")
    print()


def verify_checks() -> list[str]:
    return [
        "1. 是否真的按 manifest 做了逐文件覆盖，而不是只做了局部。",
        "2. task 的核对清单是否逐项满足。",
        "3. task 的完成标准是否逐项满足。",
        "4. 是否仍存在文档有而代码无、代码有而文档无、链路未打通、验证缺失等问题。",
        "5. 工程质量是否达到长期维护标准，而不是单次运行实例。",
        "6. 当前仓库状态是否足以把该 task 判定为完成。",
    ]


def print_verify_output_format() -> None:
    print("## 最后必须按这个格式输出")
    print()
    print_verify_result_section()
    print_report_section("二、验收范围", ["单任务", "对应文件路径"])
    print_report_section("三、完成度摘要", ["已覆盖项数", "未覆盖项数", "通过项数", "不通过项数", "阻塞项数"])
    print_report_section("四、逐项验收结果", ["项目", "结果：通过 / 不通过", "证据", "涉及文件"])
    print_report_section(
        "五、工程质量验收",
        ["代码结构与逻辑：通过 / 不通过，证据", "注释 / rustdoc / 文档同步：通过 / 不通过，证据", "错误处理与边界处理：通过 / 不通过，证据", "测试与验证覆盖：通过 / 不通过，证据", "占位、硬编码、mock-only、一次性实现检查：通过 / 不通过，证据"],
    )
    print_report_section("六、阻塞项", ["若有问题，逐条列出 P0/P1 标题、说明、绝对路径、行号、为什么导致不通过", "如果没有，明确写“未发现阻塞项”"])
    print_report_section("七、验证情况", ["跑了哪些验证", "哪些通过", "哪些失败", "哪些缺失"])
    print_final_judgement_section()


def print_verify_result_section() -> None:
    print("一、验收结论")
    print()
    print("- 通过")
    print("  或")
    print("- 不通过")


def print_final_judgement_section() -> None:
    print()
    print("八、最终判定说明")
    print()
    print("- 本次执行已达到验收标准。")
    print("  或")
    print("- 本次执行尚未达到验收标准，不能视为完成。")
    print()


def print_verify_forbidden() -> None:
    print("## 禁止事项")
    print()
    for item in ["禁止边验收边修。", "禁止因为已经做了很多就放宽标准。", "禁止把“可后续优化”包装成通过。", "禁止省略证据。", "禁止给模糊结论。"]:
        print(f"- {item}")


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
