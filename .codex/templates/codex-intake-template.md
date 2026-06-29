# Codex Intake

Lane: Quick | Change | Mission-Critical | Explore | Review | Ops
Task ID: <task-id>
Project: AreaMatrix

## 目标

- 

## 范围

- 

## Source of Truth

- AGENTS:
- Docs:
- Governance:
- Workflow / task manifest:

## Lane / Risk

- Lane: Quick | Change | Mission-Critical | Explore | Review | Ops
- Risk Level: Low | Medium | High | Mission-Critical
- Confirmation: Not Required | Required | Granted | Blocked

## 允许路径

- 

## 禁止事项

- 不写 `workflow/versions/<version>/execution/**`，除非任务已明确进入 live execution。
- 不修改 Codex 内部 SQLite。
- 不自动归档线程。
- 不触碰未列入允许路径的用户文件、DB、staging、migration、reindex、FSEvents/iCloud 或隐私边界。

## Subagent 策略

- 只读 subagents:
- 写入 subagents:
- Owner / allowed write set:

## 自动化范围

- Scope: observe-only | registry-write | validation-run | manual-confirmation-required
- 可以自动执行:
- 需要人工确认:

## 验收标准

- 

## 验证计划

- 最小充分验证:
- 扩大验证条件:

## 期望输出

- 

## 恢复入口

- Handoff:
- Evidence:
- Closeout:
- Next Action:
- Validation:
