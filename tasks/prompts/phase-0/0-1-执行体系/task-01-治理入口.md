# 0-1/task-01: 治理入口

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-0.md`

## 范围

建立 AreaMatrix 的 AI 协作入口和轻量治理源事实，不创建产品代码。

## 核对清单

1. 根 `AGENTS.md` 明确入口顺序、SSOT、高风险边界和验证要求。
2. `.ai-governance/` 声明统一源事实，并覆盖通用原则、项目规则和 prompt runtime。
3. `.codex/` 只承载 Codex 适配材料，不和 `.ai-governance/` 抢权威。
4. 不创建空的 `core/AGENTS.md` 或 `apps/macos/AGENTS.md`。

## 完成标准

- 新协作入口能说明“先读哪里、哪些事高风险、完成后如何验证”。
- 治理材料和现有 `docs/` 没有明显冲突。

## 验证

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
```

