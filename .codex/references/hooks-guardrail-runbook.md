# Repo-local Hooks Guardrail Runbook

> 本 runbook 设计 AreaMatrix 的 repo-local Codex hooks guardrail。它是提醒和明显风险阻断层，不是完整验收系统，也不替代 `./dev`、`./task-loop`、verify-ready prompt、CI、人工 review 或 Git checkpoint。

## 官方行为基线

截至 2026-05-15，已用 OpenAI Docs MCP 核对 [Codex hooks 官方文档](https://developers.openai.com/codex/hooks)：

- Codex hooks 是 stable lifecycle extension，默认启用；可用 `[features] hooks = false` 关闭。
- Codex 会读取 `~/.codex/hooks.json`、`~/.codex/config.toml`、`<repo>/.codex/hooks.json`、`<repo>/.codex/config.toml`。
- repo-local hooks 只有在项目 `.codex/` layer 被信任时才加载；非 managed command hooks 需要在 `/hooks` 中 review / trust 后才运行。
- 当前稳定事件包括 `SessionStart`、`PreToolUse`、`PermissionRequest`、`PostToolUse`、`UserPromptSubmit`、`Stop`。
- 当前只有 `type: "command"` handler 会运行；`prompt`、`agent` handler 会被解析但跳过，`async: true` command hook 也会被跳过。
- `PreToolUse` / `PostToolUse` 只能覆盖当前支持的 Bash、`apply_patch` 和 MCP tool 路径；不能拦截所有 shell 路径、`WebSearch` 或所有非 shell / 非 MCP 工具。
- plugin-bundled hooks 当前是 opt-in；AreaMatrix P1.2 不依赖 `plugin_hooks`。

## 设计结论

本轮不新增 `.codex/hooks.json`，先落 runbook。原因：

- 当前任务目标是先设计 guardrail，不默认启用会改变行为的 hook。
- AreaMatrix 已有 live runner / dirty worktree 场景，贸然加载 project-local hook 会引入新的运行变量。
- 如果未来启用，必须由人工在 `/hooks` review / trust，并先跑只读 dry check。

推荐未来采用三层只读 guardrail：

| 层级 | Hook event | 目标 | 行为 |
|---|---|---|---|
| Session preflight | `SessionStart` | 提醒当前 live runner、dirty worktree、风险边界 | 输出额外上下文或 warning，不写文件 |
| Command guard | `PreToolUse` for `Bash|apply_patch|Edit|Write` | 阻断明显重复 runner、明显危险路径、明显跳过验证 | 返回 deny / block，或添加 additional context |
| Completion guard | `Stop` | 防止“完成”汇报缺少验证证据 | 若最终答复宣称完成但没有验证命令或无法验证说明，则要求继续补验证 |

## Guardrail 范围

### 1. Live Runner Duplicate

目标：已有 live runner 时，不要启动第二个 `./task-loop run` 或会启动 runner 的 `./dev` 动作。

只读检查：

- 读取 `.codex/task-loop-lock/pid`、`.codex/task-loop-lock/run_id`、`.codex/task-loop-lock/activity.json`。
- 对 `pid` 执行 `kill -0 <pid>` 或等价只读进程存在性检查。
- 可辅助读取 `./task-loop status`，但 hook 脚本不得调用 `run`、`drain`、`reset-progress`、`clear-stale`、`resume-stale`。

阻断条件：

- Bash command 明确包含 `./task-loop run`、`bash scripts/run_area_matrix_task_pipeline.sh` 或 `./dev` 启动/继续 runner 入口；
- 且 lock alive。

提示文案应包含：

- 当前 runner pid / run_id；
- 建议改用 `./dev status`、`./task-loop status`、`./task-loop drain` 或等待当前 runner 完成；
- 明确 hook 没有停止任何进程。

### 2. Dirty Worktree Checkpoint Risk

目标：dirty worktree 会阻塞 Git checkpoint，不能让 task-loop 把既有手工改动混进 PASS task checkpoint。

只读检查：

```bash
git status --short
git diff --name-only
```

阻断条件：

- Bash command 明确启动 live runner；
- 环境未显式设置 `GIT_CHECKPOINT=off`；
- `git status --short` 非空。

允许通知不阻断的情况：

- 用户只运行 `./dev status`、`./task-loop status`、`./task-loop check`、`./dev check ...`。
- `GIT_CHECKPOINT=off` 且命令是诊断用途；hook 仍应提示这不产生真实 checkpoint。

提示文案应说明：

- dirty worktree 会挡 checkpoint；
- 需要先提交/收口当前基础设施改动，或仅限诊断时显式 `GIT_CHECKPOINT=off`；
- dry-run / `GIT_CHECKPOINT=off` 不能算 task 完成。

### 3. Mission-Critical Path Confirmation

目标：用户文件路径、DB migration、UDL / Core API 破坏性变化必须显式确认。

高风险关键词和路径：

- 用户文件与接管边界：`README.md`、`AREAMATRIX.md`、`.areamatrix/`、staging、reindex、FSEvents、iCloud、placeholder。
- DB / migration：`migration`、`schema`、`rollback`、`repair`、`metadata`、`sqlite`、`diesel`、`sqlx`。
- Core API / UDL / bridge：`docs/api/core-api.md`、`core/area_matrix.udl`、UniFFI、Swift bridge、breaking change。
- 文件破坏性动作：delete、move、rename、overwrite、rm、mv、truncate、clean、reset、reindex。

候选 hook：

- `UserPromptSubmit`：用户 prompt 明显要求高风险变更但没有“已确认影响/风险/验证/回滚”的上下文时，block 并要求先确认。
- `PreToolUse` for `Bash|apply_patch|Edit|Write`：命令或 patch 明显命中高风险路径，并且当前 turn 没有明确确认文本时，block。

阻断不是为了禁止这些任务，而是要求先回到 Mission-Critical 流程：

1. 说明影响面。
2. 说明风险。
3. 说明验证。
4. 说明回滚。
5. 等待明确确认。

### 4. Validation Before Completion

目标：任务完成前不要跳过验证。

候选 hook：

- `Stop` 读取 `last_assistant_message`，只做文本级检查。

阻断条件：

- 最终答复宣称“完成 / 已完成 / PASS / 可以结束”；
- 但没有出现验证命令、验证结果，且没有明确说明“无法运行及原因”；
- 或明确说跳过验证、无需验证、没跑检查但仍宣称完成。

要求继续的提示：

- 运行与改动范围匹配的最小检查；
- 或说明无法运行的具体原因；
- 不得把 hook 自己的通过当成任务验收通过。

## 建议 `.codex/hooks.json` 草案

以下只是未来启用方向，不在本轮落盘。真正启用前还需要新增只读脚本、人工 review / trust，并跑验证。

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \"$(git rev-parse --show-toplevel)/.codex/hooks/session_preflight.py\"",
            "timeout": 10,
            "statusMessage": "Checking AreaMatrix runtime guardrails"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash|apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \"$(git rev-parse --show-toplevel)/.codex/hooks/pre_tool_guardrail.py\"",
            "timeout": 10,
            "statusMessage": "Checking AreaMatrix command guardrails"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \"$(git rev-parse --show-toplevel)/.codex/hooks/user_prompt_guardrail.py\"",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \"$(git rev-parse --show-toplevel)/.codex/hooks/stop_validation_guardrail.py\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

草案约束：

- hook scripts 只能读取 stdin、git 状态、lock 文件和进程状态。
- 不得写文件、启动 runner、停止 runner、提交、推送、reset、clean、stash 或修改用户文件。
- 不使用 plugin hooks。
- 不使用 `async: true`、`type: "prompt"` 或 `type: "agent"` 作为关键门禁。
- command 路径从 git root 解析，不依赖当前工作目录是 repo root。

## 信任、禁用与回滚

信任：

- repo-local hooks 只有在 AreaMatrix 项目被 Codex trusted 时才加载。
- 新增或修改非 managed command hook 后，需要在 Codex CLI 的 `/hooks` 中 review / trust。
- 未经 trust 的 hook 不应被视为已生效的安全边界。

禁用：

- 在 `/hooks` 中禁用单个非 managed hook；
- 或移除 / 重命名 `<repo>/.codex/hooks.json`；
- 或在用户 config 中设置：

```toml
[features]
hooks = false
```

回滚：

1. 删除或还原 `<repo>/.codex/hooks.json`。
2. 删除或还原新增的 `.codex/hooks/*.py` 脚本。
3. 重启 Codex session 或用 `/hooks` 重新检查。
4. 运行 `./dev check governance`、`./dev check skills`、`python3 tasks/prompts/_shared/prompt_pipeline.py doctor`。

## 验证清单

只设计 runbook 时：

```bash
./dev check governance
./dev check skills
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check -- .ai-governance .codex tasks/backlog
```

未来新增真实 `.codex/hooks.json` 时，还要补充：

- `codex` 启动时没有 hook schema warning。
- `/hooks` 中能看到 repo-local hook source。
- hook 被标记为 reviewed / trusted 后才算生效。
- dry command 覆盖重复 runner、dirty worktree、危险路径、缺少验证四类场景。
- 证明 hook 没有实际运行任何破坏性命令。
