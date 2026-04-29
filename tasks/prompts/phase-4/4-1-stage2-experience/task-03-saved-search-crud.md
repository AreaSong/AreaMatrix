# 4-1/task-03: C2-03 saved-search-crud

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现保存搜索 CRUD，支撑保存搜索 sheet 和 Smart List 管理。

## 绑定

- Core 能力：C2-03 saved-search-crud
- UX 页面：S2-03, S2-06

## 核对清单

1. 新增 saved search 表或等价持久化结构。
2. 支持 create/update/delete/list saved search。
3. 保存 query、filters、sort、scope。
4. 删除 Smart List 只删除保存查询，不影响任何文件。

## 完成标准

- 保存后能从 sidebar 恢复同一搜索条件。
- 名称重复、非法 query、保存失败都有结构化错误。

## 验证

```bash
./scripts/check-all.sh
```
