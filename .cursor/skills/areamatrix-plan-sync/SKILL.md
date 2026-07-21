---
name: areamatrix-plan-sync
description: Creates, updates, or archives AreaMatrix Cursor task plans under .cursor/plans/. Use for tasks with three or more steps, after Plan mode confirmation, and when finishing plan steps. Delete the plan file when all steps are done. Execute silently without asking for slash commands.
---

# Plan Sync

## When

- 任务不少于 3 步，或需要设计决策、跨多文件改动。
- 用户确认 Plan 后 → 若尚未写入，持久化到 `.cursor/plans/`。
- 完成一个步骤 → 更新 plan 文件内状态。
- 全部步骤完成 → 删除该 plan 文件（勿只勾选留存）。

## Format

Plan 文件应含：目标、步骤清单、每项完成标准、当前状态。

## Boundaries

- 进行中追踪只写 `.cursor/plans/`；不建独立 `*_PLAN.md` 报告。
- 不写 `tasks/active/**`、`tasks/backlog/**`、`workflow/versions/<version>/execution/**`、progress、queue 或 checkpoint；需要长期追踪的工作按根 `AGENTS.md` 边界另行进入对应体系。

## Check

- 任务不少于 3 步、跨多文件或有选型吗？是 → plan 文件已建并保持最新？
- 全部步骤完成后，plan 文件删除了吗？

## Silent

不要求用户运行 `/plan-sync`；自行维护 plan 文件。
