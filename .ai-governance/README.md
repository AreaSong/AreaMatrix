# AreaMatrix AI Governance Source of Truth

本目录是 AreaMatrix 在 AI 协作场景下的统一规则源事实。

## 目标

- 只维护一份项目级协作语义。
- 让 Codex、Cursor 或其他工具可以按需投影适配层，而不让规则长期漂移。
- 把执行约束、风险边界和完成门禁沉淀在仓库内，而不是散落在个人偏好里。

## 维护原则

1. 项目语义先改这里，再同步到 `.codex/` 或其他工具适配层。
2. `.codex/` 只承载 Codex 运行材料，不作为业务规则权威来源。
3. `tasks/prompts/` 是任务执行边界，不替代长期治理规则。
4. 高风险边界必须显式记录，不能只靠临场判断。
5. 企业治理规则先落到 `CODE_REVIEW.md`、`SECURITY.md` 和 `docs/development/`，再同步到 `.codex/` skills 或 prompt 门禁。

## 目录结构

- `core/agent-principles.md`：通用协作、语言、验证和完成门禁。
- `project/areamatrix-rules.md`：AreaMatrix 项目结构、源事实和关键不变量。
- `workflows/prompt-task-runtime.md`：Quick / Change / Mission-Critical 任务运行方式。

## 参考入口

- 根规则：[../AGENTS.md](../AGENTS.md)
- Codex 材料：[../.codex/README.md](../.codex/README.md)
- Prompt 任务库：[../tasks/prompts/README.md](../tasks/prompts/README.md)
- 代码评审：[../CODE_REVIEW.md](../CODE_REVIEW.md)
- 安全政策：[../SECURITY.md](../SECURITY.md)
- CI 治理：[../docs/development/ci-governance.md](../docs/development/ci-governance.md)
