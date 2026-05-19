# Copy-ready: Browser / Chrome / Computer Use Templates

你在 `/Users/as/Ai-Project/project/AreaMatrix` 工作。本任务补齐 Browser / Chrome / Computer Use 的场景模板，不把它们变成默认主线。

## 目标

建立可复用模板，说明何时用：

- Browser：本地 dev server、file-backed preview、页面截图、点击/输入/渲染验证。
- Chrome：需要用户 profile、cookies、扩展、远程登录态网站。
- Computer Use：macOS app、SwiftUI 窗口、菜单、sheet、alert、GUI-only bug、跨 app 工作流。

模板必须强调：这些只做 UI / GUI / web 补证，不替代命令门禁。

## 非目标

- 不启动 UI 自动化。
- 不修改产品代码。
- 不修改 `tasks/prompts/**`。
- 不保存真实用户数据或截图。
- 不点击系统权限、支付、删除、隐私授权或不可逆 UI 操作。

## Source of Truth

- OpenAI Codex Computer Use: `https://developers.openai.com/codex/app/computer-use#when-to-use-computer-use`
- OpenAI Codex Browser: `https://developers.openai.com/codex/app/browser#browser-use`
- AreaMatrix Computer Use runbook: `.codex/references/computer-use-macos-ui-smoke-runbook.md`
- File safety owner: `.codex/skills-src/areamatrix-file-safety/SKILL.md`
- Validation owner: `.codex/skills-src/areamatrix-validation-driver/SKILL.md`

## Owner / Landing

- Owner: `areamatrix-validation-driver`
- Supporting owner: `areamatrix-file-safety`
- Landing: `.codex/references/computer-use-macos-ui-smoke-runbook.md` or a new concise UI evidence template under `.codex/references/**`
- Backlog landing: `tasks/backlog/**`

## 先读

1. `AGENTS.md`
2. `.codex/references/computer-use-macos-ui-smoke-runbook.md`
3. `.codex/skills-src/areamatrix-validation-driver/SKILL.md`
4. `.codex/skills-src/areamatrix-file-safety/SKILL.md`
5. OpenAI Codex Computer Use 官方文档
6. OpenAI Codex Browser 官方文档

## 允许修改

- `.codex/references/**`
- `.codex/skills-src/areamatrix-validation-driver/**` only if a reference link is missing
- `.codex/skills-src/areamatrix-file-safety/**` only if a reference link is missing
- `tasks/backlog/**`

## 禁止修改

- `tasks/prompts/**`
- `core/**`
- `apps/**`
- `workflow/versions/**`
- task-loop runtime state directories
- `/Users/as/Ai-Project/project/Vibe-Skills/**`

## 执行要求

1. 给出 Browser / Chrome / Computer Use 触发条件表。
2. 给出每类工具的禁止动作：
   - Browser 不处理真实账号敏感操作。
   - Chrome 只在需要用户登录态时使用。
   - Computer Use 不点击不可逆系统或用户文件操作。
3. 给出 UI evidence checklist：窗口/页面状态、操作步骤、截图或可观察状态、命令验证补充。
4. 明确 UI smoke 不能替代 `cargo`、`xcodebuild`、prompt doctor、governance、skill checks。
5. 明确真实用户文件、隐私、远程网站、高影响 UI 操作需要 Mission-Critical 流程。

## Rollback / Blocked

- 若模板需要真实 UI 操作才能写清，停止并只记录 blocked。
- 若模板会鼓励跳过命令验证，判定设计不合格并重写。
- 若涉及用户账号或隐私数据，停止并转 file-safety / Mission-Critical 审批。

## 验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references .codex/skills-src tasks/backlog
```

汇报时说明模板落点、触发条件、禁止动作和未触碰 `tasks/prompts/**`。
