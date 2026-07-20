---
name: areamatrix-closeout
description: Runs the AreaMatrix closeout routine after a feature or fix—scope-matched validation, doc-sync drift checks, .cursor/plans archiving, canvas snapshot sync, and a 30-second AAR routed to the existing skill-entry threshold. Use when finishing implementation, before claiming done, or when a stop hook requests closeout. Chinese cues include 完成了 / 搞定了 / 收个尾 / 合完了. Execute silently without asking the user to type /closeout.
---

# Closeout

## Ownership first

先用 `git status` 确认改动归属：只对本次会话产生的改动收口。非本次会话遗留的 dirty 文件不纳入，必要时向用户澄清归属（stop hook 对遗留脏改动存在已知误报）。

## Must

1. 按改动面选择最小充分验证（语义见 `.agents/skills/areamatrix-validation-driver/SKILL.md`）：
   - Rust core：`cargo fmt --all -- --check`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --workspace`。
   - macOS app：`xcodebuild` 构建，按需 `./dev test macos`。
   - workflow 体系：`./dev workflow doctor`。
   - 长期源事实文本（`docs/**`、README、AGENTS、治理、skill）：`./dev check wording`，按需 `./dev check docs` / `./dev check governance`。
2. 漂移检查按 `.agents/skills/areamatrix-doc-sync/SKILL.md`：docs、Core API / UDL、README、prompt 材料与代码同轮对齐，无「文档说有、代码没有」。
3. 更新 `.cursor/plans/` 步骤状态；对应 plan 全部完成时删除该文件。
4. residual 状态变化 → 先更新权威账本（`workflow/residuals/**` 流程），再同步工作区 canvas `areamatrix-residuals-dashboard.canvas.tsx` 快照；`docs/product/capabilities.md` 变化 → 同步 `areamatrix-capability-map.canvas.tsx` 快照。
5. 命中根 `AGENTS.md` 高风险边界的改动：确认已有影响、验证与回滚说明。

## AAR（30 秒，非琐碎任务必做）

问 4 问：新模式？新坑？缺规则？过时规则？全「否」即结束。
任一「是」→ 按 `.codex/skills-src/README.md` 经验录入门槛（可重复 / 代价高 / 不可见，至少两项）判断；通过则泛化录入对应 owner skill 的 Guardrails 或 References——业务语义进 `.codex/skills-src/areamatrix-*`，Cursor 操作规程进 `.cursor/skills/areamatrix-*`。不新建独立坑点文件。
可跳过：仅格式化、仅注释、行为保持的琐碎改动。

## Do not claim done if

- 未跑与改动面匹配的验证，或验证失败仍汇报完成。
- doc-sync 漂移检查命中但对应文档未改。
- plan 全部完成却未删除。
- residual / 能力状态变化但 canvas 未同步。
- 非琐碎任务跳过 AAR 扫描。

## Silent

不要求用户运行 `/closeout`；自行执行本规程后简短汇报验证结果。
