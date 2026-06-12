# Copy-ready: P2 Vibe-Skills 横向能力筛选

你在 `.` 工作。本任务只筛选 Vibe-Skills 候选能力，不安装、不启用、不复制全量仓库。

## 目标

阅读 `../Vibe-Skills`，筛选适合 AreaMatrix 近期吸收的横向能力。

优先候选：

- `systematic-debugging`
- `tdd-guide`
- `verification-before-completion`
- `code-reviewer`
- `security-threat-model`
- `architecture-patterns`
- `docs-review`
- `writing-plans`
- `subagent-driven-development`

为每个候选给出结论：

- 吸收为 AreaMatrix repo-local skill 补强
- 吸收到 `.ai-governance` / `.codex/references` 规则
- 只作为参考
- 暂缓
- 拒绝

## 先读

1. `AGENTS.md`
2. `.ai-governance/README.md`
3. `.codex/references/codex-workflow-and-tools.md`
4. `tasks/backlog/codex-native-area-vibe-optimization.md`
5. `../Vibe-Skills/README.zh.md`
6. 候选 skill 的 `SKILL.md` 或 canonical instruction
7. `../Vibe-Skills/references/skill-distillation-rules.md` 如存在

## 允许修改

- `.codex/references/**`
- `tasks/backlog/**`

## 禁止修改

- `../Vibe-Skills/**`
- `tasks/prompts/**`
- `.codex/skills-src/**`，本任务只筛选，不正式吸收
- 全局 `~/.codex/**`

## 执行要求

1. 新增候选能力筛选矩阵。
2. 每个候选说明：用途、与 AreaMatrix 现有能力关系、建议结论、理由、后续落点。
3. 明确 `vibe` runtime 不进入 AreaMatrix 主线。
4. 明确专业垂直 skills 暂不进入默认工作流，除非未来具体任务需要。

## 验证

```bash
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references tasks/backlog
```

