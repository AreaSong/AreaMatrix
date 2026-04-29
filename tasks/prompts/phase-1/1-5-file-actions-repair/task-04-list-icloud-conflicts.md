# 1-5/task-04: C1-25 list-icloud-conflicts

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现 iCloud conflicted copy 列表能力，只识别和报告，不自动解决。

## 绑定

- Core 能力：C1-25 list-icloud-conflicts
- UX 页面：S1-36, S1-25

## 核对清单

1. 识别 iCloud conflicted copy 并返回 conflict pair。
2. 不确定匹配标记为 `Needs review`。
3. 列表能力不删除、不移动任何文件。
4. 失败时返回结构化错误。

## 完成标准

- 空态、单组冲突、多组冲突、不确定匹配都有测试。
- S1-36 可直接消费结构化结果。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace icloud_conflicts
```
