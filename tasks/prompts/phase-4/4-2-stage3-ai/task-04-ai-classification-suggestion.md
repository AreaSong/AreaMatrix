# 4-2/task-04: C3-04 ai-classification-suggestion

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 AI 分类建议能力，只产生建议，不直接替用户修改分类。

## 绑定

- Core 能力：C3-04 ai-classification-suggestion
- UX 页面：S3-04

## 核对清单

1. AI 仅在规则分类失败、低置信度或用户主动请求时参与。
2. 返回建议分类、confidence、理由摘要和使用的输入类型。
3. 接受建议与拒绝建议必须记录为可追踪事件。
4. 远程 AI 未启用时不得把用户内容发出本机。

## 完成标准

- S3-04 可展示真实 AI 分类建议并完成接受/拒绝闭环。
- 分类变更仍通过已有 Core 分类更新路径完成。

## 验证

```bash
./scripts/check-all.sh
```

