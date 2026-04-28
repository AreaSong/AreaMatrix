# 1-2/task-01: Classifier Rules

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现 `classifier.yaml` 加载、默认 10 类、extension + keyword 匹配和 inbox 兜底。

## 核对清单

1. keyword 优先于 extension。
2. 支持中文关键词、大小写不敏感、Unicode NFKC 归一。
3. 无效 yaml 时保留旧规则或返回明确错误。
4. `predict_category` 与 API 文档一致。

## 完成标准

- 分类测试覆盖关键规则和边界。
- 默认规则与 `docs/api/classifier-yaml.md` 一致。

## 验证

```bash
cd core
cargo test --workspace classify
```

