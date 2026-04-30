# 4-3/task-04: C4-04 camera-import core contract

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

实现 C4-04 camera-import 的 Core 能力合同。

## 绑定

- Core 能力：C4-04 camera-import

## 核对清单

1. 只实现该 C 能力合同。
2. 不接入具体页面 UI。
3. 不实现相邻阶段能力。

## 完成标准

- C4-04 能力可被后续页面 task 消费。
- API、错误和副作用与 capability spec 一致。

## 验证

```bash
./scripts/check-all.sh
```
