# 1-3/task-01: UDL 与 Bindings

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现 `core/area_matrix.udl`、UniFFI scaffolding 和 Swift bindings 生成流程。

## 核对清单

1. UDL 与 `docs/api/core-api.md` 对齐。
2. `build.rs` 能生成 scaffolding。
3. `scripts/build-core.sh` 能生成 Swift 文件、C header 和 universal staticlib。
4. 生成文件进入 `apps/macos/AreaMatrix/Bridge/Generated/`，不手改生成物。

## 完成标准

- Rust core 能通过 UniFFI 生成 Swift binding。
- UDL 中不暴露平台专属类型。

## 验证

```bash
./scripts/build-core.sh
```

