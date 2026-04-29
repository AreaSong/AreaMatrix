# 1-3/task-05: C1-15 build-tree

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现资料库 Tree JSON 构建，支撑侧栏树、空状态和加载后刷新。

## 绑定

- Core 能力：C1-15 build-tree
- UX 页面：S1-08, S1-09, S1-10

## 核对清单

1. `list_tree_json` 返回 Swift 可解码 JSON。
2. 空资料库返回合法空树。
3. 排序稳定，节点 key 稳定。
4. 不写 generated overview，不修改 DB。

## 完成标准

- Tree JSON schema 有测试或 fixture。
- 大目录基础性能不出现明显 N+1 查询。
- UI 无需扫描文件系统来拼 sidebar。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace tree
```
