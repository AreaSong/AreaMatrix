# Vibe-Skills Capability Screening Matrix

> 本文件记录 AreaMatrix 对 `/Users/as/Ai-Project/project/Vibe-Skills` 横向能力的 P2 筛选结论。它是候选能力 admission 记录，不是安装清单，也不是 live workflow。

## 基线结论

- 不安装、不启用、不复制 Vibe-Skills 全量仓库。
- `vibe` / VCO runtime 不进入 AreaMatrix 主线，不创建第二套 requirement / plan / execution / memory surface。
- AreaMatrix v1 live execution 主线仍是：

```text
AGENTS.md / .ai-governance
-> workflow/ planning gate
-> tasks/prompts/** live queue
-> ./dev / ./task-loop
-> repo-local skills
```

- 专业垂直 skills 暂不进入默认工作流，例如科研、金融、法律、图像、视频、ML、数据库或云平台类 skill。未来只有在具体任务明确需要时，才按 `.ai-governance/workflows/external-capability-admission.md` 单项评估。
- 本轮只吸收可复用、可验证、可去冗余的方法价值；不吸收外部 runtime、命令语义、目录布局、自动编排器或工作区记忆机制。

## 读取证据

- AreaMatrix 根规则：`AGENTS.md`
- AI 治理源事实：`.ai-governance/README.md`
- Codex 运行参考：`.codex/references/codex-workflow-and-tools.md`
- 长期优化 backlog：`tasks/backlog/codex-native-area-vibe-optimization.md`
- Vibe-Skills 总览：`/Users/as/Ai-Project/project/Vibe-Skills/README.zh.md`
- Vibe runtime 入口：`/Users/as/Ai-Project/project/Vibe-Skills/SKILL.md`
- Vibe distillation 规则：`/Users/as/Ai-Project/project/Vibe-Skills/references/skill-distillation-rules.md`
- 候选 skill：对应 `core/skills/*/instruction.md` 或 `bundled/skills/*/SKILL.md`

## 快速矩阵

| 候选能力 | 用途 | 与 AreaMatrix 现有能力关系 | 建议结论 | 后续落点 |
|---|---|---|---|---|
| `systematic-debugging` | 失败、Bug、测试破裂、集成异常的根因调查 | 与 AGENTS 调试原则、`areamatrix-validation-driver`、task-loop 失败归因互补 | 吸收到 `.ai-governance` / `.codex/references` 规则 | 后续补调试 runbook 或 validation-driver reference |
| `tdd-guide` | 行为变更的 RED / GREEN / REFACTOR 测试优先方法 | 与 `docs/development/testing.md`、prompt 质量门禁部分重叠，但“生产代码前必须先失败测试”不适合作为全局硬规则 | 只作为参考 | 作为行为变更任务的可选开发姿势，不进默认门禁 |
| `verification-before-completion` | 完成声明前必须有新鲜验证证据 | 与 AGENTS 完成门禁、`areamatrix-validation-driver` 高度一致 | 吸收到 `.ai-governance` / `.codex/references` 规则 | 后续补 completion evidence checklist |
| `code-reviewer` | Review findings first，优先 correctness / regression risk | 与 `CODE_REVIEW.md`、`areamatrix-enterprise-governance` 重叠且互补 | 吸收为 AreaMatrix repo-local skill 补强 | 补强 enterprise-governance 的 review posture，不新增同义 skill |
| `security-threat-model` | 明确 threat model 任务中的资产、边界、攻击路径和缓解措施 | 与 `SECURITY.md`、`areamatrix-file-safety`、`areamatrix-enterprise-governance` 互补 | 吸收为 AreaMatrix repo-local skill 补强 | 补强安全/文件边界 skill；仅 explicit threat-model 触发 |
| `architecture-patterns` | Clean / Hexagonal / DDD 等后端架构模式参考 | AreaMatrix 架构以 `docs/architecture/**` 为源事实；上游偏通用后端和 Python 示例 | 只作为参考 | 架构讨论时作词汇和 checklist 参考，不改架构源事实 |
| `docs-review` | 文档 diff 的风格、清晰度、可读性 review | 与 `areamatrix-doc-sync` 互补，但上游绑定 Metabase style guide，不适合直接套用 | 只作为参考 | 保留“编号化、可行动 feedback”格式启发 |
| `writing-plans` | 把已批准需求转成含精确路径和验证命令的实施计划 | 与 `areamatrix-workflow-planning`、backlog prompt 包、task-label workflow 高度契合 | 吸收为 AreaMatrix repo-local skill 补强 | 补强 workflow-planning 的 handoff-safe plan 要求 |
| `subagent-driven-development` | 独立任务的 fresh subagent + spec review + quality review | 已由 `.ai-governance/workflows/subagent-boundaries.md` 和 subagent runbook 局部吸收；上游“每任务 fresh subagent / 自动 commit”不适合默认主线 | 吸收到 `.ai-governance` / `.codex/references` 规则 | 保留 explicit-only、write set、spec-before-quality；拒绝 Vibe runtime 化 |

## 候选记录

### `systematic-debugging`

- Upstream source: `core/skills/systematic-debugging/instruction.md`、`bundled/skills/systematic-debugging/SKILL.md`
- 用途: 对失败测试、构建错误、集成异常、运行时 Bug 做先复现、再收集证据、再定位边界、最后修复的流程约束。
- 现有关系: AreaMatrix 已要求原因不明 Bug 先复现和收证；`areamatrix-validation-driver` 负责选择验证，task-loop 失败还需要区分 copy / verify / checkpoint / runner gate。
- 建议结论: 吸收到 `.ai-governance` / `.codex/references` 规则。
- 理由: “no fixes before root-cause investigation”和多组件边界证据收集能补强当前失败归因质量；不需要新增同义 skill，也不能变成外部 runtime。
- 后续落点: `.ai-governance/core/agent-principles.md` 的调试规则、`.codex/references/debugging-runbook.md` 或 `areamatrix-validation-driver` reference。

### `tdd-guide`

- Upstream source: `core/skills/tdd-guide/instruction.md`、`bundled/skills/tdd-guide/SKILL.md`
- 用途: 对行为变更用 RED / GREEN / REFACTOR 约束最小实现和边界测试。
- 现有关系: AreaMatrix 是 docs-first + prompt task-first；很多任务来自已批准文档和 manifest，不总是适合先写失败测试再写生产代码。
- 建议结论: 只作为参考。
- 理由: TDD 方法有价值，但上游“no production code before a failing test”若变成全局硬规则，会和文档驱动实现、验收修复、只读 acceptance 模式冲突。
- 后续落点: 行为变更或 bugfix 任务可在任务验证里参考 RED / GREEN / REFACTOR；不进入默认 workflow、不新增 skill。

### `verification-before-completion`

- Upstream source: `bundled/skills/verification-before-completion/SKILL.md`
- 用途: 在声称完成、修复、通过、可提交或 PR-ready 前，要求新鲜、完整、可读的验证输出。
- 现有关系: 与 AGENTS 的“没有验证，不宣称已完成”、`.ai-governance` 完成门禁和 `areamatrix-validation-driver` 完全同向。
- 建议结论: 吸收到 `.ai-governance` / `.codex/references` 规则。
- 理由: 它不是新能力，而是 completion claim 的证据纪律；可直接补强 AreaMatrix 的汇报与验收口径。
- 后续落点: `.ai-governance/core/agent-principles.md`、`.codex/references/codex-workflow-and-tools.md`、`areamatrix-validation-driver/references/validation-matrix.md`。

### `code-reviewer`

- Upstream source: `core/skills/code-reviewer/instruction.md`、`bundled/skills/code-reviewer/SKILL.md`
- 用途: 代码评审时先列 findings，优先 correctness、regression risk、可行动证据。
- 现有关系: AreaMatrix 已有 `CODE_REVIEW.md` 和 `areamatrix-enterprise-governance`；上游内容更像 review posture，而不是独立 owner。
- 建议结论: 吸收为 AreaMatrix repo-local skill 补强。
- 理由: 可加强“review findings first”的输出纪律，但重复创建 `code-reviewer` skill 会和 enterprise-governance 分裂。
- 后续落点: `areamatrix-enterprise-governance` 的触发说明、`CODE_REVIEW.md` 的评审输出格式或 `.codex/references` review runbook。

### `security-threat-model`

- Upstream source: `bundled/skills/security-threat-model/SKILL.md`
- 用途: 明确 threat model 场景下，按资产、入口、信任边界、攻击能力、abuse path、缓解措施输出安全模型。
- 现有关系: AreaMatrix 已有高风险边界、`SECURITY.md`、文件安全 skill 和 enterprise governance；但缺少 explicit threat modeling 的 repo-local 操作姿势。
- 建议结论: 吸收为 AreaMatrix repo-local skill 补强。
- 理由: AreaMatrix 涉及用户文件、DB、staging、隐私和远程调用，威胁建模有长期价值；但必须 explicit-only，不能替代普通 code review，也不能在上下文缺失时跳过用户确认。
- 后续落点: `areamatrix-file-safety` 和 `areamatrix-enterprise-governance` 的安全 review references；若未来反复出现 threat-model 任务，再评估新建专门 repo-local skill。

### `architecture-patterns`

- Upstream source: `bundled/skills/architecture-patterns/SKILL.md`
- 用途: 提供 Clean Architecture、Hexagonal Architecture、DDD 等模式词汇和常见后端分层做法。
- 现有关系: AreaMatrix 的架构源事实是 `docs/architecture/**`、Core API 和 UDL；上游样例偏通用 Python 后端，不直接映射 Rust core + SwiftUI + UniFFI。
- 建议结论: 只作为参考。
- 理由: 可作为架构讨论的概念检查表，但不应让通用模式覆盖 AreaMatrix 已定义的层级、用户文件不变量或平台边界。
- 后续落点: 架构评审时人工参考；除非未来架构文档明确需要，不进入 repo-local skill 或默认门禁。

### `docs-review`

- Upstream source: `bundled/skills/docs-review/SKILL.md`
- 用途: 对文档变更做清晰度、语气、结构、链接和示例 review，并输出编号化问题。
- 现有关系: AreaMatrix 已有 `areamatrix-doc-sync` 负责源事实和漂移检查；上游 docs-review 绑定 Metabase style guide，不适合作为 AreaMatrix 文档风格权威。
- 建议结论: 只作为参考。
- 理由: “编号化、可行动 feedback”值得保留；具体 style guide、英文语气规则和 PR MCP 流程不能直接照搬。
- 后续落点: 若后续需要文档文风 review，可在 `.codex/references` 新增 AreaMatrix docs review runbook；当前不进入默认 workflow。

### `writing-plans`

- Upstream source: `core/skills/writing-plans/instruction.md`、`bundled/skills/writing-plans/SKILL.md`
- 用途: 把已批准需求或设计转成精确文件路径、可执行验证步骤和小步交付计划。
- 现有关系: 与 `areamatrix-workflow-planning`、`workflow/` planning gate、backlog prompt 包和 task-label workflow 完全同向。
- 建议结论: 吸收为 AreaMatrix repo-local skill 补强。
- 理由: “exact file paths + executable verification steps + handoff-safe”能直接提升 AreaMatrix planning artifact 质量；无需新增同义 skill。
- 后续落点: `areamatrix-workflow-planning` 的计划输出要求、`tasks/backlog/**/prompts` 模板、`.codex/references` planning runbook。

### `subagent-driven-development`

- Upstream source: `core/skills/subagent-driven-development/instruction.md`、`bundled/skills/subagent-driven-development/SKILL.md`
- 用途: 对已批准且独立的实施任务使用 fresh subagent，并在每个任务后做 spec compliance review 和 code quality review。
- 现有关系: AreaMatrix 已有 `.ai-governance/workflows/subagent-boundaries.md` 和 `.codex/references/subagent-boundaries-runbook.md`，并且 Codex subagents 在本仓库必须 explicit-only。
- 建议结论: 吸收到 `.ai-governance` / `.codex/references` 规则。
- 理由: 可保留“独立任务、fresh context、spec-before-quality、open issues 不得完成”的方法价值；但上游“每任务 fresh subagent”“implementer commits”“连续自动 review loop”不能进入默认主线。
- 后续落点: 已落到 subagent boundaries 与 runbook；未来只补充 examples，不引入 Vibe 的 runtime / memory / orchestrator。

## 不吸收项

- 不吸收 `vibe`、`vibe-upgrade`、canonical-entry、`.vibeskills/**` artifacts、VCO stage state machine、Vibe memory plane 或 specialist router。
- 不吸收 Vibe 的全量 bundled skills catalog。
- 不吸收专业垂直 skills 到默认 AreaMatrix workflow。后续若出现具体任务，例如科研数据分析、视频处理、图像生成、云平台部署、数据库专项接入，必须单独走 external capability admission gate。
- 不允许 Vibe-Skills 通过 catalog 体量获得 source-of-truth 地位；AreaMatrix 的产品、架构、API、UX、AI 治理和 live queue 源事实不变。

## 最小验证

本筛选记录变更后至少运行：

```bash
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references tasks/backlog
```
