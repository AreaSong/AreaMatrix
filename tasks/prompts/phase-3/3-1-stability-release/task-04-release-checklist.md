# 3-1/task-04: release checklist

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

建立 Stage 1 MVP 的 release checklist（发布清单）和 alpha 分发前验收证据。本任务只补发布门禁、脚本检查或发布文档证据，不补产品功能。

## 绑定

- 阶段级发布任务；不绑定单个 UX 页面或 Core 能力。
- 依赖 `3-1/task-03` 的性能基线作为发布检查项之一。

## 核对清单

1. 读取 `docs/development/release.md`、`docs/development/build.md`、Stage 1 MVP 验收清单和 `CHANGELOG.md`。
2. 对齐发布前检查项：CI/check-all、P0/P1、手工冒烟、性能基线、依赖 dry-run、文档/API 一致性、CHANGELOG、版本号。
3. 明确 alpha 分发状态：签名、公证、DMG、干净 Mac 首启、已知问题、反馈渠道。
4. 对每个发布项记录状态：通过、不通过、不适用或无法验证；无法验证项必须说明原因和发布风险。
5. 任一 P0/P1、check-all 失败、冒烟未跑、性能基线缺失或签名/公证状态不明时，不得放行最终集成验收。
6. 只补脚本、测试或 `docs/development/**` 下的发布证据；不修改产品实现。

## 完成标准

- 发布 checklist 能直接回答 MVP 是否可 alpha 分发。
- `CHANGELOG.md`、release/build 文档、Stage 1 MVP 验收清单之间没有未解释冲突。
- P0/P1、CI、冒烟、性能、签名/公证、DMG 干净机启动状态都有明确结论。
- Validation 全部运行；失败或无法运行项必须阻断或记录明确豁免依据。

## 验证

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
./scripts/check-all.sh
cargo update --dry-run
git diff --check
```
