# 4-3/task-07: C4-07 mobile-detail

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现移动端文件详情能力，覆盖元数据、笔记、改动历史和可预览状态。

## 绑定

- Core 能力：C4-07 mobile-detail
- UX 页面：S4-IOS-05

## 核对清单

1. 详情数据复用 Core `get_file_detail`、note 和 change log 语义。
2. 可预览状态、文件缺失、权限失效和 iCloud 未下载可区分。
3. 移动端 note 编辑与桌面端数据一致。
4. 不在详情页默认加载超大文件内容。

## 完成标准

- S4-IOS-05 能展示真实详情并保存 note。
- 移动端详情不破坏桌面端元数据。

## 验证

```bash
./scripts/check-all.sh
```

