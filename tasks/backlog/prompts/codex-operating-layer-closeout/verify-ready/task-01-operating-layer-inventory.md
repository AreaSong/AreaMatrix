# Verify-ready: Operating Layer Inventory

本次是只读验收，禁止修改文件。

## 验收目标

确认工作层 inventory 已经完整、准确、没有把候选能力误写成主线：

- `.ai-governance/**`、`.codex/references/**`、`.codex/skills-src/**`、`tasks/backlog/prompts/**` 均被盘点。
- 每个能力有 source of truth、owner、状态和 live mainline impact。
- `.codex/**` 没有被写成产品语义源事实。
- Vibe-Skills 没有被写成 AreaMatrix canonical runtime。
- `tasks/backlog/**` 没有被写成 live queue。

## 必须读取

1. `AGENTS.md`
2. `tasks/backlog/README.md`
3. `tasks/backlog/codex-native-area-vibe-optimization.md`
4. `tasks/backlog/prompts/codex-operating-layer-closeout/README.md`
5. `.ai-governance/README.md`
6. `.codex/references/index.md`
7. `.codex/skills-src/README.md`

## 只读检查

```bash
git diff --name-only
find .ai-governance .codex/references .codex/skills-src tasks/backlog/prompts -maxdepth 3 -type f | sort
rg -n "source of truth|源事实|owner|live mainline|tasks/prompts|progress|Vibe|runtime|candidate|候选" tasks/backlog .ai-governance .codex/references .codex/skills-src
./dev backlog list
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- tasks/backlog .codex/references
```

## 判定

若 inventory 漏掉任一 prompt package、repo-local skill 或关键 runbook，判定不通过。
若把 backlog / Vibe / `.codex` 写成 AreaMatrix 产品或 live runtime 源事实，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
