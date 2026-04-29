# 4-2/task-01: C3-01 ai-settings-config

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现 AI 设置配置的真实读写合同，作为 Stage 3 所有 AI 能力的入口门禁。

## 绑定

- Core 能力：C3-01 ai-settings-config
- UX 页面：S3-01

## 核对清单

1. `get_ai_settings` 返回本地模型、远程模型、隐私模式、语义搜索等开关状态。
2. `update_ai_settings` 支持局部更新，并保留未提交设置的校验错误。
3. 远程 AI 默认关闭，启用前必须记录用户明确选择。
4. 设置变更写入配置后能被后续 AI 调用读取。

## 完成标准

- S3-01 AI 设置页由真实 Core 设置驱动。
- 未启用远程 AI 时不得发生网络调用。

## 验证

```bash
./scripts/check-all.sh
```

