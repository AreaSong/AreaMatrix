# 1-2/task-03: Change Log

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现 change_log 的 insert、list、filter 和 detail_json 结构。

## 核对清单

1. 导入、重命名、移动、删除、恢复、外部变化写入 change_log。
2. `list_changes` 支持 file_id、category、action、时间范围、分页。
3. detail_json 可读、稳定、便于 UI 展示。

## 完成标准

- change_log 与 storage、sync 的调用点对齐。
- 过滤与分页测试通过。

## 验证

```bash
cd core
cargo test --workspace change_log
```

