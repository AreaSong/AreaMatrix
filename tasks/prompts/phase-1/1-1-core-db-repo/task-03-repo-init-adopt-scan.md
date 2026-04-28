# 1-1/task-03: Repo Init、接管与扫描会话

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现 `init_repo`、`open_repo`、非空目录接管、`scan_sessions` 和 `ignore.yaml` 的基础能力。

## 核对清单

1. 空目录初始化创建 `.areamatrix/`、DB、config、classifier、ignore。
2. 非空目录接管只索引，不移动、不重命名、不覆盖用户文件。
3. `scan_sessions` 支持中断记录和 resume。
4. `ignore.yaml` 被首次扫描、reindex、tree-scan 与 watcher 共享。

## 完成标准

- 接管已有目录不会改变任何已有用户文件路径和内容。
- 相关不变量有测试覆盖。

## 验证

```bash
cd core
cargo test --workspace repo
cargo test --workspace scan
```

