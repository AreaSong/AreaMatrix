# Stage 1 Performance Baseline

> Stage 1 MVP release 前性能基线、实测证据和阻断项。
>
> 阅读时长：约 5 分钟。

---

## 1. 结论

当前基线结论：**Stage 1 性能指标通过；Core、Swift XCTest performance 和真实
Release `.app` 启动到首屏 release gate 均有本地可复现证据**。

本次在 2026-05-10 18:12:15 CST 更新 Stage 1 baseline。Core release perf 覆盖了
单文件导入、100 文件批量导入、reindex、Tree/list 响应；`core/benches/stage1_hot_paths.rs`
提供同一组 Core hot path 的独立 bench target，`cargo bench --manifest-path core/Cargo.toml
--workspace --no-run` 会编译该 target；该 target 使用 Cargo 默认 bench harness 中的 ignored
benchmark test，不新增依赖或生产路径配置。Swift XCTest performance 由独立的
`apps/macos/AreaMatrixTests/AreaMatrixPerfTests.swift` 覆盖 hostless first-screen
readiness、单文件导入、100 文件批量导入、Tree/list 响应和 resident memory。上述可执行指标均
低于 `docs/development/performance.md` 与 `docs/roadmap/stage-1-mvp.md` 定义的阈值。

本轮 `./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests` 使用固定
DerivedData 证据目录 `/tmp/areamatrix-stage1-perf-evidence/DerivedData` 运行：标准
`xcodebuild test` 直接 `TEST SUCCEEDED`，5 个 `AreaMatrixPerfTests` 全部通过；随后构建
signed Release `AreaMatrix.app`，`codesign --verify --deep --strict` 通过，`otool -L`
未发现 `libarea_matrix_core.dylib` 动态链接，`macos_launch_probe.swift` 记录真实
`.app` 首屏 `777.606 ms < 1.5 s`。该证据关闭此前真实 `.app` 首屏 P1；Stage 1
release checklist 仍需继续阻断未完成的手工恢复冒烟、Developer ID 签名/公证/DMG、
干净 Mac 首启和 release 切面。

---

## 2. 环境

| 项 | 值 |
|---|---|
| 日期 | 2026-05-10 18:12:15 CST |
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
| Swift 标准 perf 入口 | `AREAMATRIX_RUN_PERF_TESTS=1 xcodebuild test -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' -only-testing:AreaMatrixTests/AreaMatrixPerfTests CODE_SIGNING_ALLOWED=NO`；本地 sandbox 可能在 `testmanagerd` 通信层阻断，CI 或非 sandbox 桌面会话应补跑 |
| 真实 `.app` 启动 release gate | Release build + `codesign --verify --deep --strict` + `otool -L` + `xcrun swift scripts/dev_tools/macos_launch_probe.swift --app <Release/AreaMatrix.app>` |
| Instruments memory audit | Release build + Instruments Allocations；当前 sandbox 中 `xcrun xctrace list templates` 被 `~/Library/Caches/com.apple.dt.InstrumentsCLI` 写权限阻断 |

---

## 4. 指标

| 指标 | 数据集 | 阈值 | 实测 | 入口 | 结论 |
|---|---|---:|---:|---|---|
| 启动到首屏 hostless surrogate | 已初始化 empty repo；`MainWindow + OnboardingModel + CoreBridge` 首屏 readiness | < 1.5 s | 81.355 ms | `AreaMatrixPerfTests/testApplicationLaunchToFirstScreenBaselineUnderStage1Threshold` via `./dev test macos` sandbox fallback | PASS |
| 真实 `.app` 启动到首屏 release gate | Release `AreaMatrix.app`，`NSWorkspace.openApplication` 到首个可见窗口 | < 1.5 s | 777.606 ms | `scripts/dev_tools/macos_launch_probe.swift` after Release build + codesign | PASS |
| Core 单文件 import copied | 1 MiB `invoice.pdf` | < 30 ms | 11 ms | `stage1_import_one_mebibyte_copy_under_threshold` in release profile | PASS |
| Swift 单文件 import copied | 1 MiB `invoice.pdf` | < 200 ms | 85.218 ms | `AreaMatrixPerfTests/testSingleFileImportBaselineUnderStage1Threshold` | PASS |
| 100 文件批量导入 + list | 100 x 4 KiB text | < 5 s | Rust 1,077 ms / Swift 1,043.521 ms | Rust release perf + Swift `AreaMatrixPerfTests` | PASS |
| reindex | 10,000 x 128 B files | < 30 s | 15,950 ms | `stage1_reindex_ten_thousand_files_under_threshold` in release profile | PASS |
| Tree response | 1,000 x 128 B files | < 30 ms | Rust 5 ms / Swift 15.475 ms | Rust release perf + Swift `AreaMatrixPerfTests` | PASS |
| list response | 200 rows | < 5 ms | Rust 0.702 ms / Swift 3.961 ms | Rust release perf + Swift `AreaMatrixPerfTests` | PASS |
| idle memory | CoreBridge opened empty repo | < 200 MB | 105.000 MB | `AreaMatrixPerfTests/testMemoryBaselinesUnderStage1Thresholds` resident memory | PASS |
| 1k 文件库内存 | 1,000 files | < 300 MB | 111.875 MB | `AreaMatrixPerfTests/testMemoryBaselinesUnderStage1Thresholds` resident memory | PASS |
| 10k 文件库内存 | 10,000 files | < 500 MB | 180.109 MB | `AreaMatrixPerfTests/testMemoryBaselinesUnderStage1Thresholds` resident memory | PASS |

---

## 5. 阻断项

当前没有 P1 性能 release 阻断项。

### 已关闭：真实 `.app` 启动到首屏 release 证据

- Stage 1 最终 MVP 标准要求启动时间 `< 1.5s`。
- 已执行证据：2026-05-10 18:12 CST
  `./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests`，标准
  `xcodebuild test` 直接 `TEST SUCCEEDED`；随后 Release build、ad-hoc codesign
  verification、`otool -L` 自包含检查和 `macos_launch_probe.swift` 均完成。
- 实测结果：
  `STAGE1_PERF name="applicationLaunchToFirstScreen.realApp" value_ms=777.606 threshold_ms=1500.000 result=PASS`。
- release checklist 处理：性能基线可标为通过；该证据不能替代 Developer ID 签名、公证、
  DMG 或干净 Mac 首启。

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
  必须保持未勾选；当前本地 release app launch gate 已通过。
- 本文件的指标表必须随 release candidate 更新；不得沿用旧机器、旧 commit 或
  Debug-only 数据替代当次 release baseline。
- Direct `xcrun xctest` fallback 只证明 hostless XCTest bundle 的 perf 测试逻辑通过；
  不能替代标准 `xcodebuild test` 或 release app launch probe 证据。
- 当前 baseline 满足 Stage 1 性能放行要求；release checklist 仍必须独立核对手工冒烟、
  签名、公证、DMG、干净 Mac 首启和 release notes。
- 内存自动门禁必须来自 XCTest resident memory 采样；release candidate 可再补
  Instruments Allocations 或 Xcode memory gauge 人工审计。

---

## Related

- [performance.md](performance.md)
- [testing.md](testing.md)
- [observability.md](observability.md)
- [release.md](release.md)
- [../roadmap/stage-1-mvp.md](../roadmap/stage-1-mvp.md)
