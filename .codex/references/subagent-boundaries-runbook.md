# Codex Subagent Boundaries Runbook

> 本 runbook 是 `.ai-governance/workflows/subagent-boundaries.md` 的 Codex 操作投影。它说明在 AreaMatrix 中何时使用 subagents、如何拆分写入、哪些 live runtime 区域禁止委派，以及主 agent 如何复核。

## 官方能力核对

截至 2026-05-15，已用 OpenAI Docs MCP 核对：

- Codex Subagents: https://developers.openai.com/codex/subagents
- Codex Subagent concepts: https://developers.openai.com/codex/concepts/subagents

当前官方语义：

- Codex 可以 spawn specialized agents 并行探索、处理或分析，再由主线程汇总。
- Codex 只在明确要求 subagents / parallel agent work 时 spawn；不会自动 spawn。
- 内置 agent 包括 `default`、`worker`、`explorer`。
- Subagents 继承当前 sandbox policy；custom agents 可定义自己的模型、reasoning、sandbox、MCP 和 skill 配置，但父线程的 live runtime override 仍会重新应用。
- 官方建议从 read-heavy work 开始，例如探索、测试、triage、summarization；parallel write-heavy workflow 要谨慎，因为会增加冲突和协调成本。

## AreaMatrix 采用结论

| 项 | 结论 |
|---|---|
| 默认启用方式 | explicit-only；只有用户或当前任务明确要求才用 |
| 主线关系 | 不进入 `./task-loop` 协议，不创建第二 runner |
| 最适合 | 并行只读审计、日志归因、测试输出归纳、文档/代码路径映射 |
| 可谨慎使用 | disjoint write set 明确的多模块实现 |
| 禁止 | live progress / checkpoint / runner 控制、用户文件高风险边界、同一 live task 多 writer |
| 最终责任 | 主 agent 负责整合、复核、验证和最终结论 |

## 只读探索

适合并行：

- 一个 PR 或 task 的安全、测试、文档、可维护性风险分别审计。
- 不同目录或模块的现状调查，例如 `core`、`apps/macos`、`docs` 分别读取。
- 长日志、测试输出、历史记录的独立归因。
- 外部官方文档核对，例如 OpenAI / Codex 能力、第三方框架 API。

只读 subagent prompt 必须包含：

```text
你是只读 explorer。只阅读和归纳，不修改文件，不运行写入命令，不启动/停止 runner。
问题：
读取范围：
禁止范围：
返回格式：结论、证据文件、风险、未确认项。
```

主 agent 不应把关键路径阻塞在 subagent 上。如果下一步必须依赖某个文件或状态，主 agent 自己读取关键证据，再让 subagent 做旁路补证。

## 写入实现

并行写入前，主 agent 必须先写出 ownership table：

| Worker | Owner | Allowed write set | Forbidden touches | Validation |
|---|---|---|---|---|
| worker-a | 例：docs adapter | `docs/foo.md` | `tasks/prompts/**`, progress, checkpoints | `./dev check ...` |
| worker-b | 例：tests only | `core/tests/foo.rs` | production files, lockfiles | `cargo test ...` |

worker prompt 必须包含：

```text
你不是唯一协作者。只拥有以下写入范围：
Allowed write set:
Forbidden touches:
Shared files:
Validation:

不得 revert、format 或重写非 owner 范围。若需要改 owner 外文件，停止并报告给主 agent。
完成后列出 changed files、validation、blocked items。
```

## Shared File 规则

以下文件或目录默认不能多 worker 并行写：

- `tasks/prompts/**`、manifest、`tasks/prompts/_shared/progress.json`
- `.codex/task-loop-logs/**`、`.codex/task-loop-runs/**`、task-loop lock
- Git checkpoint evidence、branch、commit、stash、reset、clean 相关状态
- DB migration、schema、rollback、staging recovery
- `core/area_matrix.udl`、Core API、Swift bridge 的破坏性变化
- lockfiles、CI workflow、CODEOWNERS、global config

确实需要修改共享文件时，指定单一 owner 或由主 agent 串行编辑。

## Live Runner 禁区

当 `./task-loop` 正在运行，或 task 处于 in-progress / stale / repair：

- 不把同一 live task 拆给多个 writer。
- 不让 subagent 修改 progress、logs、run summaries 或 checkpoint。
- 不让 subagent 启动、停止、drain、resume、reset、clear stale 或第二个 runner。
- 不让 subagent 做 commit、push、stash、reset、clean 或 branch 切换。
- 主 agent 亲自读取 live 状态并解释恢复语义。

如果需要并行分析当前失败，只能把静态代码、文档或复制出来的日志片段交给 read-only explorer。恢复操作、checkpoint 处理和最终结论仍由主 agent 执行。

## 用户文件与隐私边界

Subagent 默认不得触碰：

- 用户原文件删除、移动、覆盖、重命名。
- 非空目录接管、reindex、FSEvents 回流、iCloud 占位符下载。
- `.areamatrix/` 元数据、DB、migration、rollback、staging recovery。
- 隐私、AI 远程调用、用户数据离开本机。

这些边界命中 Mission-Critical 流程：主 agent 先说明影响、风险、验证和回滚，等待明确确认，再决定是否允许任何 subagent 做严格限定的只读审计。写入仍优先由主 agent 串行处理。

## 主 Agent 整合清单

Subagent 完成后，主 agent 必须检查：

- subagent 是否遵守 read-only 或 allowed write set。
- diff 是否有 owner 外路径、共享文件冲突或用户已有改动被回退。
- worker 报告的验证是否真实覆盖最终合并状态。
- 是否仍需要 `./dev check governance`、`./dev check skills`、prompt doctor、Rust、Swift、docs 或 task-loop 相关检查。
- 最终回答是否区分 subagent 发现、主 agent 复核结果和未验证项。

没有这些复核，subagent 结果不能作为 `VERIFY_RESULT: PASS`、checkpoint 成功、merge-ready 或最终完成证据。
