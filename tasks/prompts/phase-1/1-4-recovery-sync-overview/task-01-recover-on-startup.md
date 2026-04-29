# 1-4/task-01: C1-16 recover-on-startup

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现启动恢复，清理安全 staging 残留并回滚未完成 DB staging 状态。

## 绑定

- Core 能力：C1-16 recover-on-startup
- UX 页面：S1-05, S1-10, S1-30, S1-32

## 核对清单

1. `recover_on_startup` 返回清理数量和 warnings。
2. 只清理 `.areamatrix/staging/` 中可安全判定的临时文件。
3. active 用户文件和最终目录文件不得被删除。
4. 未完成 DB staging rows 能回滚或标记为可恢复。

## 完成标准

- 崩溃残留、空 staging、权限失败均有测试。
- RecoveryReport 可驱动 S1-32 展示。
- 高风险删除边界有明确测试证据。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace recovery
```
