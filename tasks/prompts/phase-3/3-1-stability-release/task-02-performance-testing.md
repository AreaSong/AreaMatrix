# 3-1/task-02: 性能与测试加固

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-3.md`

## 范围

补齐核心集成测试、性能基线、大量文件场景和崩溃测试。

## 核对清单

1. core 覆盖率达到 Stage 1 门槛。
2. 1 万文件列表、树渲染和 DB 查询有性能验证。
3. staging 崩溃测试覆盖强杀或 panic 注入。
4. 手工冒烟清单可执行。

## 完成标准

- Stage 1 的稳定性风险有测试或手工清单覆盖。
- 性能瓶颈有记录和优化结果。

## 验证

```bash
cd core
cargo test --workspace
cargo llvm-cov --workspace --fail-under-lines 70
```

