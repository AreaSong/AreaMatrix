# Codex References Index

Codex 在 AreaMatrix 中处理任务时，按以下顺序定位上下文：

1. 根规则：[../../AGENTS.md](../../AGENTS.md)
2. AI 治理：[../../.ai-governance/README.md](../../.ai-governance/README.md)
3. 文档导航：[../../docs/README.md](../../docs/README.md)
4. Workflow 边界：[../../workflow/AGENTS.md](../../workflow/AGENTS.md) 与 [../../workflow/README.md](../../workflow/README.md)
5. Lightweight tasks：[../../tasks/README.md](../../tasks/README.md)
6. Residual ledger：[../../workflow/residuals/README.md](../../workflow/residuals/README.md)
7. v1 历史执行队列：[../../workflow/versions/v1-mvp/execution/README.md](../../workflow/versions/v1-mvp/execution/README.md)
8. Repo-local skills：[../skills-src/README.md](../skills-src/README.md)

## 日常入口

- Codex operating layer playbook：`.codex/references/codex-operating-layer-playbook.md`
- Completion evidence checklist：`.codex/references/completion-evidence-checklist.md`
- Debugging / failure attribution runbook：`.codex/references/debugging-failure-attribution-runbook.md`
- Planning handoff runbook：`.codex/references/planning-handoff-runbook.md`
- Review and threat model runbook：`.codex/references/review-and-threat-model-runbook.md`

## 专项 Runbooks

- Codex hooks guardrail runbook：`.codex/references/hooks-guardrail-runbook.md`
- Codex subagent boundaries runbook：`.codex/references/subagent-boundaries-runbook.md`
- Codex Automations / Cloud / Worktrees gate：`.codex/references/codex-automations-cloud-worktrees-gate.md`
- Computer Use macOS UI smoke runbook：`.codex/references/computer-use-macos-ui-smoke-runbook.md`
- Browser / Chrome / Computer Use UI evidence templates：`.codex/references/ui-evidence-tool-templates.md`

## 能力盘点与候选记录

- Codex 工作流与工具 inventory：`.codex/references/codex-workflow-and-tools.md`
- Codex 工作层 backlog inventory：`tasks/backlog/codex-operating-layer-inventory.md`
- Vibe-Skills 横向能力筛选矩阵：`.codex/references/vibe-skills-capability-screening.md`
- Vibe 专业 skill 触发矩阵：`.codex/references/vibe-professional-skill-trigger-matrix.md`
- 外部能力接入门禁：`.ai-governance/workflows/external-capability-admission.md`
- Residual ledger：`workflow/residuals/README.md`
- v1-mvp residuals：`workflow/versions/v1-mvp/residuals/README.md`
- v2 planning bootstrap：`workflow/README.md`、`workflow/versions/README.md`、`.codex/skills-src/areamatrix-workflow-planning/references/version-lifecycle.md`
- Lightweight task boundaries：`tasks/README.md`、`tasks/indexes/residuals.md`

## 项目源事实快捷入口

- 架构总览：`docs/architecture/overview.md`
- 技术栈：`docs/architecture/tech-stack.md`
- Core API：`docs/api/core-api.md`
- 构建与运行：`docs/development/build.md`
- 测试策略：`docs/development/testing.md`
- 编码规范：`docs/development/coding-standards.md`
- 代码评审：`CODE_REVIEW.md`
- 依赖与供应链：`docs/development/dependency-policy.md`
- CI 治理：`docs/development/ci-governance.md`
- Prompt 工程质量门禁：`workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md`
- v1 历史源材料：`workflow/versions/v1-mvp/source-docs/`
- 总路线图：`docs/roadmap/version-roadmap.md`

## Repo-local Skills

- `areamatrix-task-loop`：静默任务流水线启动、监控与恢复。
- `areamatrix-git-checkpoint`：PASS task 的 commit / push / Git 恢复策略。
- `areamatrix-enterprise-governance`：企业级 review、安全、依赖、CI 与 CODEOWNERS 治理。
- `areamatrix-validation-driver`：按改动范围选择最小充分验证集。
- `areamatrix-doc-sync`：检查 docs / API / UDL / prompt manifest 漂移。
- `areamatrix-file-safety`：用户文件、`.areamatrix/` 元数据与恢复边界。
- `areamatrix-workflow-planning`：v* 版本 planning gate、middle-layer handoff 和 prompt 生成前门禁。
- `areamatrix-residual-ledger`：release blocker、accepted exception、historical reference、template-only 与 task-facing residual 索引。

## Health Checks

- Skills：`./dev check skills`
- Quality smoke：`./dev check quality`
- Long-term wording audit：`./dev check wording`
- Governance：`./dev check governance`
- Prompt runner：`python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py doctor`
- Task loop full check：`./task-loop check`
- Task loop：`./task-loop status`
- Task loop reset：`./task-loop reset-progress`
- Task loop Git：默认 `GIT_CHECKPOINT=commit`，上传时显式 `GIT_CHECKPOINT=push`
