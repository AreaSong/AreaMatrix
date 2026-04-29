# 4-2/task-08: C3-08 semantic-search

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现语义搜索能力，并与 Stage 2 普通搜索结果合并展示。

## 绑定

- Core 能力：C3-08 semantic-search
- UX 页面：S3-08

## 核对清单

1. 支持构建和刷新文件向量索引，索引失败不影响普通搜索。
2. `semantic_search` 返回结果、score、匹配理由和降级原因。
3. 未启用 AI 或模型不可用时回退普通搜索并说明原因。
4. 搜索结果不得泄露未被授权索引的文件内容。

## 完成标准

- S3-08 可展示真实语义搜索结果和降级状态。
- 语义搜索与普通搜索排序、分页、过滤关系清晰可测。

## 验证

```bash
./scripts/check-all.sh
```

