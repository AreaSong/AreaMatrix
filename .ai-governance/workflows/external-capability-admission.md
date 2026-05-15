# External Capability Admission Gate

> 本门禁用于判断 Vibe-Skills、Codex 官方新能力、插件、MCP、subagent pattern 或其他外部 workflow 是否可以进入 AreaMatrix。

## 基线结论

- 目录存在不等于启用。任何外部目录、skill、plugin、workflow、runtime 或 prompt 包即使已经在本机存在，也不能自动参与 AreaMatrix 路由、任务执行或验收。
- 外部 runtime 不得成为 AreaMatrix canonical runtime。AreaMatrix v1 live execution 仍以 `./dev + ./task-loop + tasks/prompts/**` 为唯一主线。
- 外部资料只能先作为候选能力、上游语义证据或治理参考；是否吸收由本门禁记录判断。
- 涉及 OpenAI / Codex 能力语义时，优先用 OpenAI 官方文档核对。Codex 官方当前建议的接入顺序是先 `AGENTS.md`，再 hooks / linters，已有可复用 workflow 才考虑 plugin / skill，需要外部系统时再接 MCP，适合委派时再考虑 subagents。

## Source Of Truth

| 范围 | Canonical source of truth | 外部资料角色 |
|---|---|---|
| 产品、架构、API、UX | `docs/**`，其中 Core API 以 `docs/api/core-api.md` 为准 | 只能提供参考，不能覆盖产品定义 |
| AI 协作规则、风险边界、完成门禁 | `.ai-governance/**` | 可作为规则设计输入，不能成为规则权威 |
| Codex 适配材料、运行参考 | `.codex/references/**`、`.codex/skills-src/**` | 官方文档说明能力语义，但 AreaMatrix 落点仍由本仓库决定 |
| Live task queue | `tasks/prompts/**`、manifest、`tasks/prompts/_shared/progress.json` | 不得直接写入、替代或旁路 |
| 本地执行 runtime | `./dev`、`./task-loop`、repo-local skills | 外部 runtime 只能作为候选或未来评估项 |
| Vibe-Skills | `/Users/as/Ai-Project/project/Vibe-Skills/**` | 候选能力池和治理参考，不是 AreaMatrix canonical runtime |

## Admission Checklist

每个候选能力必须先形成一条 admission record。无法填写任一必填项时，默认不启用。

| 判定项 | 必须回答 | 合格标准 | 不合格时结论 |
|---|---|---|---|
| AreaMatrix 缺口 | 它解决什么具体缺口？ | 能指向当前 docs、workflow、skill、validation 或 task-loop 痛点 | `只参考` 或 `拒绝` |
| 去重关系 | 是否与现有 AreaMatrix skill / rule / workflow 重复？ | 明确 `dedup_with`，优先补现有 owner，不新增同名能力 | 重复率高且无剩余价值则 `拒绝` |
| Source of truth | 本地权威是谁？上游只证明什么？ | 明确本仓库落点和上游证据边界 | 说不清权威则 `拒绝` |
| 触发条件 | 何时触发？是否 implicit？ | 有关键词、任务类型、风险等级、explicit-only 或 advisory 规则 | 目录存在即触发则 `拒绝` |
| Live 主线影响 | 是否影响 `./task-loop`、`tasks/prompts/**`、progress、checkpoint 或 promotion？ | 默认不影响；若影响，必须先过 `workflow/` planning gate 和人工确认 | 绕过主线则 `拒绝` |
| 用户文件安全 | 是否触碰用户文件、`.areamatrix/`、DB、staging、FSEvents、iCloud、隐私或远程调用？ | 命中高风险边界时先说明影响、验证、回滚并等待确认 | 无安全边界则 `暂缓` 或 `拒绝` |
| 验证方式 | 如何证明接入有效且没有破坏主线？ | 至少有 `./dev check governance`、`./dev check skills`、prompt doctor 和路径级 diff check；按影响面补充验证 | 无验证路径则 `暂缓` |
| Owner / 落点 | 谁维护？写到哪里？ | 规则进 `.ai-governance/**`，Codex 参考进 `.codex/references/**`，repo skill 进 `.codex/skills-src/**`，候选记录进 `tasks/backlog/**` | owner 不明则 `暂缓` |
| 结论 | 吸收、暂缓、只参考、拒绝 | 结论与证据一致，可复查 | 无结论则不得启用 |

## 四类结论

| 结论 | 使用条件 | 允许落点 | 禁止事项 |
|---|---|---|---|
| 吸收 | 补足明确缺口；不重复现有 owner；可验证；不改变 live 主线 | `.ai-governance/**`、`.codex/references/**`、`.codex/skills-src/**` 或经批准的 `workflow/**` | 不原样搬运外部 runtime，不直接写 `tasks/prompts/**` |
| 暂缓 | 有潜在价值，但 owner、触发、验证或安全边界未闭合 | `tasks/backlog/**` 候选记录 | 不启用，不进入 implicit trigger |
| 只参考 | 主要提供 wording、taxonomy、case、checklist 或上游设计启发 | `.codex/references/**` 或 backlog note | 不创建新 skill，不进入默认工作流 |
| 拒绝 | 与主线冲突、重复率过高、需要第二 runtime / supervisor、无法说明 source of truth 或会危及用户文件安全 | 可在 backlog 记录拒绝原因 | 不安装、不链接、不保留为可触发能力 |

## 候选记录模板

```md
### <candidate-id>

- Upstream source:
- AreaMatrix gap:
- Dedup with:
- Local source of truth:
- Trigger condition:
- Live mainline impact:
- User-file / privacy / remote-call impact:
- Verification:
- Owner / landing:
- Decision: 吸收 | 暂缓 | 只参考 | 拒绝
- Evidence:
```

## 启用规则

1. 候选能力先进入 `tasks/backlog/**` 或 `.codex/references/**`，状态为候选。
2. 如果只是参考材料，不得出现在 repo-local skill discovery 路径中。
3. 如果要成为 repo-local skill，先确认不会与现有 `.codex/skills-src/**` owner 重复，再更新 `.codex/skills-src/<skill>/SKILL.md` 或创建经过批准的新 skill。
4. 如果要影响 `workflow/**` 或 `tasks/prompts/**`，先走 `workflow/` discussion / planning / promotion gate，不得从外部仓库直接 promotion。
5. 如果要影响 `./dev`、`./task-loop`、progress、checkpoint 或用户文件安全，按高风险变更处理，先说明影响、风险、验证和回滚，再等待明确确认。
6. Subagent pattern 只能作为当前任务内的并行协作方式或候选 role taxonomy；不得变成默认隐式执行器、第二 runner 或绕过主 agent 复核的验收机制。具体边界见 [Subagent Boundaries](subagent-boundaries.md)。

## 最小验证

外部能力 admission gate 或相关索引变更至少运行：

```bash
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

如果候选能力改变了更具体的实现面，还必须按变更路径追加 Rust、Swift、docs、workflow 或 task-loop 相关检查。
