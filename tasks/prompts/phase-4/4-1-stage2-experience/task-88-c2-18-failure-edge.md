# 4-1/task-88: C2-18 failure-edge

> 共享规则：`tasks/prompts/_shared/audit-rules.md`
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`

## 任务类型

atomic

## 范围

补齐 C2-18 redo-action-log 的失败、边界和回滚语义。

## 绑定

- Core 能力：C2-18 redo-action-log
- 能力类型：Undo / Redo
- 阶段：Stage 2 Experience
- Core 步骤：失败与边界

## 核对清单

1. 覆盖空态、非法输入、权限、IO/DB 错误和错误码映射。
2. 涉及写入、移动、删除、导入或同步时，必须证明失败不留下半成品。
3. 涉及隐私/AI/远程调用时，必须证明默认关闭、密钥不入日志。
4. 不得用吞错或静默降级掩盖失败。

## 完成标准

- C2-18 的失败路径有明确返回、可测试证据和用户文件安全保证。
- 高风险路径具备可回滚或可恢复说明。

## 验证

```bash
./dev check all
```
