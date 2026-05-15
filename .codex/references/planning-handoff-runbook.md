# Planning Handoff Runbook

本 runbook 吸收 Vibe-Skills `writing-plans` 的 handoff-safe planning 方法价值，但不新增同义 skill、不安装 Vibe runtime、不改变 AreaMatrix live queue。

## 适用场景

- 生成或评审 `workflow/versions/v*/plans/**`。
- 生成或评审 `workflow/versions/v*/drafts/**`、`queue/**`、promotion preview。
- 维护 `tasks/backlog/**` 的 copy-ready / verify-ready prompt 包。
- 把已批准需求拆成未来可 promotion 的任务候选。

## Source of Truth

- 产品、架构、API、UX、开发规范：`docs/**`。
- AI 协作与风险规则：`.ai-governance/**`。
- Workflow 生命周期：`workflow/**`。
- Backlog prompt 包：`tasks/backlog/**`，只作候选和手工复制材料。
- Live queue：`tasks/prompts/**`，只有 workflow promotion 通过后才可写入。

## 必填字段

每个 planning handoff artifact 至少写清：

- 目标：本计划要交付什么。
- 非目标：明确不做什么，尤其是不进入 live queue 的边界。
- Source of truth：列出精确文档、规则、change、middle-layer 或 backlog 来源路径。
- Owner / landing：说明由哪个 AreaMatrix skill / workflow layer 承接，落在哪些路径。
- 精确文件路径：按 create / modify / test / docs / prompt draft 分组列出。
- 执行顺序：按小步、可检查的顺序排列，不用“补齐相关逻辑”这类模糊动作。
- 验证命令：写出真实命令；无法运行时必须说明 blocker 和替代证据。
- Rollback / blocked 口径：说明失败时停在哪一层、如何回滚或保持 blocked。

## Copy-ready / Verify-ready 分离

- `copy-ready` 只描述实施任务：允许范围、禁止范围、读取顺序、执行步骤、验证命令、完成汇报字段。
- `verify-ready` 只描述只读验收：禁止修改文件，按 source of truth、manifest / draft、实际文件和验证证据逐项核验。
- 两者不得混写。verify-ready 发现不通过时输出 FAIL / blocker，不在同一 prompt 中修复。

## Backlog 边界

- `tasks/backlog/**` 不是 live queue，不由 `./task-loop` 执行。
- Backlog prompt 不写 `tasks/prompts/**`，不写 `tasks/prompts/_shared/progress.json`，不创建 checkpoint、run summary、runner lock 或 promotion state。
- Backlog prompt 只能作为候选材料；进入 live queue 必须经过 `workflow/` planning gate、promotion preview 和明确批准。

## Blocked / Rollback 口径

- 计划缺少 source of truth、精确路径或验证命令时，状态写 `blocked` 或 `not-ready`。
- 命中用户文件、DB、migration、Core API / UDL、隐私或远程调用等高风险边界时，先说明影响、风险、验证和回滚，再等待确认。
- 预览层 artifact 写错时，只回滚预览或 backlog 文件；不得通过直接改 live queue “修正”。
- promotion preview 无 live mapping 时保持 `promotion_preview.live_mapping: pending`，不要抢占 live task label。

## 推荐验证

```bash
./dev check skills
./dev check governance
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./dev workflow doctor
git diff --check -- workflow .codex/references .codex/skills-src tasks/backlog
```
