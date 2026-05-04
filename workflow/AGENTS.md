# Workflow Agent Guide

## 定位

- `workflow/` 是大功能、版本、重构和优化的生命周期系统。
- `tasks/prompts/**` 是已经批准的小任务执行队列。
- `./task-loop` 只执行 live queue，不负责需求讨论、版本决策或 promotion 审批。

## 标准顺序

新 v* 版本默认遵循：

```text
docs
-> workflow/templates
-> workflow/versions/v*/discussion
-> changes
-> plans
-> drafts
-> queue
-> promotion preview
-> tasks/prompts/**
```

## Discussion Gate

- 新版本进入 `changes/` 前必须先完成 `discussion/` 三件套：
  - `docs-discussion.md`
  - `middle-layer-discussion.md`
  - `decisions.yaml`
- `docs-discussion.md` 负责功能意图、用户路径、Exact Docs、争议点、非目标和验收边界。
- `middle-layer-discussion.md` 负责说明 changes、plans、drafts、queue、promotion 如何承接，以及哪些 docs/API/UDL/task 必须同步。
- `decisions.yaml` 是机器可校验账本；只有 `allow_changes: true` 且无 unresolved blockers/open questions 时，才允许进入 changes。

## 边界

- `workflow/` 不能在讨论、预览、plan、queue 或 promotion preview 阶段写 live `tasks/prompts/**`。
- v1 live queue 未完成前，不移动、不重命名、不归档当前 `tasks/prompts/**`。
- promotion preview 只是映射预演，不等于真实 promote/apply。
- 产品行为仍以 `docs/` 为源事实；workflow 只能记录、拆分和追踪，不替代 docs。

## 验证

- workflow 结构变更后运行 `./dev workflow doctor`。
- discussion gate 变更后运行 `./dev workflow discuss --version <v*> doctor`。
- 涉及 task-loop 自检时运行 `./task-loop check`，但不得启动真实 live runner。
