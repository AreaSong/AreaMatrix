# 4-3/task-03: C4-03 mobile-library-query

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现移动端资料库列表查询能力，复用 Core list/search/detail 数据模型。

## 绑定

- Core 能力：C4-03 mobile-library-query
- UX 页面：S4-IOS-02

## 核对清单

1. 支持分页、排序、分类筛选和基础搜索。
2. 返回移动端所需缩略信息，不强制加载大文件内容。
3. 空态、加载态、权限失效和仓库断开状态可区分。
4. 查询结果与桌面端数据库语义一致。

## 完成标准

- S4-IOS-02 由真实 Core 数据驱动。
- 移动端查询不会触发危险文件写入。

## 验证

```bash
./scripts/check-all.sh
```

