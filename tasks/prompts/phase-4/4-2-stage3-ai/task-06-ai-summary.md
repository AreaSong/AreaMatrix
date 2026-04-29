# 4-2/task-06: C3-06 ai-summary

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现文件 AI 摘要生成与用户编辑保存合同，不覆盖用户手写笔记。

## 绑定

- Core 能力：C3-06 ai-summary
- UX 页面：S3-06

## 核对清单

1. `generate_ai_summary` 返回摘要草稿、来源能力、本地/远程标记和 confidence。
2. 摘要草稿与用户 note 分离存储，保存前不得覆盖用户内容。
3. 用户可编辑、接受、放弃或重新生成摘要。
4. 对不可解析文件返回结构化错误和降级提示。

## 完成标准

- S3-06 完成生成、编辑、保存、放弃的真实闭环。
- AI 摘要不会破坏现有 note 和 change log。

## 验证

```bash
./scripts/check-all.sh
```

