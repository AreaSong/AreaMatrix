# 4-1/task-05: C2-05 tag-crud

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现单文件标签增删查，支撑添加标签 popover 和标签筛选。

## 绑定

- Core 能力：C2-05 tag-crud
- UX 页面：S2-07, S2-08

## 核对清单

1. `add_tag/remove_tag/list_tags` 或等价 API 完整。
2. 标签名称校验、去重、排序稳定。
3. 标签写入 `tags` 与 change log。
4. 标签不改变分类和文件路径。

## 完成标准

- 单文件添加、移除、重复添加、非法标签均有验证。
- UI 可用真实 tag set 渲染。

## 验证

```bash
./scripts/check-all.sh
```
