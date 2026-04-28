# 1-2/task-02: Storage Import

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现 SHA256、Move / Copy / Index 三模式、冲突处理、重复 hash 策略和事务式 staging。

## 核对清单

1. 成功导入同时写入文件系统和 DB。
2. 失败导入不留下最终目录半成品或 active DB 行。
3. Copy 保留源文件，Move 移走源文件，Index 不复制文件。
4. 重复 hash 和同名冲突策略符合 UX 与 storage 文档。
5. `recover_on_startup` 清理 staging 并修复 staging DB 行。

## 完成标准

- Storage 不变量有集成测试覆盖。
- 不使用 `unwrap()` 处理业务错误。

## 验证

```bash
cd core
cargo test --workspace storage
```

