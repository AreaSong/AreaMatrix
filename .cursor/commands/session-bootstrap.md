# Session Bootstrap

本命令供兼容发现；Agent 须静默执行 skill `areamatrix-session-bootstrap`，勿要求用户输入本斜杠。

按该 skill 完成：读根与局部 `AGENTS.md`、读取未完成 `.cursor/plans/` 并简报进度、确认 dirty worktree 归属、命中 Skill 路由表时读取对应 `.agents/skills/areamatrix-*`。
