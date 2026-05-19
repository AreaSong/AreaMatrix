# Verify-ready: P1 Computer Use macOS UI smoke runbook

本次是只读验收，禁止修改文件。

## 验收目标

确认 runbook 已说明：

- Computer Use 是 macOS UI smoke 补充，不替代命令测试和验收。
- 适用场景覆盖 SwiftUI 窗口、点击、菜单、表单、截图或状态检查。
- Browser / Chrome 与 Computer Use 的边界清楚。
- 密码、系统权限、隐私授权、用户文件确认不得自动化。
- 有可复用的证据格式。

## 只读检查

```bash
git diff --name-only
rg -n "Computer Use|macOS|SwiftUI|UI smoke|Browser|Chrome|截图|权限|隐私|密码|证据" .codex tasks/backlog docs apps 2>/dev/null
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references .codex/skills-src tasks/backlog
```

## 判定

若 runbook 暗示可自动处理密码、系统授权、隐私授权或替代正式测试，判定不通过。

