# Workflow Agent Guide

## 定位

- `workflow/` 是大功能、版本、重构和优化的生命周期系统。
- `workflow/versions/<version>/execution/` 是标准化后的版本内执行层，用于承载通过 promotion 的 copy-ready / verify-ready / manifest / progress / checkpoint / reports。
- `workflow/versions/v1-mvp/execution/**` 是 Stage 1 历史执行队列；不得为了视觉整理重写、清空或重置。
- `./task-loop` 只执行 live queue，不负责需求讨论、版本决策或 promotion 审批。

## 标准顺序

新 v* 版本默认遵循：

```text
docs
-> workflow/templates
-> workflow/versions/v*/discussion
-> middle-layer
-> changes
-> plans
-> drafts
-> queue
-> promotion preview
-> execution
-> projection
-> closeout
```

## Discussion Gate

- 新版本进入 `changes/` 前必须先完成 `discussion/` 三件套：
  - `docs-discussion.md`
  - `middle-layer-discussion.md`
  - `decisions.yaml`
- `docs-discussion.md` 负责功能意图、用户路径、Exact Docs、争议点、非目标和验收边界。
- `middle-layer-discussion.md` 负责说明 changes、plans、drafts、queue、promotion 如何承接，以及哪些 docs/API/UDL/task 必须同步。
- `decisions.yaml` 是机器可校验账本；只有 `allow_changes: true` 且无 unresolved blockers/open questions 时，才允许进入 changes。
- `middle-layer/*.yaml` 是正式中间层账本，按 feature 记录插入点、联动关系、Exact Docs 行号、代码影响、依赖、slice 计划和风险边界。
- `changes/*.yaml` 保持 docs-change ledger；进入 plans/drafts/queue 前必须与 `middle-layer/*.yaml` 通过双源互校验。

## 边界

- `workflow/` 不能在讨论、预览、plan、queue 或 promotion preview 阶段写 live execution 材料。
- `middle-layer/` 不能替代 `docs/` 的产品语义；它只承接和细化已确认的 docs 意图。
- v1 live queue 已完成并归档为 `workflow/versions/v1-mvp/execution/`；不得重写历史 execution、`progress.json` 或 task-loop evidence。
- promotion preview 只是映射预演，不等于真实 promote/apply。
- 产品行为仍以 `docs/` 为源事实；workflow 只能记录、拆分和追踪，不替代 docs。

## 验证

- workflow 结构变更后运行 `./dev workflow doctor`。
- discussion gate 变更后运行 `./dev workflow discuss --version <v*> doctor`。
- 涉及 task-loop 自检时运行 `./task-loop check`，但不得启动真实 live runner。
