# Codex References Index

Codex 在 AreaMatrix 中处理任务时，按以下顺序定位上下文：

1. 根规则：[../../AGENTS.md](../../AGENTS.md)
2. AI 治理：[../../.ai-governance/README.md](../../.ai-governance/README.md)
3. 文档导航：[../../docs/README.md](../../docs/README.md)
4. Prompt 任务库：[../../tasks/prompts/README.md](../../tasks/prompts/README.md)
5. Repo-local skills：[../skills-src/README.md](../skills-src/README.md)

## 常用文档

- 架构总览：`docs/architecture/overview.md`
- 技术栈：`docs/architecture/tech-stack.md`
- Core API：`docs/api/core-api.md`
- 构建与运行：`docs/development/build.md`
- 测试策略：`docs/development/testing.md`
- 编码规范：`docs/development/coding-standards.md`
- Prompt 工程质量门禁：`tasks/prompts/_shared/engineering-quality-rules.md`
- Stage 1 MVP：`docs/roadmap/stage-1-mvp.md`
- 总路线图：`docs/roadmap/milestones.md`

## Repo-local Skills

- `areamatrix-task-loop`：静默任务流水线启动、监控与恢复。
- `areamatrix-validation-driver`：按改动范围选择最小充分验证集。
- `areamatrix-doc-sync`：检查 docs / API / UDL / prompt manifest 漂移。
- `areamatrix-file-safety`：用户文件、`.areamatrix/` 元数据与恢复边界。

## Health Checks

- Skills：`bash scripts/check-skills.sh`
- Prompt runner：`python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- Task loop：`bash scripts/run_area_matrix_task_pipeline.sh --status`
- Task loop reset：`bash scripts/run_area_matrix_task_pipeline.sh --reset-progress`
