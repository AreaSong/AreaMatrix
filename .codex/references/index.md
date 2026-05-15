# Codex References Index

Codex 在 AreaMatrix 中处理任务时，按以下顺序定位上下文：

1. 根规则：[../../AGENTS.md](../../AGENTS.md)
2. AI 治理：[../../.ai-governance/README.md](../../.ai-governance/README.md)
3. 文档导航：[../../docs/README.md](../../docs/README.md)
4. Prompt 任务库：[../../tasks/prompts/README.md](../../tasks/prompts/README.md)
5. Repo-local skills：[../skills-src/README.md](../skills-src/README.md)

## 常用文档

- Codex 工作流与工具：`.codex/references/codex-workflow-and-tools.md`
- Completion evidence checklist：`.codex/references/completion-evidence-checklist.md`
- Debugging / failure attribution runbook：`.codex/references/debugging-failure-attribution-runbook.md`
- Planning handoff runbook：`.codex/references/planning-handoff-runbook.md`
- Review and threat model runbook：`.codex/references/review-and-threat-model-runbook.md`
- Codex hooks guardrail runbook：`.codex/references/hooks-guardrail-runbook.md`
- Codex subagent boundaries runbook：`.codex/references/subagent-boundaries-runbook.md`
- Computer Use macOS UI smoke runbook：`.codex/references/computer-use-macos-ui-smoke-runbook.md`
- Vibe-Skills 横向能力筛选矩阵：`.codex/references/vibe-skills-capability-screening.md`
- 外部能力接入门禁：`.ai-governance/workflows/external-capability-admission.md`
- 架构总览：`docs/architecture/overview.md`
- 技术栈：`docs/architecture/tech-stack.md`
- Core API：`docs/api/core-api.md`
- 构建与运行：`docs/development/build.md`
- 测试策略：`docs/development/testing.md`
- 编码规范：`docs/development/coding-standards.md`
- 代码评审：`CODE_REVIEW.md`
- 依赖与供应链：`docs/development/dependency-policy.md`
- CI 治理：`docs/development/ci-governance.md`
- Prompt 工程质量门禁：`tasks/prompts/_shared/engineering-quality-rules.md`
- Stage 1 MVP：`docs/roadmap/stage-1-mvp.md`
- 总路线图：`docs/roadmap/milestones.md`

## Repo-local Skills

- `areamatrix-task-loop`：静默任务流水线启动、监控与恢复。
- `areamatrix-git-checkpoint`：PASS task 的 commit / push / Git 恢复策略。
- `areamatrix-enterprise-governance`：企业级 review、安全、依赖、CI 与 CODEOWNERS 治理。
- `areamatrix-validation-driver`：按改动范围选择最小充分验证集。
- `areamatrix-doc-sync`：检查 docs / API / UDL / prompt manifest 漂移。
- `areamatrix-file-safety`：用户文件、`.areamatrix/` 元数据与恢复边界。
- `areamatrix-workflow-planning`：v* 版本 planning gate、middle-layer handoff 和 prompt 生成前门禁。

## Health Checks

- Skills：`./dev check skills`
- Governance：`./dev check governance`
- Prompt runner：`python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- Task loop full check：`./task-loop check`
- Task loop：`./task-loop status`
- Task loop reset：`./task-loop reset-progress`
- Task loop Git：默认 `GIT_CHECKPOINT=commit`，上传时显式 `GIT_CHECKPOINT=push`
