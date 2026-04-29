# 4-1/task-01: C2-01 search-query-files

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Stage 2 搜索查询核心能力，覆盖文件名、路径、笔记、分类和改动历史搜索。

## 绑定

- Core 能力：C2-01 search-query-files
- UX 页面：S2-01, S2-04, S2-05

## 核对清单

1. `search_files` 支持查询字符串、分页、排序和基础 query diagnostics。
2. 文件名、相对路径、笔记、分类、change log 能被检索。
3. 0 结果和 query parse error 返回不同结构化状态。
4. 搜索不修改文件、标签、分类或配置。

## 完成标准

- 搜索结果、空态、查询错误都能由真实 Core 数据驱动。
- Stage 3 语义搜索/OCR 不混入本任务。

## 验证

```bash
./scripts/check-all.sh
```
