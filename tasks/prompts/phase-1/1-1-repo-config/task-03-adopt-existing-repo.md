# 1-1/task-03: C1-03 adopt-existing-repo

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现非空目录接管：初始化 `.areamatrix/` 并只索引已有用户文件，不移动、不重命名、不删除、不覆盖。

## 绑定

- Core 能力：C1-03 adopt-existing-repo
- UX 页面：S1-03, S1-04, S1-05, S1-10

## 核对清单

1. `init_repo(mode=AdoptExisting)` 写入 `scan_sessions(kind=Adopt)`。
2. 已有用户文件以 `origin=Adopted` 进入 `files`。
3. `.areamatrix/`、generated overview、系统临时文件按文档跳过。
4. 支持查询和恢复最近 scan session。

## 完成标准

- 接管测试能证明用户文件路径和内容未改变。
- 中断或失败后有 scan session 证据可恢复或可解释。
- `README.md` 作为普通用户文件索引，不被覆盖。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace adopt_existing_repo
```
