# AreaMatrix Codex Materials

`.codex/` 承载只服务 Codex 运行时的材料，不是 AreaMatrix 业务语义的权威来源。

权威规则在：

- [../AGENTS.md](../AGENTS.md)
- [../.ai-governance/README.md](../.ai-governance/README.md)
- [../docs/README.md](../docs/README.md)

## 当前内容

- `config.example.toml`：repo-local Codex 配置模板；复制为本地 `config.toml`（已 gitignore，不入库）。
- `references/index.md`：Codex 需要快速定位的规则入口。
- `skills-src/`：AreaMatrix repo-local Codex skills 的源事实目录；每个 skill 的细节放在 `references/`。
- `../.agents/skills/`：Codex 官方 repo-local skill 发现入口；当前以 symlink 方式指向本目录下的 `skills-src/`。
- `templates/prompt-task-template.md`：新建 prompt 任务的模板。
- `templates/prompt-verify-template.md`：验收 prompt 的格式参考；实际优先由 runner 生成。
- `templates/codex-intake-template.md`：Codex OS 任务进入模板，记录 lane、risk、source of truth、允许路径、自动化范围和验证计划。
- `templates/codex-handoff-template.md`：Codex OS 恢复交接模板，记录当前状态、关键文件、验证、阻塞点和下一步。
- `templates/codex-evidence-template.md`：Codex OS 验证证据模板，记录新鲜命令、结果、未验证项、drift 检查和剩余风险。
- `templates/codex-closeout-template.md`：Codex OS 线程收尾模板，记录完成内容、验证、下一步入口和归档建议。
- `templates/task-registry.example.json`：Codex OS 本机 task registry 示例，不是 live queue。
- `runtime/`：本机运行态统一目录；只放日志、锁、控制请求、本地偏好和恢复快照，不作为业务源事实。
  - `runtime/task-loop/logs/`：自动任务循环的本地原始日志；`*.exec.log` 只作本机排障，不作为完成证据。
  - `runtime/task-loop/console/`：后台 Dev Console 输出。
  - `runtime/task-loop/control/`：drain 等本地控制请求。
  - `runtime/task-loop/lock/`：live runner 锁。
  - `runtime/task-loop/tmp/`：本地临时保留目录。
  - `runtime/task-loop/progress-backups/`：本地 progress 恢复快照（reset/clear-stale 时写入），默认不进 Git；仓库仅跟踪脱敏 example fixture。
  - `runtime/dev-console/`：本地 Dev Console 偏好。
  - `runtime/codex-os/`：Codex Operating System 的本地 dashboard、thread-health、task-registry、context、evidence、closeout、weekly review 和 health report；只作操作面恢复索引，不是 live queue 或产品完成证据，默认 gitignored。
- `workflow/versions/v1-mvp/evidence/task-loop-runs/`：可追溯、可提交的 run summary / index 证据，不属于 `.codex/` 的业务源事实。
- Task loop 的状态 helper 位于 `scripts/task_loop/state.py`，Git checkpoint helper 位于 `scripts/task_loop/git.py`，完整自检入口是 `./task-loop check`。
- Prompt 工程质量门禁位于 `workflow/versions/v1-mvp/execution/_shared/engineering-quality-rules.md`；编码规范源事实仍在 `docs/development/coding-standards.md`。
- 企业治理检查入口是 `./dev check governance`，源事实在 `CODE_REVIEW.md`、`SECURITY.md` 和 `docs/development/`。

## 约束

- 不在本目录放个人模型、权限、token 或密钥；`config.toml` 仅保留在本机。
- 项目语义变化先更新 `.ai-governance/`，再同步这里。
- Prompt 执行任务本体放在 `workflow/versions/<version>/execution/`；v1 历史执行队列位于 `workflow/versions/v1-mvp/execution/`。
- Skill 发现入口放在 `.agents/skills/`，源事实仍以 `.codex/skills-src/` 为准；这是官方发现路径 + repo 内源事实目录的投影关系，不是第二份 skill。
- `codex exec` 需要读取 repo-local skill 时，使用本仓库内 `.codex/skills-src/<skill>/SKILL.md` 或 `.agents/skills/<skill>/SKILL.md`；不要使用 `~/.codex/skills-src/...` 这类全局猜测路径。
- Skill 变更后运行 `./dev check skills`。
- 企业治理变更后运行 `./dev check governance`。
- Git checkpoint 策略见 `skills-src/areamatrix-git-checkpoint/`；默认 PASS task 本地 commit，push 需要显式 `GIT_CHECKPOINT=push`。
- Task loop 的运行锁 `.codex/runtime/task-loop/lock/` 是本地协调缓存，不作为证据提交。
- 旧路径 `.codex/task-loop-logs/`、`.codex/task-loop-progress-backups/`、`.codex/task-loop-lock/`、`.codex/task-loop-control/`、`.codex/task-loop-console/`、`.codex/dev-console/` 只作历史兼容读取；新运行态写入 `runtime/`。

## Codex OS 任务入口

日常任务优先由 Codex 自动使用：

```bash
./dev codex-os start-flow --task-id <task-id> --changed --write
./dev codex-os run-validation --task-id <task-id> --changed --execute --write
./dev codex-os repair-plan --task-id <task-id> --changed
./dev codex-os close-flow --task-id <task-id> --status Done --validation "<fresh PASS/OK result>" --write
./dev codex-os ops-flow --write
```

这些命令只管理 `.codex/runtime/codex-os/` 的本机操作层状态。它们不会写 Codex 内部 SQLite，
不会归档线程，不会启动或替代 `./task-loop`，也不会写入 `workflow/versions/<version>/execution/**`。

底层展开命令仍可用于诊断或精细控制：`context`、`resume`、`preflight`、`subagent-plan`、
`recommend-validation`、`evidence`、`closeout`、`finish`、`archive-review`、`title-suggestions`、
`weekly` 和 `health-score`。
