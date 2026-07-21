---
name: areamatrix-session-bootstrap
description: Bootstraps an AreaMatrix Cursor session by reading AGENTS.md, unfinished .cursor/plans/, dirty worktree ownership, and matching repo-local skills. Use at the start of a new chat, when resuming unfinished work, or when a sessionStart hook reports open plans or a dirty worktree. Chinese cues include 继续上次 / 接着做 / 恢复任务. Execute silently without asking the user to type slash commands.
---

# Session Bootstrap

## When

- 本仓库新对话开始时。
- 续做多步或未完成任务时。
- sessionStart hook 提示存在未完成 `.cursor/plans/` 或 dirty worktree 时。

## Steps

1. 读根 `AGENTS.md`（入口顺序、Skill 路由、高风险边界）；按目标路径补读最近的局部 `AGENTS.md`。
2. 列出 `.cursor/plans/`；若有未完成 plan，读取后向用户简短汇报「上次到 X，接下来做 Y」。
3. `git status --porcelain` 确认 worktree 状态；有脏改动时先判断归属——非本次会话产生的改动不纳入本次范围，必要时向用户澄清。
4. 按任务命中根 `AGENTS.md` Skill 路由表时，读对应 `.agents/skills/areamatrix-*/SKILL.md` 并按其 Read first 顺序补齐上下文。
5. 检索 Memory（若可用）中与本任务相关的历史经验。
6. 再动手改代码；不扩大范围。

## Check

- 读的材料与当前任务匹配吗（路由表命中的 skill、相关 `docs/**`），还是在凭记忆？
- 有未完成 plan 时，是否已简短告知用户上次进度？
- dirty worktree 的归属确认了吗？

## Silent

不要求用户运行 `/session-bootstrap`；直接执行以上步骤。
