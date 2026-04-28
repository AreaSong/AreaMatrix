# 4-2/task-01: 本地 AI 分类

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

Stage 3 粗粒度任务：接入本地 AI 分类，并保持离线优先。

## 核对清单

1. 本地模型作为默认路径，远程模型默认关闭。
2. AI 只在规则分类失败或低置信度时介入。
3. 结果带 confidence，用户可回退到 inbox。
4. AI 调用日志可见且不泄露敏感内容。

## 完成标准

- 无网络也能完成核心分类流程。
- 隐私承诺没有被破坏。

## 验证

```bash
./scripts/check-all.sh
```

