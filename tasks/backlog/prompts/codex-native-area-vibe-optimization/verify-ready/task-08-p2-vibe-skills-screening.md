# Verify-ready: P2 Vibe-Skills 横向能力筛选

本次是只读验收，禁止修改文件。

## 验收目标

确认筛选结果：

- 覆盖至少这些横向候选：`systematic-debugging`、`tdd-guide`、`verification-before-completion`、`code-reviewer`、`security-threat-model`、`architecture-patterns`、`docs-review`、`writing-plans`。
- 每个候选有清晰结论：吸收、规则吸收、只参考、暂缓或拒绝。
- 说明与 AreaMatrix 现有 skills / governance 的关系。
- 没有修改 Vibe-Skills 仓库。
- 没有把 `vibe` runtime 设为 AreaMatrix 主线。
- 没有修改 `tasks/prompts/**`。

## 只读检查

```bash
git diff --name-only
rg -n "systematic-debugging|tdd-guide|verification-before-completion|code-reviewer|security-threat-model|architecture-patterns|docs-review|writing-plans|只参考|暂缓|拒绝|吸收" .codex/references tasks/backlog
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references tasks/backlog
```

## 判定

若结果只是列名字，没有说明是否与 AreaMatrix 重复、为什么吸收或不吸收，判定不通过。

