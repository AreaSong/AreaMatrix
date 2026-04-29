# 4-1/task-17: C2-17 import-conflict-batch

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Stage 2 同名导入冲突的批量决策闭环。

## 绑定

- Core 能力：C2-17 import-conflict-batch
- UX 页面：S2-21

## 核对清单

1. 导入会话能聚合同名、重复 hash 和 replace 风险项。
2. 支持 Skip、Keep both、Replace、Ask per item 等批量策略预览。
3. Replace 必须二次确认，并写入 change log / undo action。
4. 批量策略失败时保留 staged 文件和冲突状态。

## 完成标准

- S2-21 可由真实导入冲突数据驱动。
- 默认策略保护用户文件，不静默覆盖。

## 验证

```bash
./scripts/check-all.sh
```

