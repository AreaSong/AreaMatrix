# Copy-ready: P1 Computer Use macOS UI smoke runbook

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务为 macOS SwiftUI 验收补充 Computer Use UI smoke runbook。

## 目标

建立一个可复用 runbook：当 AreaMatrix macOS UI 任务完成时，如何用 Computer Use 补充真实窗口、点击、输入、菜单、截图或状态检查证据。

Computer Use 只能作为 UI smoke 补充，不能替代：

- Rust tests
- `xcodebuild`
- SwiftLint / SwiftFormat
- prompt verify
- 文档/UDL/Core API 核对

## 先读

1. `AGENTS.md`
2. `apps/macos/AGENTS.md` 如存在
3. `docs/development/testing.md`
4. `.codex/references/codex-workflow-and-tools.md`
5. `tasks/backlog/codex-native-area-vibe-optimization.md`
6. OpenAI Codex Computer Use 官方文档，优先用 OpenAI Docs MCP 核对当前限制

## 允许修改

- `.codex/references/**`
- `.codex/skills-src/**` 如确实需要补现有 skill 引用
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- 任何系统权限、密码、支付、隐私授权自动化

## 执行要求

1. 新增或补充 macOS UI smoke runbook。
2. 说明何时用 Computer Use，何时用 Browser / Chrome，何时用命令测试。
3. 说明安全边界：密码、系统权限、隐私、用户文件确认必须人工介入。
4. 给出最小证据格式：窗口名、操作步骤、截图/状态、命令验证搭配。
5. 如新增文档，更新 `.codex/references/index.md`。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references .codex/skills-src tasks/backlog
```

