# Agent Principles

> AreaMatrix 的 AI 协作基础原则：中文沟通、文档优先、可验证推进。

## 语言

- 对话、任务说明、设计说明、提交说明默认中文。
- 代码标识符、类型名、函数名、模块名保持英文。
- 技术术语首次出现时，优先附一个简短中文解释。

## 执行顺序

1. 先读当前任务命中的 `AGENTS.md` 链。
2. 再读任务列出的文档和 manifest。
3. 明确边界、风险和验证方式。
4. 执行最小必要改动。
5. 运行与改动范围匹配的检查。
6. 汇报改了什么、为什么、验证了什么、剩余风险是什么。

## OpenAI / Codex 信息核对

- 任务涉及 OpenAI、Codex、model、API、SDK、hooks、MCP、skills、plugins、Computer Use 或其他 OpenAI 运行层能力时，默认先核对 OpenAI 官方文档；可用时优先使用 `openaiDeveloperDocs` Docs MCP。
- 回答“最新”“当前”“默认”“是否仍支持”等易变化问题前，必须重新核对官方文档或官方 OpenAI 域名，不把记忆、旧本地笔记或历史运行经验当作最新事实。
- OpenAI 官方文档只用于判断 OpenAI / Codex 运行层能力、限制和推荐做法；它不替代 AreaMatrix 产品、架构、API、UX 和开发规范的 `docs/**` 源事实。
- 不写死易过期的模型、价格、地区、配额、功能状态或 release 阶段；确需记录时，必须同时标注核对日期和官方来源。
- OpenAI Docs MCP 是只读文档入口，不是 OpenAI API 调用凭证；不得把 token、auth 配置或个人全局 `~/.codex/**` 内容写入仓库。

## 任务分级

- Quick：范围小、风险低、已有模式清楚，可直接处理。
- Change：跨文件、跨层或需要设计取舍，先计划再执行。
- Mission-Critical：涉及用户文件安全、DB/migration、staging recovery、FSEvents/iCloud、隐私或 Core API 破坏性变化，必须先确认。

## 调试与失败归因

- 原因不明的失败先复现、收证、分层归因、提出单一可证伪假设，再修复。
- 不把 copy、verify、validation command、runner、Git checkpoint、docs/API/UDL/prompt 漂移或文件安全边界混成一个笼统的“失败”。
- task-loop 失败先看 `./dev status --verbose`、`./task-loop status`、`tasks/prompts/_shared/progress.json`、run summary、copy / verify logs，再决定归因层。
- 失败跨越多组件时，先检查组件边界的输入、输出、配置和状态传播；不要直接在最深层症状处补丁。
- 调试和归因参考 `.codex/references/debugging-failure-attribution-runbook.md`；具体 owner 仍由 repo-local skills 分担。

## 编码习惯

- 遵循 KISS、YAGNI、高内聚低耦合。
- 单函数尽量不超过 50 行，单文件尽量不超过 500 行，嵌套尽量不超过 3 层。
- 注释解释 why，不重复 what。
- 不引入无需求支撑的抽象层。

## 完成门禁

- 没有验证，不宣称完成。
- 检查失败时先修复；无法修复或无法运行时，明确说明阻塞原因。
- 发现文档与代码冲突时，记录冲突来源，并优先让代码回到文档定义的行为。
- 声称完成、修复、通过、可提交、可合并或可交付前，必须提供完成证据清单：改了什么、为什么这样改、跑了哪些验证、验证是否为本轮新鲜结果、哪些检查没跑及具体原因、剩余风险。
- Dry-run 只能证明 runner、prompt 生成、风险门禁或日志链路，不能替代真实产品实现、真实业务闭环或真实验证命令。
- Review、security、dependency、CI 或 Git evidence 存在 blocker 时，即使命令局部通过，也不能报告 `PASS`；必须降级为 `BLOCKED` 或 `NOT-READY`，并说明阻断层与补齐方式。

## Review 与安全分析

- Code review 输出必须 findings first：先列 correctness、regression risk、missing tests、security / privacy / user-file risk，再写摘要；没有 finding 时也要说明剩余风险或未验证项。
- 普通 review 中发现明显安全风险时，作为 review finding 处理，并说明是否需要升级为 explicit threat model。
- Threat model 只在用户 / 任务明确要求，或命中用户文件、DB、staging、reindex、FSEvents / iCloud、隐私、远程 AI 调用等高风险边界时触发。
- Threat model 必须覆盖资产、信任边界、入口、攻击能力、abuse path、缓解措施和 residual risk；它不能替代普通 review、验证或 CI。
