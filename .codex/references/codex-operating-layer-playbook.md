# Codex Operating Layer Playbook

> 本 playbook 只索引和解释现有规则，不是新的 source of truth。产品语义仍看 `docs/**`，治理边界仍看 `.ai-governance/**`，live execution 仍只从已批准的 `tasks/prompts/**` 和 `./task-loop` 进入。

## 默认顺序

```text
OpenAI / Codex 易变信息 -> 官方 OpenAI docs
AreaMatrix 产品语义 -> docs/**
治理、风险、完成门禁 -> .ai-governance/**
Codex 操作投影 -> .codex/references/** + .codex/skills-src/**
候选 prompt 包 -> tasks/backlog/** + ./dev backlog
大功能 / 新 v* -> workflow/**
live 执行 -> tasks/prompts/** + ./task-loop
```

## 日常分流表

| 问题类型 | 先去哪里 | 入口 | 禁止 |
|---|---|---|---|
| OpenAI / Codex / model / hooks / MCP / skills / plugin / Computer Use / Automations 是否支持或最新行为 | 官方 OpenAI / Codex docs；本仓库只记录核对日期和本地落点 | `openaiDeveloperDocs`，必要时仅退到 `developers.openai.com` / `platform.openai.com` | 用旧记忆、第三方文章或 AreaMatrix 文档判断官方当前状态 |
| AreaMatrix 产品、架构、API、UX、开发规范 | `docs/**` | `docs/README.md`，Core API 看 `docs/api/core-api.md` | 让 `.codex/**`、backlog、skill 覆盖产品定义 |
| AI 协作规则、风险边界、完成门禁 | `.ai-governance/**` | `.ai-governance/README.md`、workflow rules | 把 runbook 写成规则源事实 |
| Codex 日常操作、证据格式、失败归因、UI smoke | `.codex/references/**` 和 repo-local skills | `.codex/references/index.md`、`.codex/skills-src/README.md` | 保存 token、全局 `~/.codex/**` 内容或易过期配置为硬规则 |
| 还未进入 live queue 的 prompt package | `tasks/backlog/**` | `./dev backlog list`、`./dev backlog show <package>` | 执行 backlog prompt、写 progress、写 checkpoint、直接 promotion |
| 新版本、大功能、重构、优化生命周期 | `workflow/**` | `./dev workflow init --version <v*>`、`./dev workflow doctor` | 从 workflow 直接写 live `tasks/prompts/**` 或抢占 live label |
| 已批准小任务的执行和验收 | `tasks/prompts/**` + `./task-loop` | `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`、`./dev`、`./task-loop` | 启动第二 runner、手改 runtime state、绕过 verify-ready |

## 外部能力判断

| 能力 | 默认结论 | 接入前必须证明 |
|---|---|---|
| Vibe-Skills | 候选能力池和治理参考 | 过 `.ai-governance/workflows/external-capability-admission.md`；明确缺口、去重、owner、触发、验证；不得引入 Vibe runtime |
| hooks | warn-only / read-only guardrail 候选 | 只提醒、补充上下文或做只读检查；不 block/deny/continue，不写文件、不启动/停止 runner、不 commit/push/reset/clean/stash；需要 `/hooks` review / trust |
| subagents | explicit-only | 只读探索可并行；写入必须有 disjoint write set、owner、允许/禁止路径和主 agent 复核 |
| Computer Use | macOS UI smoke 补证 | 只补真实窗口/点击/截图证据；不替代 `xcodebuild`、Rust tests、prompt verify；不点密码、系统权限、隐私或真实用户文件破坏性确认 |
| Automations / Cloud / Worktrees / SDK / app-server / remote-control | 暂不接管 v1 主线 | 不创建第二套 runner、progress、queue、checkpoint 或 state；如要影响主线，先走 workflow planning gate 和人工确认 |

## 四类污染快速检查

| 污染类型 | 快速检查 | 不变量 |
|---|---|---|
| Source of truth 污染 | 变更是否把产品语义写进 `.codex/**` / backlog / skill？是否让外部资料覆盖 `docs/**` 或 `.ai-governance/**`？ | `.codex/**` 只能做 Codex 操作投影；外部资料只能参考或候选 |
| Execution 污染 | 是否新增 runner、自动执行 backlog、直接 promotion、或让 hooks / automation / subagent 接管 `./task-loop`？ | live execution 只从批准的 `tasks/prompts/**` 和 `./task-loop` 进入 |
| State 污染 | 是否写 `tasks/prompts/_shared/progress.json`、logs、run summaries、lock、checkpoint、branch/commit 状态？ | backlog、workflow preview、references 和 skills 不写 runtime state |
| Skill owner 污染 | 是否新增重复 skill，或把同一规则复制到多个 owner？ | 先复用 `.codex/skills-src/**` 现有 owner；规则语义变化先改 `.ai-governance/**` |

## 最小验证

改这个操作层、reference、backlog 或 skill 导航后，至少运行：

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .codex/references tasks/backlog
```

如果改到更具体的层，再追加对应检查：`./dev workflow doctor`、`./task-loop check`、Rust / Swift / docs / CI 检查等。
