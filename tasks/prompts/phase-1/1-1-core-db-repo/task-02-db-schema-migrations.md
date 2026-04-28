# 1-1/task-02: DB Schema 与 Migration

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现 SQLite v1 schema、migration 框架、WAL、外键约束和基础 repo DB 打开逻辑。

## 核对清单

1. schema 与 `docs/architecture/data-model.md` 一致。
2. migration 支持幂等初始化和版本记录。
3. WAL 与 foreign keys 在连接初始化时启用。
4. DB 测试覆盖 v1 创建、重复初始化、约束生效。

## 完成标准

- 临时目录中能初始化 `.areamatrix/index.db`。
- migration 不破坏已有 DB。

## 验证

```bash
cd core
cargo test --workspace db
```

