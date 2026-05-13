# 4-1/task-27: C2-06 implementation

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

实现 C2-06 batch-add-tags 的最小 Core 行为闭环。

## 绑定

- Core 能力：C2-06 batch-add-tags
- 能力类型：Batch
- 阶段：Stage 2 Experience
- Core 步骤：实现

## 核对清单

1. 只实现 C2-06，不得顺手实现同阶段其他 C* 能力。
2. 按能力规格落实输入、输出、DB/文件系统变化和错误映射。
3. 保持 Rust Core 不依赖平台 UI API。
4. 必要时补最小测试支撑，但不做页面接入。

## 完成标准

- C2-06 的核心行为可被测试或桥接调用验证。
- 未触碰用户文件安全边界之外的行为。

## 验证

```bash
./dev check all
```
