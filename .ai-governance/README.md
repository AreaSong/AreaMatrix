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

## Live 主线保护

AreaMatrix v1 阶段唯一 live execution 主线是：

```text
AGENTS.md / .ai-governance
-> workflow/ planning gate
-> tasks/prompts/** live queue
-> ./dev / ./task-loop
-> repo-local skills
```

- `workflow/` 只负责讨论、规划、预览和 promotion gate；通过明确 apply 前不得直接写入 live `tasks/prompts/**`。
- `tasks/backlog/**` 只记录规划、评估和治理排期，不进入 `./task-loop`，不写 `progress.json`，不替代 live queue。
- Codex Automations、Cloud、Worktrees、Vibe-Skills、SDK、app-server、remote-control 只能作为候选能力或未来评估项；v1 live queue 阶段不得接管主线。
- 不创建第二套 runner、progress、queue 或 promotion 机制；任何外部能力接入必须先通过 [外部能力接入门禁](workflows/external-capability-admission.md)，证明不会改变上述主线和源事实层级。

## 目录结构

- `core/agent-principles.md`：通用协作、语言、验证和完成门禁。
- `project/areamatrix-rules.md`：AreaMatrix 项目结构、源事实和关键不变量。
- `workflows/prompt-task-runtime.md`：Quick / Change / Mission-Critical 任务运行方式。
- `workflows/external-capability-admission.md`：Vibe-Skills、Codex 官方能力、插件、MCP、subagent pattern 等外部能力的接入门禁。
- `workflows/subagent-boundaries.md`：Codex subagents 的只读探索、写入实现、live runner 禁区和主 agent 复核责任。

## 参考入口

- 根规则：[../AGENTS.md](../AGENTS.md)
- Codex 材料：[../.codex/README.md](../.codex/README.md)
- Prompt 任务库：[../tasks/prompts/README.md](../tasks/prompts/README.md)
- 代码评审：[../CODE_REVIEW.md](../CODE_REVIEW.md)
- 安全政策：[../SECURITY.md](../SECURITY.md)
- CI 治理：[../docs/development/ci-governance.md](../docs/development/ci-governance.md)
