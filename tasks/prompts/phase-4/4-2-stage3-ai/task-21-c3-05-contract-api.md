# 4-2/task-21: C3-05 contract-api

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

为 C3-05 ai-call-log 对齐 Core API / UDL 合同，不实现业务逻辑。

## 绑定

- Core 能力：C3-05 ai-call-log
- 能力类型：Audit
- 阶段：Stage 3 AI
- Core 步骤：合同/API

## 核对清单

1. 读取 C3-05 能力规格、Stage 3 AI control map、Core API 和错误码。
2. 确认 API 名称、输入、输出、错误码、权限/隐私边界与能力规格一致。
3. 只补合同、类型、桥接声明或文档缺口，不实现相邻能力。
4. 记录当前页面消费方是否能从合同中得到所需状态。

## 完成标准

- C3-05 的 Core API 合同可被后续 implementation task 直接实现。
- 合同没有引入 control map 之外的页面能力。

## 验证

```bash
./dev check all
```
