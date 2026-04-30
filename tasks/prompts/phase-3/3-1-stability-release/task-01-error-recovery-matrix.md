# 3-1/task-01: error recovery matrix

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

建立 Stage 1 MVP 的 error recovery matrix（错误恢复矩阵）。本任务只做稳定性验收定义、测试证据或开发文档，不补产品功能。

## 绑定

- 阶段级稳定性任务；不绑定单个 UX 页面或 Core 能力。
- 必须覆盖 Core 错误码、UX 错误文案、事务式导入和 troubleshooting 的对应关系。

## 核对清单

1. 读取 `docs/api/error-codes.md`、`docs/ux/error-messages.md`、`docs/architecture/transactional-import.md` 和 `docs/development/troubleshooting.md`。
2. 梳理每类 Stage 1 错误的来源、用户可见文案、恢复动作、诊断入口和阻断级别。
3. 覆盖至少以下错误域：repo path、permission、DB、IO、iCloud placeholder、duplicate、conflict、staging recovery、internal。
4. 检查 Core 错误码与 UX 错误文案是否存在无主项、缺失项或语义冲突。
5. 检查事务式导入失败路径是否都有恢复或清理策略，不允许留下最终目录半成品。
6. 只补测试、脚本或 `docs/development/**` 下的发布/稳定性证据；不新增产品功能。

## 完成标准

- 已形成可追溯的 error recovery matrix，能从错误码追到 UX 文案、恢复动作、测试或手工验证证据。
- 所有发现的 P0/P1 恢复缺口都有明确阻断结论；不能包装成“后续优化”。
- 与 Core、Swift UI、脚本或文档现状不一致的地方已记录证据和回退到 Phase 1/2 的任务建议。
- Validation 全部运行；若某项命令因环境缺失无法运行，必须说明原因并提供替代证据。

## 验证

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
cargo test --workspace recovery
cargo test --workspace error_mapping
```
