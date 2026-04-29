# 4-1/task-16: C2-16 icloud-conflict-visual

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 iCloud 冲突可视化增强能力，包含版本预览和安全解决报告。

## 绑定

- Core 能力：C2-16 icloud-conflict-visual
- UX 页面：S2-20, S1-36

## 核对清单

1. `preview_conflict_versions` 返回版本 metadata 和可预览摘要。
2. `resolve_icloud_conflict` 默认 Keep both。
3. 丢弃版本必须走 Trash，不直接删除。
4. 解决失败保持 unresolved 状态。

## 完成标准

- 不自动删除任一冲突版本。
- 预览失败不能继续 destructive resolution。

## 验证

```bash
./scripts/check-all.sh
```
