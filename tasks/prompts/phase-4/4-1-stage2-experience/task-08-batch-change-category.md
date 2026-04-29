# 4-1/task-08: C2-08 batch-change-category

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现批量改分类 preview + execute 闭环。

## 绑定

- Core 能力：C2-08 batch-change-category
- UX 页面：S2-12, S2-10

## 核对清单

1. 执行前生成每个文件目标路径预览。
2. Copy/Move 文件安全移动，Indexed 只改元数据。
3. 冲突、权限失败、未知分类逐项报告。
4. 写入 change log 和 undo action。

## 完成标准

- 没有预览不得执行。
- 部分失败不会静默跳过。

## 验证

```bash
./scripts/check-all.sh
```
