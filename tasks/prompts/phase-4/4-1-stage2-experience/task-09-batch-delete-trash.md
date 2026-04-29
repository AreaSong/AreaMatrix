# 4-1/task-09: C2-09 batch-delete-trash

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现批量删除确认所需的 preview 与 Trash 删除能力。

## 绑定

- Core 能力：C2-09 batch-delete-trash
- UX 页面：S2-13, S2-10

## 核对清单

1. 批量删除前生成影响预览。
2. Copy/Move 文件进入 Trash；Indexed/Missing 只移除索引。
3. Trash 不可用时禁用删除。
4. 写入 change log 和 undo action。

## 完成标准

- Stage 2 不提供永久删除。
- 失败项不被当作成功删除。

## 验证

```bash
./scripts/check-all.sh
```
