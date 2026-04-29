# 1-5/task-05: C1-26 repair-reindex-metadata

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现 metadata repair / full rescan 的 Core 合同，修复对象只限 `.areamatrix/` 元数据。

## 绑定

- Core 能力：C1-26 repair-reindex-metadata
- UX 页面：S1-37, S1-11, S1-32

## 核对清单

1. 修复前可创建诊断快照或恢复点。
2. Full rescan 只读扫描用户文件并重建索引。
3. 修复不移动、不重命名、不删除用户文件。
4. 成功/失败 report 可驱动 S1-37。

## 完成标准

- DB corrupted、rescan 成功、rescan 失败都有测试。
- README 和用户文件安全边界有证据。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace metadata_repair
```
