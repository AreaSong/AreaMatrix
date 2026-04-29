# 1-2/task-01: C1-05 classify-preview

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现无副作用分类预览，供导入 sheet 和分类设置页消费。

## 绑定

- Core 能力：C1-05 classify-preview
- UX 页面：S1-16, S1-17, S1-18, S1-19, S1-28

## 核对清单

1. `predict_category` 读取规则并返回 category、suggested_name、reason、confidence。
2. 关键词优先于扩展名，未命中时落到 inbox/default。
3. 规则加载失败有可理解错误或安全 fallback。
4. 调用不写 DB、不写文件、不创建目录。

## 完成标准

- 分类规则、命名建议、fallback 路径都有测试。
- UI 可以直接使用结果填充导入确认信息。
- Stage 3 AI 分类不在本任务中实现。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace classify
```
