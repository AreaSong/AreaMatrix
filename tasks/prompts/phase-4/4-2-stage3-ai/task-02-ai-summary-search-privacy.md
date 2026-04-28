# 4-2/task-02: AI 摘要、搜索与隐私控制

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

Stage 3 粗粒度任务：自动摘要、自动标签、语义搜索和隐私控制。

## 核对清单

1. AI 摘要和标签结果可编辑、可清除。
2. 远程模型必须由用户显式配置 key 并启用。
3. 支持“不发送到 AI”的目录或关键词规则。
4. AI 失败时回退到本地规则和普通搜索。

## 完成标准

- AI 能力是可选增强，不成为核心功能依赖。

## 验证

```bash
./scripts/check-all.sh
```

