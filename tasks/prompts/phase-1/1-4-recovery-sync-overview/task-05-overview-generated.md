# 1-4/task-05: C1-20 overview-generated

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现自动概览生成策略，默认写入 `.areamatrix/generated/`，可选根 `AREAMATRIX.md`。

## 绑定

- Core 能力：C1-20 overview-generated
- UX 页面：S1-27, S1-30

## 核对清单

1. 默认不触碰用户 `README.md`。
2. 导入或配置变更能触发 generated overview 更新。
3. `RootAreaMatrixFile` 只写 `AREAMATRIX.md`，且不覆盖 README。
4. overview 输出失败不破坏导入主链路。

## 完成标准

- generated overview 内容可反映当前分类/文件。
- README 不被写入或覆盖的测试明确存在。
- 配置切换行为与 ADR 和 source-of-truth 文档一致。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace overview
```
