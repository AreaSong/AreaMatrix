# 性能工程

> 记录 AreaMatrix 当前可执行的 Rust/macOS 性能基线、命令和证据边界。
>
> 阅读时长：约 6 分钟。

---

## 当前性能门禁

AreaMatrix 有三组显式性能测试：

| 层 | 文件 | 运行方式 |
|---|---|---|
| Rust Core | `core/benches/core_hot_paths.rs` | ignored libtest benchmark |
| macOS | `apps/macos/AreaMatrixTests/AreaMatrixPerfTests.swift` | explicit XCTest gate |
| macOS observability | `apps/macos/AreaMatrixTests/Observability/ObservabilityPerformanceTests.swift` | explicit XCTest gate |

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
| 100k structured observability submit + bounded drain/backpressure | 2 s |

Rust benchmark 会打印 `CORE_HOT_PATH_BENCH ... result=PASS/FAIL`，并为 observability 场景报告 delivered/drop
数量；有界队列允许拥塞丢弃，因此该场景不声明 100k 事件全部送达。当前 benchmark 不对阈值执行 assertion，
命令 exit 0 只能证明 benchmark 完成，必须同时审查每一行 result。

## macOS performance XCTest

```bash
./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests
./dev test macos --only-testing AreaMatrixTests/ObservabilityPerformanceTests
```

当前覆盖：

- application launch 到首个可见 repository window：1.5 s。
- 1 MiB Copy import：200 ms。
- 100 × 4 KiB import + list：5 s。
- 1k tree：30 ms。
- list 200 rows：标准路径 5 ms，hostless fallback 10 ms。
- resident memory：idle 200 MB、1k files 300 MB、10k files 500 MB。
- observability source sanitization 10k 次：2 s。
- observability bounded ring append 200k 次：2 s。
- observability rolling JSONL append 500 条并完成 rotation：5 s。
- Trace Console 10k 事件投影：10 s。

macOS tests 使用 assertion，超阈值会失败。受限环境无法启动真实 app 时可执行 hostless first-screen
fallback；该结果不能替代正式分发的 clean-Mac 首启证据。

显式 performance gate 还会构建 Release app 并执行签名/链接/启动探针。ad-hoc 或同机探针只证明本地
工程路径，不替代 Developer ID、公证、DMG 或外部设备验证。

## 普通 CI 边界

`AreaMatrixPerfTests` 和 `ObservabilityPerformanceTests` 默认不参加普通 `./dev test macos`，避免共享 runner
的 wall-clock 和 resident memory 抖动阻断功能 CI。Rust benchmark 同样需要显式运行。

普通 CI 仍覆盖：

- Rust fmt、clippy、test、coverage。
- Core universal build 与 bindings。
- macOS build/test、Watcher/Bridge coverage、SwiftLint、SwiftFormat。

性能相关改动应在 PR/评审记录中附显式 benchmark 输出，而不是假设普通 CI 已执行性能门禁。

## 开发反馈基线

本地开发反馈使用固定 DerivedData 和已命中的 CoreSDK 测量。参考环境为 Mac16,8、macOS 26.4.1、
Xcode 26.4.1；样本应在相同环境和工作树条件下比较。

| 路径 | 样本 | P50 | P95 | 证据边界 |
|---|---:|---:|---:|---|
| 本地 Swift Build | 20 / 20 | 1.857 s | 1.924 s | `macos-build-for-testing-warm`，固定 DerivedData、CoreSDK 命中且不启动 Cargo |
| 本地 XCTest | 20 / 20 | 2.199 s | 2.220 s | `macos-architecture-test-without-building-warm`，复用同一测试构建产物 |
| Xcode Canvas 恢复 | 20 / 20 | 4.630 s | 5.942 s | `xcode-canvas-ui-catalog-live-refresh`，刷新后 UI Catalog 三个 Preview 可交互 |
| 远端 CI | 0 / 20 | 未建立 | 未建立 | 尚无同 runner、event 和 cache policy 的可读取成功样本 |

`./dev metrics build --json` 另外汇总 CoreSDK cache hit/miss 和 Cargo lane lock wait。构建、测试和 Canvas
基线必须分别记录，不能用 command 启动耗时替代 Canvas 实际可交互时间。

真实反馈样本使用
`./dev metrics feedback --record <canvas|build|test|ci> --cohort <stable-cohort> --duration <seconds> --note <context>`
记录，`canvas`、`build`、`test`、`ci` 先分路径，再按同一命令、缓存状态、runner/event policy 的 cohort
分别汇总；只有单个非 legacy cohort 至少有 20 个成功样本时，`baseline_ready` 才为 true。缺少 cohort 的旧记录
归入 `legacy-mixed`，无论数量多少都不能成为正式基线。Canvas duration 必须来自 Xcode Preview 实际恢复可交互的可读观测；
当前 UI Catalog cohort 已满足 20 个成功样本，每个样本都确认 Preview 条目存在且没有 `Canvas paused` 状态。
当前 Build 与定向 Test 已分别达到 20 个同质成功样本，构成本机 warm 反馈基线；`legacy-mixed` 中原有的
warm/clean、定向/全量混合记录仍只保留为历史观测，不能参与正式基线。全量测试与 CI 仍必须各自建立
独立 cohort，比较时不得混用。

CI workflow 已保留 CoreSDK、Cargo lane 和 macOS test 的标准化 duration 输出，并把 macOS build + 分层测试
记录为 `github-macos14-xcode-build-and-layered-tests` cohort，上传 `macos-ci-feedback` artifact。仓库内尚无至少
20 次同类成功远端运行的可读取样本，因此没有建立远端 CI P50/P95。首次 CI 基线必须来自同一 runner image、
同类 event 和相同 cache policy 的真实成功 run；本地耗时不能冒充 CI 基线。

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
