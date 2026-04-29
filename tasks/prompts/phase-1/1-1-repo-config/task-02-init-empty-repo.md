# 1-1/task-02: C1-02 init-empty-repo

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现空目录初始化闭环：创建 `.areamatrix/`、DB schema、默认配置、默认分类规则和 generated overview。

## 绑定

- Core 能力：C1-02 init-empty-repo
- UX 页面：S1-04, S1-05, S1-07, S1-08

## 核对清单

1. `init_repo(mode=CreateEmpty)` 按文档创建资料库内部结构。
2. 创建并校验 SQLite schema、`repo_config`、默认 `classifier.yaml` 和 `ignore.yaml`。
3. 默认不覆盖用户 `README.md`，默认 generated overview 写在 `.areamatrix/generated/`。
4. 重复初始化和初始化失败路径有结构化错误。

## 完成标准

- 空目录初始化后能被 `load_config`、`list_files`、`list_tree_json` 读取。
- 初始化失败不留下不可恢复的 active 半成品。
- 验证测试覆盖成功、重复初始化、不可写路径。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace init_empty_repo
```
