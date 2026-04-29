# 4-1/task-02: C2-02 search-filters

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现搜索过滤与 facet 能力，支撑 filter popover 和标签筛选。

## 绑定

- Core 能力：C2-02 search-filters
- UX 页面：S2-02, S2-08

## 核对清单

1. 支持 category、tag、date range、storage mode、include deleted 等过滤。
2. filter facet/count 可供 UI 展示。
3. 日期非法、标签不存在等状态结构化返回。
4. 普通搜索即时生效，Smart List 编辑只更新 draft。

## 完成标准

- 过滤只改变查询条件，不创建、删除或修改标签。
- filter 组合和空结果路径可验收。

## 验证

```bash
./scripts/check-all.sh
```
