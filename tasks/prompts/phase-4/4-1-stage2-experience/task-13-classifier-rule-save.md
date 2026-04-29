# 4-1/task-13: C2-13 classifier-rule-save

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-4.md`

## 范围

实现分类规则保存能力，支撑纠错沉淀规则。

## 绑定

- Core 能力：C2-13 classifier-rule-save
- UX 页面：S2-17

## 核对清单

1. 支持关键词/扩展名/目标分类/优先级规则。
2. 原子更新 classifier 配置。
3. 过宽或重复规则结构化 warning。
4. 保存规则不自动应用到历史文件。

## 完成标准

- 配置损坏时可保留旧版本。
- 保存规则与 impact preview 分离。

## 验证

```bash
./scripts/check-all.sh
```
