# AreaMatrix Skills Source

这里是 AreaMatrix repo-local Codex skills 的源事实目录。

业务语义的统一源事实仍在 [`.ai-governance/`](../../.ai-governance/README.md)，本目录只承载 Codex skill 形态下的可复用工作流说明。

## 原则

- 项目级 skill 以本目录内容为准。
- 仓库根 `.agents/skills/areamatrix-*` 仅作为 Codex 自动发现这些 skill 的入口。
- `codex exec` 或 prompt 内需要手动读取 skill 时，必须读取仓库内 `.codex/skills-src/<skill>/SKILL.md` 或 `.agents/skills/<skill>/SKILL.md`，不要猜测 `/Users/as/.codex/skills-src/...`。
- 暂不维护 `.agents/skills-portable/`；只有目标环境不支持 symlink 时再补。
- 默认优先支持隐式触发；显式 `$areamatrix-*` 用于强制指定工作视角。
- 若 skill 语义变化涉及项目规则，先更新 `.ai-governance/`，再同步 skill 文本。

## 当前 Skills

- `areamatrix-task-loop`：任务循环、运行锁、stale progress、summary index、自检和恢复入口。
- `areamatrix-git-checkpoint`：PASS task 的 Git checkpoint、commit/push、dirty worktree 和恢复策略。
- `areamatrix-enterprise-governance`：代码评审、安全、依赖、CI、CODEOWNERS 与治理漂移。
- `areamatrix-validation-driver`
- `areamatrix-doc-sync`
- `areamatrix-file-safety`
- `areamatrix-workflow-planning`：v* 版本规划、docs 讨论、中间层讨论和 prompt 生成前门禁。

## Owner 边界

| Skill | Owner | 常见交接 |
|---|---|---|
| `areamatrix-task-loop` | live copy-ready / verify-ready runner、progress、logs、stale / failed / blocked 恢复 | Git checkpoint 行为交给 `areamatrix-git-checkpoint`；验证组合交给 `areamatrix-validation-driver`；v* planning 不进入 live queue 时交给 `areamatrix-workflow-planning` |
| `areamatrix-git-checkpoint` | PASS 后 commit / push / branch / dirty worktree / checkpoint failure | runner 状态交给 `areamatrix-task-loop`；merge readiness 与 CI / review 交给 `areamatrix-enterprise-governance` |
| `areamatrix-validation-driver` | 按改动范围选择最小充分验证、记录 PASS / FAIL / BLOCKED 证据 | docs/API/UDL 漂移交给 `areamatrix-doc-sync`；用户文件高风险验收交给 `areamatrix-file-safety`；治理门禁交给 `areamatrix-enterprise-governance` |
| `areamatrix-doc-sync` | `docs/`、Core API、UDL、prompt manifest、README、Codex 运行材料之间的漂移 | 只同步 Codex skill 导航时参考本 README；高风险文件语义交给 `areamatrix-file-safety`；workflow gate 交给 `areamatrix-workflow-planning` |
| `areamatrix-file-safety` | 用户文件、`.areamatrix/` 元数据、DB、staging、reindex、FSEvents / iCloud、生成概览安全 | 验证命令交给 `areamatrix-validation-driver`；Core API / UDL 对齐交给 `areamatrix-doc-sync` |
| `areamatrix-workflow-planning` | `workflow/versions/v*` discussion gate、middle-layer handoff、changes / plans / drafts / queue / promotion preview | live `tasks/prompts/**` 执行交给 `areamatrix-task-loop`；源事实漂移交给 `areamatrix-doc-sync` |
| `areamatrix-enterprise-governance` | review、安全、依赖、CI、CODEOWNERS、PR 模板、治理漂移 | 最小验证集交给 `areamatrix-validation-driver`；Git checkpoint 机制交给 `areamatrix-git-checkpoint` |

交叉引用只用于交接 owner，不把一个 skill 的完整规则复制到另一个 skill。

每个 skill 应保持：

- `SKILL.md`：触发条件、必读顺序、引用导航和核心 guardrails。
- `references/*.md`：可执行清单、矩阵、runbook 或验收表。
- `agents/openai.yaml`：UI 展示和默认提示元数据。

## 维护建议

- 变更 skill 时，同时检查 `agents/openai.yaml` 是否仍与 `SKILL.md` 匹配。
- 不在 skill 目录内添加 README、变更日志或低价值说明文件。
- 验收时先运行 `./dev check skills`；涉及 task-loop 时再运行 `./task-loop check` 和 prompt runner 基线。
