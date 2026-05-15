# Verify-ready: Operator Playbook

本次是只读验收，禁止修改文件。

## 验收目标

确认操作手册可用且没有变成新的源事实：

- 手册说明了官方 docs、AreaMatrix docs、`.ai-governance`、`.codex`、backlog、workflow、live queue 的使用顺序。
- 手册说明了 Vibe-Skills、hooks、subagents、Computer Use、Automations 的接入判断。
- 手册说明了 source-of-truth / execution / state / skill owner 污染检查。
- 手册链接或引用现有源事实，没有替代它们。
- 未修改 `tasks/prompts/**`。

## 必须读取

1. `AGENTS.md`
2. `.codex/references/index.md`
3. 新增或修改的 playbook 文件
4. `tasks/backlog/README.md`
5. `.ai-governance/workflows/prompt-task-runtime.md`
6. `.ai-governance/workflows/external-capability-admission.md`
7. `.codex/skills-src/README.md`

## 只读检查

```bash
git diff --name-only
rg -n "OpenAI|Codex|docs/|\\.ai-governance|\\.codex|tasks/backlog|tasks/prompts|workflow|Vibe|hooks|subagent|Computer Use|Automations|污染|source of truth|源事实" .codex/references tasks/backlog
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references tasks/backlog
```

## 判定

若手册把自己写成产品或治理源事实，判定不通过。
若手册缺少四类污染检查或日常使用顺序，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
