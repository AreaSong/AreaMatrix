# 4-1/task-19: C2-19 tag-suggestions

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 Stage 2 非 AI 标签建议闭环。

## 绑定

- Core 能力：C2-19 tag-suggestions
- UX 页面：S2-23

## 核对清单

1. 基于文件名、相对路径和来源目录生成标签建议。
2. 不读取文件正文，不调用 AI，不发生网络访问。
3. 采纳建议复用 tag CRUD / batch add tags 能力。
4. 忽略建议不写标签关系，但可记录为轻量反馈。

## 完成标准

- S2-23 可展示、采纳、忽略真实标签建议。
- 采纳后的标签可被搜索、筛选、详情页和 undo 读取。

## 验证

```bash
./scripts/check-all.sh
```

