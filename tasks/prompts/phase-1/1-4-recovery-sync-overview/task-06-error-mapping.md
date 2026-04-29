# 1-4/task-06: C1-21 error-mapping

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

补齐 CoreError 到 Swift/AppError 的稳定映射合同，支撑错误页、初始化失败、iCloud 提示和恢复 UI。

## 绑定

- Core 能力：C1-21 error-mapping
- UX 页面：S1-03, S1-06, S1-11, S1-25, S1-32

## 核对清单

1. `CoreError` variant 与 `docs/api/error-codes.md`、UDL、Rust 类型一致。
2. Swift 包装层不依赖字符串 contains 做主分支判断。
3. 每个错误有 severity、用户文案和建议动作。
4. 高严重错误能进入 repo error 或 recovery UI。

## 完成标准

- 每个 `CoreError` 都有映射测试或快照。
- UI 可区分 duplicate、invalid path、iCloud placeholder、DB、permission、internal。
- 错误映射缺失时验收不通过。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace error
```
