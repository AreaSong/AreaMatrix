# 4-1/task-01: Tags、Search 与 Conflict UI

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

Stage 2 粗粒度任务：标签系统、全文搜索和冲突解决 UI。

## 核对清单

1. 标签数据模型和 UI 筛选对齐。
2. 文件名、备注、改动历史搜索可用。
3. iCloud 冲突和同名导入冲突有可视化决策。
4. 不破坏 Stage 1 已有导入与同步能力。

## 完成标准

- Stage 2 体验功能形成可用闭环。
- 对 DB schema 变化有 migration。

## 验证

```bash
./scripts/check-all.sh
```

