# Stage 1 Performance Baseline

> Stage 1 MVP release 前性能基线、实测证据和阻断项。
>
> 阅读时长：约 5 分钟。

---

## 1. 结论

当前基线结论：**已形成 Stage 1 指标表；Core 与 Swift XCTest performance 可执行指标
通过；真实 Release `.app` 启动到首屏证据在当前 sandbox 环境仍为 P1/BLOCKED，
因此 Stage 1 release checklist 不能放行**。

本次在 2026-05-09 21:20:00 CST 更新 Stage 1 baseline。Core release perf 覆盖了
单文件导入、100 文件批量导入、reindex、Tree/list 响应；`core/benches/stage1_hot_paths.rs`
提供同一组 Core hot path 的独立 bench target，`cargo bench --manifest-path core/Cargo.toml
--workspace --no-run` 会编译该 target；该 target 使用 Cargo 默认 bench harness 中的 ignored
benchmark test，不新增依赖或生产路径配置。Swift XCTest performance 由独立的
`apps/macos/AreaMatrixTests/AreaMatrixPerfTests.swift` 覆盖 hostless first-screen
readiness、单文件导入、100 文件批量导入、Tree/list 响应和 resident memory。上述可执行指标均
低于 `docs/development/performance.md` 与 `docs/roadmap/stage-1-mvp.md` 定义的阈值。

当前 Codex 本地 sandbox 无法给出真实 `NSWorkspace.openApplication` 或 Instruments
启动 `AreaMatrix.app` 到首个可见窗口的 release 证据。`xcodebuild test` 被
`com.apple.testmanagerd.control` sandbox restriction 阻断后，`./dev test macos`
会复用同一 DerivedData 中的 `AreaMatrixTests.xctest` 运行 hostless XCTest fallback；
该 fallback 只能证明 `MainWindow + CoreBridge` 首屏 readiness，不能替代真实 `.app`
launch release gate。Release build、codesign、self-contained linkage 和
`macos_launch_probe.swift` 仍会运行；若 LaunchServices 在当前 sandbox 返回
`NSCocoaErrorDomain code=259` / `kLSNoExecutableErr` 等环境阻断，local validation
可以继续通过；若直接 executable 模式也因当前 sandbox 无法产生可见窗口，会同样记录为
local sandbox BLOCKED。本文件和 release checklist 必须保留 P1 阻断。

---

## 2. 环境

| 项 | 值 |
|---|---|
| 日期 | 2026-05-09 21:20:00 CST |
| macOS | 26.4.1 (25E253) |
| 架构 | arm64 |
| Xcode | 26.2 (17C52) |
| Rust | rustc 1.94.1 / cargo 1.94.1 |
| CPU / 内存 | `system_profiler`: MacBook Pro Mac16,8 / Apple M4 Pro / 12 cores (8P+4E) / 24 GB；`sysctl` 在当前 sandbox 返回 Operation not permitted |
| 数据位置 | 测试只使用 `tempfile` / `FileManager.default.temporaryDirectory` 下的临时目录 |

---

## 3. 可重复入口

| 范围 | 命令或入口 |
|---|---|
| Prompt doctor | `python3 tasks/prompts/_shared/prompt_pipeline.py doctor` |
| Manifest Rust bench 编译 | `cargo bench --manifest-path core/Cargo.toml --workspace --no-run`；必须出现 `Executable benches/stage1_hot_paths.rs` |
| Rust Stage 1 hot path bench | `cargo test --manifest-path core/Cargo.toml --release --bench stage1_hot_paths -- --ignored --nocapture` |
| Rust Stage 1 release perf | `cargo test --manifest-path core/Cargo.toml --release --test stage1_performance_baseline -- --ignored --test-threads=1 --nocapture` |
| Swift perf validation gate | `./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests`；先跑标准 `xcodebuild test`，仅在失败日志明确指向 `testmanagerd` sandbox restriction 时 fallback 到同一 XCTest bundle |
| Swift 标准 perf 入口 | `xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' -only-testing:AreaMatrixTests/AreaMatrixPerfTests CODE_SIGNING_ALLOWED=NO`；本地 sandbox 可能在 `testmanagerd` 通信层阻断，CI 或非 sandbox 桌面会话应补跑 |
| 真实 `.app` 启动 release gate | Release build + `codesign --verify --deep --strict` + `otool -L` + `xcrun swift scripts/dev_tools/macos_launch_probe.swift --app <Release/AreaMatrix.app>`；当前 sandbox 下 LaunchServices / direct executable probe 为 BLOCKED |
| Instruments memory audit | Release build + Instruments Allocations；当前 sandbox 中 `xcrun xctrace list templates` 被 `~/Library/Caches/com.apple.dt.InstrumentsCLI` 写权限阻断 |

---

## 4. 指标

| 指标 | 数据集 | 阈值 | 实测 | 入口 | 结论 |
|---|---|---:|---:|---|---|
| 启动到首屏 hostless surrogate | 已初始化 empty repo；`MainWindow + OnboardingModel + CoreBridge` 首屏 readiness | < 1.5 s | 175.600 ms | `AreaMatrixPerfTests/testApplicationLaunchToFirstScreenBaselineUnderStage1Threshold` via `./dev test macos` sandbox fallback | PASS |
| 真实 `.app` 启动到首屏 release gate | Release `AreaMatrix.app`，`NSWorkspace.openApplication` / Instruments 到首个可见窗口 | < 1.5 s | BLOCKED：LaunchServices sandbox 返回 `NSCocoaErrorDomain code=259`；direct executable probe 无法产生可见窗口 | `scripts/dev_tools/macos_launch_probe.swift` after Release build + codesign | BLOCKED |
| Core 单文件 import copied | 1 MiB `invoice.pdf` | < 30 ms | 11 ms | `stage1_import_one_mebibyte_copy_under_threshold` in release profile | PASS |
| Swift 单文件 import copied | 1 MiB `invoice.pdf` | < 200 ms | 63.860 ms | `AreaMatrixPerfTests/testSingleFileImportBaselineUnderStage1Threshold` | PASS |
| 100 文件批量导入 + list | 100 x 4 KiB text | < 5 s | Rust 1,077 ms / Swift 1,013.616 ms | Rust release perf + Swift `AreaMatrixPerfTests` | PASS |
| reindex | 10,000 x 128 B files | < 30 s | 15,950 ms | `stage1_reindex_ten_thousand_files_under_threshold` in release profile | PASS |
| Tree response | 1,000 x 128 B files | < 30 ms | Rust 5 ms / Swift 16.370 ms | Rust release perf + Swift `AreaMatrixPerfTests` | PASS |
| list response | 200 rows | < 5 ms | Rust 0.702 ms / Swift 4.078 ms | Rust release perf + Swift `AreaMatrixPerfTests` | PASS |
| idle memory | CoreBridge opened empty repo | < 200 MB | 72.844 MB | `AreaMatrixPerfTests/testMemoryBaselinesUnderStage1Thresholds` resident memory | PASS |
| 1k 文件库内存 | 1,000 files | < 300 MB | 79.891 MB | `AreaMatrixPerfTests/testMemoryBaselinesUnderStage1Thresholds` resident memory | PASS |
| 10k 文件库内存 | 10,000 files | < 500 MB | 133.844 MB | `AreaMatrixPerfTests/testMemoryBaselinesUnderStage1Thresholds` resident memory | PASS |

---

## 5. 阻断项

当前存在 1 个 P1 release 阻断项。

### P1：真实 `.app` 启动到首屏 release 证据缺失

- 阻断原因：Stage 1 最终 MVP 标准要求启动时间 `< 1.5s`。当前环境只能取得 hostless
  `MainWindow + CoreBridge` readiness，真实 Release `.app` launch 到首屏被本地 sandbox
  阻断。
- 已尝试证据：Release build、ad-hoc codesign verification、`otool -L` 自包含检查、
  `macos_launch_probe.swift`、复制到 `/private/tmp`、清理 xattrs、`spctl` 接受、直接执行
  app executable。LaunchServices 仍返回 `NSCocoaErrorDomain code=259` / corrupt app
  类错误，直接执行也无法在当前 sandbox 给出首屏窗口证据。
- release checklist 处理：`release.md` 中“性能基线无回退 / 启动时间 < 1.5s”不得勾选。
- 回退建议：在非 Codex sandbox 的 macOS 桌面会话或 CI runner 上重跑
  `./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests`、标准
  `xcodebuild test ... AreaMatrixPerfTests` 与 Instruments launch profile；若真实启动超阈值，
  回到 Phase 1/2 的 startup recovery、`OnboardingModel.bootstrapIfNeeded()`、
  `CoreBridge.openConfiguredRepository` 和首屏 tree/list loading 路径做 profile。

### 记录：Rust bench 编译入口

- 本轮 task/manifest 要求运行
  `cargo bench --manifest-path core/Cargo.toml --workspace --no-run`。
- 当前验证结果：该命令通过，并编译 `benches/stage1_hot_paths.rs`，不是仅编译 lib bench
  harness。
- 可执行 hot path 入口：
  `cargo test --manifest-path core/Cargo.toml --release --bench stage1_hot_paths -- --ignored --nocapture`。
  该入口输出 `STAGE1_BENCH` 指标行，覆盖单文件导入、100 文件批量导入、reindex 和 Tree/list。

### 已修复：本地 macOS perf validation 不能吞掉真实测试失败

- 本地 gate 使用
  `./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests`。
- 该入口仍先执行标准 `xcodebuild test`；如果目标 XCTest suite 已经全部通过，只忽略
  sandbox-only 的 xcodebuild 收尾错误。
- 只有没有目标 suite 通过证据且当前本地 sandbox 明确阻断 `testmanagerd` 通信时，
  才复用同一 XCTest bundle 通过 `xcrun xctest` 跑 `AreaMatrixPerfTests`。
- 构建失败、断言失败、链接失败、非 sandbox 错误不会被 fallback 覆盖。
- 对 `AreaMatrixPerfTests`，runner 会继续尝试 Release `.app` 启动 probe。若 probe
  返回 LaunchServices 或 direct executable sandbox 阻断，runner 会把本地 validation 保持为
  通过，同时打印 release checklist blocked；该输出不是 release 放行证据。

---

## 6. Release Checklist 规则

- 任一 P0/P1 性能指标失败、未测或被环境阻断时，`release.md` 中“性能基线无回退”
  必须保持未勾选。
- 本文件的指标表必须随 release candidate 更新；不得沿用旧机器、旧 commit 或
  Debug-only 数据替代当次 release baseline。
- Direct `xcrun xctest` fallback 只证明 hostless XCTest bundle 的 perf 测试逻辑通过；
  不能替代标准 `xcodebuild test` 中真实 `.app` launch 到首屏证据。
- 当前 baseline 已满足“记录并阻断”要求，但不满足 release 放行要求；后续 release task
  必须在非 sandbox 环境补齐真实 `.app` launch 或 Instruments 证据。
- 内存自动门禁必须来自 XCTest resident memory 采样；release candidate 可再补
  Instruments Allocations 或 Xcode memory gauge 人工审计。

---

## Related

- [performance.md](performance.md)
- [testing.md](testing.md)
- [observability.md](observability.md)
- [release.md](release.md)
- [../roadmap/stage-1-mvp.md](../roadmap/stage-1-mvp.md)
