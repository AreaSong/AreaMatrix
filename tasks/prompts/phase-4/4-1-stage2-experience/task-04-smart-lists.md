# 4-1/task-04: C2-04 smart-lists

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Smart List 运行和列表能力，支撑 sidebar 与 command palette 入口。

## 绑定

- Core 能力：C2-04 smart-lists
- UX 页面：S2-06, S2-15

## 核对清单

1. `run_smart_list` 复用 saved search 条件。
2. Smart List 结果分页、排序和普通搜索一致。
3. Rename/Delete/Duplicate 只影响 saved search 记录。
4. Command palette 可发现 Smart List。

## 完成标准

- 打开 Smart List 不移动、不删除、不改名任何文件。
- 缺失 saved_search_id 有结构化错误。

## 验证

```bash
./scripts/check-all.sh
```
