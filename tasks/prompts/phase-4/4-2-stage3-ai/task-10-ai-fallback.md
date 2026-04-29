# 4-2/task-10: C3-10 ai-fallback

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 AI 不可用、超时、隐私阻断和 provider 失败时的统一降级合同。

## 绑定

- Core 能力：C3-10 ai-fallback
- UX 页面：S3-10

## 核对清单

1. 区分本地模型不可用、远程未启用、隐私阻断、超时和 provider 错误。
2. 降级后核心文件管理、搜索、导入和标签能力仍可用。
3. UI 能显示可操作的下一步，而不是只显示通用失败。
4. 降级事件写入 AI 调用日志或系统事件日志。

## 完成标准

- S3-10 覆盖全部 AI 失败和降级状态。
- Stage 3 的 AI 能力失败不会破坏 Stage 1/2 闭环。

## 验证

```bash
./scripts/check-all.sh
```

