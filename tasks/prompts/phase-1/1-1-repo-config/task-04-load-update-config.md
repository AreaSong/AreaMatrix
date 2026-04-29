# 1-1/task-04: C1-04 load-update-config

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现资料库配置读取与原子更新，支撑设置页和后续导入默认行为。

## 绑定

- Core 能力：C1-04 load-update-config
- UX 页面：S1-26, S1-27, S1-28, S1-29, S1-30

## 核对清单

1. `load_config` 在配置不存在时返回默认值。
2. `update_config` 原子写入配置并校验字段合法性。
3. 默认存储模式、overview 输出、locale、AI 开关均可读写。
4. 配置更新失败不损坏旧配置。

## 完成标准

- 设置页需要的 Stage 1 配置字段都有 Core 类型和测试。
- `RepoConfig` 与 `docs/api/core-api.md`、UDL、Rust 类型一致。
- 配置错误能映射为 `CoreError.Config`。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace config
```
