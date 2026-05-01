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

- `areamatrix-task-loop`：任务循环、运行锁、stale progress、summary 和恢复入口。
- `areamatrix-validation-driver`
- `areamatrix-doc-sync`
- `areamatrix-file-safety`

每个 skill 应保持：

- `SKILL.md`：触发条件、必读顺序、引用导航和核心 guardrails。
- `references/*.md`：可执行清单、矩阵、runbook 或验收表。
- `agents/openai.yaml`：UI 展示和默认提示元数据。

## 维护建议

- 变更 skill 时，同时检查 `agents/openai.yaml` 是否仍与 `SKILL.md` 匹配。
- 不在 skill 目录内添加 README、变更日志或低价值说明文件。
- 验收时先运行 `bash scripts/check-skills.sh`，再运行 prompt runner 基线。
