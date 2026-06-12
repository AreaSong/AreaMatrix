# Verify-ready: P0 外部能力接入门禁

本次是只读验收，禁止修改文件。

## 验收目标

确认已经建立外部能力接入门禁，并且满足：

- 外部 skill / workflow 不能因为目录存在而自动启用。
- Vibe-Skills 只能先作为候选能力池和治理参考。
- 每个候选都必须说明 source of truth、触发条件、验证方式、owner、是否影响主线。
- 明确四类结论：吸收、暂缓、只参考、拒绝。
- 未修改 `../Vibe-Skills/**`。
- 未修改 `tasks/prompts/**`。

## 只读检查

运行：

```bash
git diff --name-only
rg -n "admission|接入|Vibe-Skills|source of truth|触发|验证|owner|只参考|暂缓|拒绝" .ai-governance .codex/references tasks/backlog
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex/references tasks/backlog
```

## 判定

如果接入规则会让外部 runtime 绕过 AreaMatrix 主线，判定不通过。

