# 目录树扫描

> 记录 `list_tree_json` 当前如何读取文件系统并生成主窗口目录树。
>
> 阅读时长：约 4 分钟。

---

## 实现位置

目录树当前由单文件 `core/src/tree/mod.rs` 实现，公开门面位于 `core/src/api/queries.rs`。

每次调用 `list_tree_json(repoPath, locale)` 都会重新：

1. 验证资料库 DB 可只读打开。
2. 读取 `.areamatrix/classifier.yaml`；缺失或无效时回退内置 classifier。
3. 读取 `.areamatrix/ignore.yaml` 并合并默认 ignore patterns。
4. 使用 `WalkDir` 遍历真实文件系统。
5. 在本次调用内用 `RawNode` 和 `BTreeMap` 聚合 file count 与 size。
6. 应用分类显示名和 locale，序列化为 JSON。

## 遍历边界

```rust
WalkDir::new(repo)
    .follow_links(false)
    .same_file_system(true)
```

- 不跟随符号链接。
- 不跨文件系统边界。
- 忽略 `.areamatrix/`、版本控制目录、依赖/构建目录和用户 ignore patterns。
- 目录只用于树结构；file count 与 size 从普通文件累计。
- 用户文件只读，不创建、移动、删除、重命名或覆盖。

## 节点类型

- `RepositoryRoot`
- `SystemCategory`
- `UserFolder`
- `Subdir`

根节点显示名根据 locale 选择“资料库”或“Repository”。分类显示名来自 classifier 的
`display_name`，缺失时回退 slug。

## 缓存边界

当前没有 `TreeCache`、dirty marking、incremental cache、LRU、DB aggregation 或 cache hit/miss 指标。
每次调用都扫描文件系统并构造新的内存树。

因此性能优化必须先通过真实 benchmark 证明瓶颈，再决定是否引入缓存及失效协议。不能在文档中把缓存写成
现有能力。

## 错误

- 资料库未初始化或 DB 不可读：返回对应 Core error。
- classifier/ignore 读取失败：除 `RepoNotInitialized`/`Db` 外统一归一为 `Io` error（与
  [core-api.md](../api/core-api.md) 的 tree 合同一致）；classifier 内容无效可回退内置配置。
- WalkDir entry、metadata 或路径规范化失败：返回映射后的 Core error。
- JSON 序列化失败：返回 IO error。

## 验证

- classifier locale 与 fallback。
- default/user ignore patterns。
- symlink 和跨文件系统边界。
- 多层目录的 count、size、depth、relative path。
- 1k 文件性能基线和大库内存占用。

## Related

- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [../architecture/concurrency.md](../architecture/concurrency.md)
- [../development/performance.md](../development/performance.md)
- [storage.md](storage.md)
- [overview-gen.md](overview-gen.md)
