# 4-2/task-07: C3-07 ai-tags-suggestion

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 AI 标签建议能力，并复用 Stage 2 标签 CRUD 与批量添加路径。

## 绑定

- Core 能力：C3-07 ai-tags-suggestion
- UX 页面：S3-07

## 核对清单

1. 返回建议标签、confidence、理由摘要和是否已存在。
2. 接受建议时复用真实 tag CRUD / batch add tags 能力。
3. 拒绝建议要可记录，用于后续降低相似建议权重。
4. AI 标签建议不得绕过标签命名校验和冲突处理。

## 完成标准

- S3-07 可完成建议、接受、拒绝、批量应用闭环。
- 标签写入后能被搜索、过滤和详情页读取。

## 验证

```bash
./scripts/check-all.sh
```

