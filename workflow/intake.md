# AreaMatrix Workflow Intake

本文定义新需求、版本、重构或优化进入 workflow 前的提问入口。它不是产品文档，不定义产品行为；产品源事实仍然是 `docs/`。旧 `scripts/question.md` 的 AreaFlow 愿景资料已经迁入 [`references/areaflow-vision.md`](references/areaflow-vision.md)。

## Position

`intake` 只负责把模糊意图整理成可进入 discussion gate 的输入，不直接写 `changes/`、`plans/`、`drafts/`、`queue/`、promotion preview 或 `workflow/versions/<version>/execution/**`。

标准流转：

```text
intake
-> docs scope
-> workflow/versions/<version>/discussion
-> middle-layer
-> changes
-> plans
-> drafts
-> queue
-> promotion preview
-> execution
```

## Intake Questions

### 1. Intent

- 这次想解决什么问题？
- 为什么现在要做？
- 这是新版本、大功能、重构、优化，还是一个小任务？
- 成功后用户或维护者能观察到什么变化？

### 2. Source Of Truth

- 哪些 `docs/**` 文件是产品、架构、API、UX 或开发规范源事实？
- 是否需要先补 `docs/`，再进入 workflow？
- 是否涉及 `.ai-governance/**` 协作规则、风险边界或完成门禁？
- 是否只是历史资料、愿景资料或 backlog，不应该进入当前版本 scope？

### 3. Version And Scope

- 目标版本是现有 `v2`，还是需要创建新的 `workflow/versions/<version>/`？
- 哪些内容明确在本轮范围内？
- 哪些内容明确不是本轮目标？
- 是否依赖 v1 closeout、release evidence、外部环境或人工决策？

### 4. User Paths And Acceptance

- 主要用户路径是什么？
- 验收边界是什么？
- 哪些行为必须可测试、可观察或可回滚？
- 哪些失败属于 task-scope，哪些属于 repo-wide gate、环境问题或 release blocker？

### 5. Risk Boundaries

- 是否触碰用户原文件、`.areamatrix/` 元数据、DB、migration、staging、reindex、FSEvents/iCloud、隐私、AI 远程调用或权限？
- 是否涉及 Core API、UDL、Swift bridge 或跨平台行为？
- 是否需要先说明影响、风险、验证和回滚，再等待确认？
- 哪些路径在 discussion 阶段禁止写入？

### 6. Handoff Shape

- discussion 应写入哪个 `workflow/versions/<version>/discussion/`？
- `docs-discussion.md` 需要记录哪些 Exact Docs、争议点、非目标和验收边界？
- `middle-layer-discussion.md` 需要说明哪些 changes、plans、drafts、queue、promotion 承接关系？
- `decisions.yaml` 里的 open questions、blockers、risk boundaries 是否足够机器检查？

## Routing

| Intake Result | Next Step |
| --- | --- |
| 小而明确、低风险、无需版本链路 | 作为普通局部任务处理；不创建 workflow execution |
| 大功能、版本、重构或优化 | 进入 `workflow/versions/<version>/discussion/` |
| 产品语义不清 | 先补或讨论 `docs/**` |
| 只有愿景、事故复盘或未来产品想法 | 放入 `workflow/references/**` 或 `tasks/backlog/**` |
| 可执行任务候选但尚未批准 | 进入 plans / drafts / queue，保持 promotion preview，不写 execution |
| 已通过 approval 和 live mapping | 才能 promote 到 `workflow/versions/<version>/execution/**` |

## Guardrails

- 不从 intake 直接生成 copy-ready / verify-ready。
- 不从 intake 直接写 `workflow/versions/<version>/execution/**`。
- 不把 `workflow/references/areaflow-vision.md` 当作 AreaMatrix 当前产品源事实。
- 不把 `workflow/versions/v1-mvp/source-docs/**` 的历史 Stage 2/3/4 名称当作未来 v2/v3/v4 范围。
- 不让 backlog prompt 包写 progress、checkpoint、run summary、runner lock 或 execution `progress.json`。
- 缺少 Exact Docs、owner / landing、验证命令或风险边界时，保持 `blocked` 或 `not-ready`。

## Validation

修改 intake 或 discussion 规则后运行：

```bash
./dev workflow doctor
./dev workflow check-template
./dev check governance
./dev check diff
```
