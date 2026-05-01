# AreaMatrix Codex Materials

`.codex/` 承载只服务 Codex 运行时的材料，不是 AreaMatrix 业务语义的权威来源。

权威规则在：

- [../AGENTS.md](../AGENTS.md)
- [../.ai-governance/README.md](../.ai-governance/README.md)
- [../docs/README.md](../docs/README.md)

## 当前内容

- `references/index.md`：Codex 需要快速定位的规则入口。
- `skills-src/`：AreaMatrix repo-local Codex skills 的源事实目录；每个 skill 的细节放在 `references/`。
- `templates/prompt-task-template.md`：新建 prompt 任务的模板。
- `templates/prompt-verify-template.md`：验收 prompt 的格式参考；实际优先由 runner 生成。
- `task-loop-logs/`、`task-loop-runs/`、`task-loop-progress-backups/`：自动任务循环的日志、运行摘要与进度备份，作为可回溯证据保留。
- Task loop 的状态 helper 位于 `scripts/task_loop_state.py`，Git checkpoint helper 位于 `scripts/task_loop_git.py`，完整自检入口是 `bash scripts/check-task-loop.sh`。
- Prompt 工程质量门禁位于 `tasks/prompts/_shared/engineering-quality-rules.md`；编码规范源事实仍在 `docs/development/coding-standards.md`。

## 约束

- 不在本目录放个人模型、权限、token 或密钥。
- 项目语义变化先更新 `.ai-governance/`，再同步这里。
- Prompt 任务本体放在 `tasks/prompts/`。
- Skill 发现入口放在 `.agents/skills/`，源事实仍以 `.codex/skills-src/` 为准。
- `codex exec` 需要读取 repo-local skill 时，使用本仓库内 `.codex/skills-src/<skill>/SKILL.md` 或 `.agents/skills/<skill>/SKILL.md`；不要使用 `/Users/as/.codex/skills-src/...` 这类全局猜测路径。
- Skill 变更后运行 `bash scripts/check-skills.sh`。
- Git checkpoint 策略见 `skills-src/areamatrix-git-checkpoint/`；默认 PASS task 本地 commit，push 需要显式 `GIT_CHECKPOINT=push`。
- Task loop 的运行锁 `.codex/task-loop-lock/` 是本地协调缓存，不作为证据提交。
