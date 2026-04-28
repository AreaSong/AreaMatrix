# 1-3/task-02: Core API 集成测试

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

用集成测试覆盖从 `init_repo` 到 `import_file`、`list_files`、`list_changes`、`list_tree_json` 的核心闭环。

## 核对清单

1. 临时目录完成 repo 初始化。
2. Copy / Move / Index 三模式都有 API 级测试。
3. 错误路径返回 `CoreError`，不 panic。
4. list 和 filter 行为与文档一致。

## 完成标准

- Core API 层关键路径有端到端测试。
- 覆盖率门槛开始接近 `docs/development/testing.md` 要求。

## 验证

```bash
cd core
cargo test --workspace
```

