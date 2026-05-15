# Subagent Boundaries

> 本规则定义 Codex subagents 在 AreaMatrix 中的使用边界。Subagent 是并行协作能力，不是第二套 runner、验收系统或责任转移机制。

## 基线结论

- Codex 只在当前任务明确授权 subagent、并行 agent work 或一 agent 一问题时才可 spawn subagent；不得因为任务复杂就自动委派。
- Subagent 适合把独立、嘈杂、可汇总的工作移出主线程，例如只读探索、日志归因、测试输出归纳或分模块审计。
- 写入型 subagent 只能在 owner、允许路径和 disjoint write set 已经明确时使用；共享文件、共享状态和 live runner 状态默认由主 agent 串行处理。
- 主 agent 始终拥有任务契约、边界解释、验证选择、diff 复核、最终结论和用户汇报责任。Subagent 输出只是证据输入，不能替代验收。
- AreaMatrix v1 live execution 主线仍是 `./dev + ./task-loop + tasks/prompts/**`。Subagent 不得接管 live queue、progress、checkpoint、promotion 或 repo-local skill 主线。

## 角色与权限

| 角色 | 典型 native agent | 可做 | 不可做 |
|---|---|---|---|
| Lead / 主 agent | `default` | 维护任务契约、拆分工作、整合结果、选择验证、给最终结论 | 把最终责任转交给 subagent |
| Explorer / 只读探索 | `explorer` | 搜索、阅读、比对、归纳证据和风险 | 修改文件、启动 runner、写 progress、提交 checkpoint |
| Worker / scoped implementation | `worker` | 在明确 owner 和允许路径内实现、修复、补测试 | 越过 write set、回退他人改动、写共享状态 |
| Reviewer / quality gate | `default` 或 `worker` | 对 diff、契约、测试和风险做只读复核 | 用 review 名义直接扩大修复范围 |
| Security reviewer | `default` 或 `worker` | 聚焦隐私、路径、权限、远程调用、依赖和用户文件边界 | 在没有具体 trust boundary 时泛化整改 |

Vibe-Skills 的 role taxonomy 可作为命名和 permission bundle 参考，但 AreaMatrix 的 source of truth 仍是本文件和 `.ai-governance/**`。

## 只读探索

允许并行只读探索的条件：

- 问题可以独立回答，例如不同模块、不同文档、不同风险维度、不同测试日志。
- 每个 subagent 的输入包含明确问题、读取范围、禁止写入说明和期望输出格式。
- subagent 只返回 evidence、文件引用、风险、假设和建议，不直接改代码或更新状态。
- 主 agent 不等待 subagent 做当前 critical path 的阻塞动作；如果下一步被该结果阻塞，应由主 agent 自己读取关键上下文。

只读探索禁止事项：

- 不读写 live task-loop progress、lock、run summary 或 checkpoint 状态作为状态源；live 状态由主 agent 亲自读取和解释。
- 不启动、停止、drain、resume、reset 或 clear live runner。
- 不把 explorer 的判断直接写成 PASS、DONE、completed 或 merge-ready。
- 不读取或操作真实用户文件、`.areamatrix/` 元数据、DB、staging、FSEvents、iCloud 占位符或隐私/远程调用边界，除非主任务已按 Mission-Critical 流程获得明确确认并且 subagent 只做授权范围内的只读审计。

## 写入实现

并行写入只有在全部条件满足时才允许：

- 用户或当前任务明确授权使用 subagents / parallel agent work。
- 主 agent 先给出拆分计划，并为每个 worker 指定唯一 owner。
- 每个 worker 有 disjoint write set：允许写入路径、禁止路径、共享文件处理方式、验证命令和交付格式都必须写清楚。
- 任一共享文件只能有一个 owner；无法独占的共享文件由主 agent 串行编辑。
- 每个 worker 必须知道自己不是唯一协作者，不得 revert、format 或重写非 owner 范围。
- worker 完成后必须列出改动文件、验证命令、未验证项和需要主 agent 决策的冲突。

不适合并行写入的范围：

- `tasks/prompts/**` live queue、manifest、`tasks/prompts/_shared/progress.json`。
- `.codex/task-loop-logs/**`、`.codex/task-loop-runs/**`、task-loop lock、checkpoint evidence。
- DB schema、migration、rollback、staging recovery、reindex、FSEvents、iCloud、隐私或 AI 远程调用。
- Core API / UDL / Swift bridge 的破坏性变化。
- `Cargo.lock`、SwiftPM lockfile、CI workflow、global config、CODEOWNERS 等需要全局一致性的共享文件，除非明确指定单一 owner。

## Live Runner 规则

当 `./task-loop` 正在运行，或某个 live task 处于 in-progress / stale / repair 状态时：

- 不把同一 live task 拆给多个 writer。
- 不让 subagent 修改 progress、logs、run summaries、checkpoint、branch、commit、stash、reset 或 clean。
- 不让 subagent 启动第二个 runner，也不调用会继续、重置或清理 live runner 状态的命令。
- 如果需要并行分析当前失败，最多使用只读 explorer 分析静态代码、文档或测试输出片段；live 状态、恢复语义和最终操作仍由主 agent 处理。

## 主 Agent 复核

Subagent 返回后，主 agent 必须：

1. 复核 subagent 的文件引用、范围和假设。
2. 检查 diff 是否只落在允许路径和对应 owner 范围内。
3. 解决 write set 冲突、共享文件冲突和验证缺口。
4. 运行与最终合并后状态匹配的验证，而不是只复述 worker 的验证。
5. 最终报告改了什么、为什么这样改、跑了哪些验证、还有哪些风险或未验证项。

没有主 agent 复核和最终验证，subagent 结果不得作为 AreaMatrix task 完成、checkpoint 成功、CI 通过或 merge-ready 的证据。
