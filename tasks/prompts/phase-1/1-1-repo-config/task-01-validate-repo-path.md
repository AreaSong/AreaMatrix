# 1-1/task-01: C1-01 validate-repo-path

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现路径校验能力，只读判断资料库候选目录状态，不初始化、不接管、不写文件。

## 绑定

- Core 能力：C1-01 validate-repo-path
- UX 页面：S1-02, S1-03, S1-11, S1-32

## 核对清单

1. Core API 文档补齐并实现 `validate_repo_path` 或明确等价结构化入口。
2. 校验空目录、非空目录、已初始化目录、不可写目录和 `.areamatrix/` 子目录。
3. 返回结构化结果给 Swift，不依赖字符串解析。
4. 不产生任何 DB 或文件系统写入。

## 完成标准

- 路径校验测试覆盖主要路径状态和错误码。
- `validate_repo_path` 能支撑 S1-02/S1-03 的风险提示。
- 运行验证后无格式、clippy 和测试失败。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace validate_repo_path
```
