# Verify-ready: Browser / Chrome / Computer Use Templates

本次是只读验收，禁止修改文件。

## 验收目标

确认 UI / web / GUI 工具模板是补证工具，不是主线替代：

- Browser / Chrome / Computer Use 触发条件清楚。
- 禁止动作和 Mission-Critical 边界清楚。
- UI evidence checklist 清楚。
- 明确不替代命令验证。
- 未修改产品代码或 live queue。

## 必须读取

1. `.codex/references/computer-use-macos-ui-smoke-runbook.md`
2. 新增或修改的 UI / Browser template 文件
3. `.codex/skills-src/areamatrix-validation-driver/SKILL.md`
4. `.codex/skills-src/areamatrix-file-safety/SKILL.md`
5. `tasks/backlog/prompts/codex-advanced-noninvasive-layer/README.md`

## 只读检查

```bash
git diff --name-only
rg -n "Browser|Chrome|Computer Use|UI smoke|GUI|screenshot|xcodebuild|cargo|prompt doctor|Mission-Critical|隐私|用户文件|不可逆" .codex tasks/backlog
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references .codex/skills-src tasks/backlog
```

## 判定

若模板允许跳过命令验证，判定不通过。
若模板允许不可逆 UI 操作或真实用户文件风险绕过 Mission-Critical，判定不通过。
若验证命令无法运行，说明原因并判定为 blocked。
