# 4-3/task-100: C4-20 integration-verify

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

integration

## 范围

只读验收 C4-20 repository-settings-cross-platform 的 Core 能力闭环。

## 绑定

- Core 能力：C4-20 repository-settings-cross-platform
- 能力类型：Settings
- 阶段：Stage 4 Multiplatform
- Core 步骤：能力集成验收

## 核对清单

1. 交叉检查 capability spec、Core API、UDL、Rust 实现和测试。
2. 确认消费页面需要的状态、错误和副作用均已覆盖。
3. 确认没有实现 control map 之外的能力。
4. 不得修改文件；只记录验收证据和阻塞项。

## 完成标准

- C4-20 可以作为后续 page-feature task 的真实 Core 依赖。
- 若无法证明，明确阻塞后续 UI 接入。

## 验证

```bash
./dev check all
```
