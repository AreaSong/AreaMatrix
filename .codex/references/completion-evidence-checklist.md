# Completion Evidence Checklist

AreaMatrix 吸收 `verification-before-completion` 的方式是完成声明证据纪律，不新增同义 skill，不引入外部 runtime。

## 适用时机

在任何人准备声称以下状态前，必须先使用本清单：

- 完成、已修复、通过、可提交、可合并、可交付。
- task-loop 可以进入下一项。
- commit、push、PR 或 release-ready。
- 本地验证、远端 CI、review、security 或 dependency gate 已经满足。

## 必填证据

完成报告必须说明：

- 改了什么：列出核心路径、行为或文档规则变化。
- 为什么这样改：说明对齐的 task、manifest、docs、governance 或风险边界。
- 跑了哪些验证：写出真实命令、退出状态和关键结果。
- 验证是否新鲜：必须是本轮工作后重新执行；旧日志、历史记忆和别的 agent 报告只能作为背景。
- 哪些检查没跑：逐条写命令或检查名，并给出具体原因。
- 剩余风险：说明未覆盖场景、环境限制、人工 review 或 CI 缺口。
- Blocker 状态：明确 review、security、dependency、CI、Git evidence 是否还有阻断项。

## 判定规则

- 没有新鲜验证证据时，不得宣称完成。
- 命令失败、环境无法运行或输出不能证明目标时，结论必须是 `FAIL`、`BLOCKED` 或 `NOT-READY`。
- Dry-run 只能证明 runner、prompt 生成、风险门禁或日志链路，不能证明产品实现、业务闭环或任务完成。
- 单个验证通过不能覆盖其他门禁；review、security、dependency、CI 或 Git evidence blocker 会让 `PASS` 降级。
- Agent 自述、旧日志、截图、mock-only、fixture-only、hardcoded success path 都不能作为真实完成证据。

## 最小报告骨架

```text
改了什么:
- <核心路径和行为变化>

为什么这样改:
- <对应 task/docs/governance/风险边界>

已运行验证:
- <command>: <fresh result>

未运行验证:
- <command or check>: <concrete reason>

Blocker:
- Review: clear / blocked / not-applicable
- Security: clear / blocked / not-applicable
- Dependency: clear / blocked / not-applicable
- CI: clear / blocked / not-applicable
- Git evidence: clear / blocked / not-applicable

结果:
- PASS / FAIL / BLOCKED / NOT-READY

剩余风险:
- <remaining risk or None>
```
