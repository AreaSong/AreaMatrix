# 4-1/task-10: C2-10 batch-rename-preview

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现批量重命名 preview + execute 闭环。

## 绑定

- Core 能力：C2-10 batch-rename-preview
- UX 页面：S2-14, S2-10

## 核对清单

1. 预览 old/new name 覆盖每个文件。
2. 冲突和非法名称阻止执行或逐项标记。
3. Copy/Move rename 文件，Indexed 只改显示名。
4. 写 change log 和 undo action。

## 完成标准

- 没有预览不得执行批量重命名。
- 成功后可撤销。

## 验证

```bash
./scripts/check-all.sh
```
