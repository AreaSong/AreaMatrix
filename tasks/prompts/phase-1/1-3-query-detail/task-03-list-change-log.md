# 1-3/task-03: C1-13 list-change-log

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现 change log 查询，支撑详情时间线、导入结果和恢复说明。

## 绑定

- Core 能力：C1-13 list-change-log
- UX 页面：S1-13, S1-21, S1-32

## 核对清单

1. `list_changes` 支持 file_id、category、action、since、until、limit、offset。
2. 按 `occurred_at DESC` 稳定排序。
3. `detail_json` 保持合法 JSON。
4. 与导入、重命名、笔记、sync 动作共享 action 约定。

## 完成标准

- 查询过滤与分页测试通过。
- 已有导入记录能在详情日志中查询。
- 失败时返回 `Db` 等结构化错误。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace change_log
```
