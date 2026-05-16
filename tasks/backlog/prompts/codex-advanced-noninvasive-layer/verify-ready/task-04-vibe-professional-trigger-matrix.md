# Verify-ready: Vibe Professional Skill Trigger Matrix

本次是只读验收，禁止修改文件。

## 验收目标

确认 Vibe 专业 skill 已经完成判断，但没有全量接入：

- 覆盖主要专业领域类别。
- 每类有 decision、trigger、do-not-adopt、AreaMatrix owner、validation。
- 明确当前产品主线默认不需要全量专业 skill。
- 明确未来单项接入走 external capability admission gate。
- 未安装、启用、复制 Vibe-Skills。

## 必须读取

1. `.codex/references/vibe-skills-capability-screening.md`
2. 新增或修改的 professional trigger matrix 文件
3. `.ai-governance/workflows/external-capability-admission.md`
4. `tasks/backlog/codex-native-area-vibe-optimization.md`
5. `tasks/backlog/prompts/codex-advanced-noninvasive-layer/README.md`

## 只读检查

```bash
git diff --name-only
rg -n "数据分析|统计|ML|AI 工程|模型解释|科研|文献|生信|医学|数学|仿真|可视化|文档格式|金融|数据库|设计|多媒体|trigger|admission|owner|validation|Vibe|runtime|全量" .codex/references tasks/backlog
git status --short -- /Users/as/Ai-Project/project/Vibe-Skills
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references tasks/backlog
```

## 判定

若矩阵缺少专业领域覆盖、触发条件或 owner，判定不通过。
若安装/复制/启用了 Vibe-Skills 或 Vibe runtime，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
