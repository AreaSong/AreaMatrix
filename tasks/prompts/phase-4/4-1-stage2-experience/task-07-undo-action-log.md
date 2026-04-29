# 4-1/task-07: C2-07 undo-action-log

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Undo action log，支撑 Undo toast 和历史面板。

## 绑定

- Core 能力：C2-07 undo-action-log
- UX 页面：S2-10, S2-11

## 核对清单

1. 支持 `list_undo_actions` 与 `undo_action`。
2. 移动、重命名、删除、改分类等可生成 undo action。
3. 外部 FSEvents 变化不可撤销时明确标记。
4. Undo 失败不破坏当前状态。

## 完成标准

- Undo 历史可分页查看。
- 反向 change log 可追溯。

## 验证

```bash
./scripts/check-all.sh
```
