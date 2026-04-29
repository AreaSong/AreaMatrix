# 4-2/task-09: C3-09 ai-privacy-rules

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 AI 隐私规则能力，定义哪些文件、目录、字段和能力允许进入 AI 流程。

## 绑定

- Core 能力：C3-09 ai-privacy-rules
- UX 页面：S3-09

## 核对清单

1. 支持全局禁用远程 AI、路径排除、文件类型排除和敏感字段过滤。
2. 每次 AI 调用前必须执行隐私规则判定。
3. 被阻止的调用返回可解释错误，不静默失败。
4. 规则变更后影响后续调用，不追溯修改已有日志。

## 完成标准

- S3-09 能配置并验证真实隐私规则。
- 任何 AI 能力都不能绕过隐私规则。

## 验证

```bash
./scripts/check-all.sh
```

