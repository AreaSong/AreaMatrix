# 性能工程

> 记录 AreaMatrix 当前可执行的 Rust/macOS 性能基线、命令和证据边界。
>
> 阅读时长：约 6 分钟。

---

## 当前性能门禁

AreaMatrix 有两组显式性能测试：

| 层 | 文件 | 运行方式 |
|---|---|---|
| Rust Core | `core/benches/core_hot_paths.rs` | ignored libtest benchmark |
| macOS | `apps/macos/AreaMatrixTests/AreaMatrixPerfTests.swift` | explicit XCTest gate |

仓库当前没有 Criterion 依赖、`storage_bench.rs`、HTML report、跨 commit 自动 baseline 比较或统一“回归
+10% 即失败”CI。

## Rust Core benchmark

先确认 benchmark target 可编译：

```bash
cargo bench --manifest-path core/Cargo.toml --workspace --no-run
```

执行真实 hot paths：

```bash
cargo test --manifest-path core/Cargo.toml \
  --release --bench core_hot_paths -- --ignored --nocapture
```

当前覆盖：

| 场景 | 文档阈值 |
|---|---:|
| Copy import 1 MiB | 30 ms |
| 100 × 4 KiB Copy import + list | 5 s |
| reindex 10k files | 30 s |
| list tree 1k files | 30 ms |
| list files 200 rows | 5 ms |
| 100k structured observability submit + delivery | 2 s |

Rust benchmark 会打印 `CORE_HOT_PATH_BENCH ... result=PASS/FAIL`，但当前不会对阈值执行 assertion。因此
命令 exit 0 只能证明 benchmark 完成，必须同时审查每一行 result。

## macOS performance XCTest

```bash
./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests
```

当前覆盖：

- application launch 到首个可见 repository window：1.5 s。
- 1 MiB Copy import：200 ms。
- 100 × 4 KiB import + list：5 s。
- 1k tree：30 ms。
- list 200 rows：标准路径 5 ms，hostless fallback 10 ms。
- resident memory：idle 200 MB、1k files 300 MB、10k files 500 MB。

macOS tests 使用 assertion，超阈值会失败。受限环境无法启动真实 app 时可执行 hostless first-screen
fallback；该结果不能替代正式分发的 clean-Mac 首启证据。

显式 performance gate 还会构建 Release app 并执行签名/链接/启动探针。ad-hoc 或同机探针只证明本地
工程路径，不替代 Developer ID、公证、DMG 或外部设备验证。

## 普通 CI 边界

`AreaMatrixPerfTests` 默认不参加普通 `./dev test macos`，避免共享 runner 的 wall-clock 和 resident memory
抖动阻断功能 CI。Rust benchmark 同样需要显式运行。

普通 CI 仍覆盖：

- Rust fmt、clippy、test、coverage。
- Core universal build 与 bindings。
- macOS build/test、Watcher/Bridge coverage、SwiftLint、SwiftFormat。

性能相关改动应在 PR/评审记录中附显式 benchmark 输出，而不是假设普通 CI 已执行性能门禁。

## 基线纪律

- 使用相同硬件、OS、power mode 和构建配置比较结果。
- 至少记录命令、commit、环境、样本数和原始输出。
- 先证明瓶颈，再优化；不为未测量路径引入缓存或并发复杂度。
- 文件系统、DB、staging、FSEvents 优化不得弱化用户文件安全和错误恢复。
- 性能通过不能覆盖 correctness、review、CI 或 release evidence blocker。

## 工具

可按需人工使用 Instruments Time Profiler、Allocations 和 Xcode metric，但它们不是当前自动 CI gate。新增
工具或依赖必须遵守 dependency policy。

## Related

- [testing.md](testing.md)
- [ci-governance.md](ci-governance.md)
- [coding-standards.md](coding-standards.md)
- [../modules/tree-scan.md](../modules/tree-scan.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
