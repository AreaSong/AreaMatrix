# 测试策略

> 记录 AreaMatrix 当前 Rust、macOS、文档、治理、性能和发布证据的验证层次。
>
> 阅读时长：约 8 分钟。

---

## 原则

- 测试范围与改动风险匹配；跨 Core/macOS/文件系统边界时组合门禁。
- 临时目录、fixture 和 dependency injection 用于隔离，不得建立 mock-only 生产路径。
- dry-run、截图和同机探针不能替代真实业务或发布证据。
- required command 无法运行时结果是 `BLOCKED` 或 `NOT-READY`，不是 PASS。
- 所有完成证据必须在最终相关修改后重新执行。

## 按变更路径验证

高频开发先查看并执行当前工作树需要的完整层级门禁：

```bash
./dev test changed --list
./dev test changed
# `check affected` is the governance-oriented alias for the same affected-path plan.
./dev check affected --list
./dev check affected
```

| 变更层 | 当前执行内容 |
|---|---|
| developer tools | Python developer-tool regression suite |
| Rust Core | `validation` lane single-flight lock 内执行 `cargo test --workspace` |
| macOS client | localization contract + 复用持久 DerivedData 的 `./dev test macos` |
| iOS client | `swift build --package-path apps/ios`，不误跑 macOS XCTest |
| docs / governance | `./dev check docs` + `./dev check governance` |

`./dev check affected` 与 `./dev test changed` 使用同一套受影响路径解析；前者适合治理和 CI 脚本，后者适合日常开发。

该入口按层去重并按稳定顺序执行，适合开发反馈；跨层、高风险或最终收口仍需组合下方完整门禁，不能把
changed-path 选择当成 release 或 merge evidence。

## Rust Core

完整门禁：

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-features --workspace
```

Core 测试位于：

- 同模块 `#[cfg(test)]` 单元测试。
- `core/tests/**` 合同、实现、失败恢复和集成测试。
- `core/benches/core_hot_paths.rs` 显式性能测试。

文件安全能力至少覆盖正常路径、DB 失败、文件系统失败、重复执行、边界路径和用户文件不变量。

## macOS

标准入口：

```bash
./dev test macos
```

Xcode 共享 scheme 注册六份可执行测试计划，并以 `apps/macos/AreaMatrix-Functional.xctestplan` 作为默认功能计划。
每份计划固定 `AreaMatrixTests` target，且登记真实的类/方法标识，避免把空的 test plan 当成分层治理。日常开发可按
反馈成本选择：

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix \
  -destination 'platform=macOS,arch=arm64' -testPlan AreaMatrix-Unit test
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix \
  -destination 'platform=macOS,arch=arm64' -testPlan AreaMatrix-Feature test
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix \
  -destination 'platform=macOS,arch=arm64' -testPlan AreaMatrix-Integration test
```

脚本入口也支持先构建、后复用同一 DerivedData 执行分层计划：

```bash
./dev test macos --build-for-testing \
  --derived-data-path .build/derived-data/macos-tests
./dev test macos --test-without-building --test-plan AreaMatrix-Unit \
  --derived-data-path .build/derived-data/macos-tests
./dev test macos --test-without-building --test-plan AreaMatrix-Integration \
  --derived-data-path .build/derived-data/macos-tests
```

`--build-for-testing` 只生成 XCTest bundle，不启动测试；后续 `--test-without-building` 不会重新触发编译。
当本机 `testmanagerd` 被沙箱阻断时，runner 会从同一 DerivedData 复用 bundle；若指定了非 Functional 计划，
hostless fallback 会读取该计划的 `selectedTests`，不会误跑全量测试。`--test-plan` 可接受带或不带
`.xctestplan` 后缀的计划名；未指定时使用 scheme 注册的 Functional 默认计划。

`AreaMatrix-Performance.xctestplan` 由计划自身注入 `AREAMATRIX_RUN_PERF_TESTS=1`，只执行登记的性能样本；
`AreaMatrix-Release.xctestplan` 运行启动、Scenario Launcher 和生成绑定冒烟。完整的 `./dev test macos`
仍消费默认 Functional 计划；CI 先执行一次 `build-for-testing`，再通过 `test-without-building` 复用同一
DerivedData 运行 Unit、Feature、Integration 和 Functional coverage 分片。Performance 与 Release 计划仍按
显式性能 / 发布门禁运行，不把外部分发证据混入普通功能 CI。

本地默认 DerivedData 位于 `.build/derived-data/macos-tests/` 并跨运行保留。需要隔离缓存时使用
`./dev test macos --temporary-derived-data`，CI 或并行任务使用独立 `--derived-data-path`；两个显式选项
互斥，temporary 模式优先于环境中的 `DERIVED_DATA_PATH` 并在运行后清理。

脚本优先运行标准 `xcodebuild test`。只有日志明确显示本地 `testmanagerd` sandbox restriction 时，才允许
复用同一 DerivedData 的 hostless XCTest bundle。编译、链接、断言或非沙箱失败不能 fallback 成 PASS。

构建门禁：

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj \
  -scheme AreaMatrix \
  -destination 'platform=macOS,arch=arm64' \
  build CODE_SIGNING_ALLOWED=NO
```

格式与 lint：

```bash
cd apps/macos
swiftlint lint --strict --config ../../scripts/dev_tools/swiftlint.yml --force-exclude . --no-cache
swiftformat --lint . --config ../../scripts/dev_tools/swiftformat.conf \
  --exclude AreaMatrix/Bridge/Generated,AreaMatrix/Bridge/UniFFI,DerivedData --cache ignore
```

## 可观测性与诊断

Core 专项至少覆盖：subscriber 单次安装、配置更新、source redaction、catalog ID、事件字段、双层大小限制、
优先级队列、callback lifetime/deadline、并发、drop/health，以及 observed import 的 trace continuity。平台专项至少覆盖：

- Core sink adapter 的有界 ingress、severity 替换、drop 汇总和 drain/close。
- Hub 的 OSLog/signpost、内存 ring、rolling JSONL、manifest version/ownership、rotation、retention、disk-full、
  corrupt manifest/tail 和无副作用 health。
- incident pre/post window、`memory_only` / `manifest_owned` / `read_only`、持久化失败、异常 session 恢复和删除边界。
- `.amdiagnostic` preview/export parity、双层 redaction、checksum、大小/文件数/单行限制、symlink/hardlink/path
  traversal、非 allowlist 附件和离线 reader。
- 独立 Diagnostics Tab、三种持久化模式与 disabled、租约、en / zh-Hans、Trace Console，以及日志失败不改变
  import FS/DB/用户文件结果。

功能门禁使用 `./dev test macos`；Core 观测测试随 `cargo test --all-features --workspace` 执行。性能门禁显式运行：

```bash
./dev test macos --only-testing AreaMatrixTests/ObservabilityPerformanceTests
```

所有文件测试使用临时目录，不读取或删除真实 Application Support 日志和用户资料库。

## Coverage

远端 CI 的现行门槛：

- Core line coverage：70%。
- Swift Watcher：60%。
- 手写 Swift Bridge：50%。

macOS coverage 从 `.xcresult` 校验实际文件清单；空集合、生成绑定或 hostless fallback 不能冒充 coverage
PASS。仅包含协议一致性扩展、没有可执行行的声明型 Bridge 适配器（当前为
`Bridge/CoreBridgeRuntime.swift`）不计入加权比率；其余手写 Bridge 源文件必须逐一出现在
`xccov` 报告中，清单漂移直接失败。

## 文档与治理

长期文档或治理变更至少运行：

```bash
./dev check docs
./dev check wording
./dev check governance
./dev check skills
./dev check quality
./dev check prompts
./dev check diff
```

workflow authoring 变更还需：

```bash
./dev workflow discuss --version v2 doctor
./dev workflow doctor
./dev workflow check-template
```

不得为整理外观重写 v1 历史 execution、progress 或 evidence。

## 文件安全测试矩阵

| 边界 | 最小证据 |
|---|---|
| Copy/Move/Indexed import | FS + DB + source/final 状态 |
| staging recovery | 安全路径、未知 residue、symlink、重复执行 |
| migration/repair | backup、transaction failure、integrity、旧 DB 恢复 |
| reindex | 用户文件不变、scan session、冲突/不可读状态 |
| FSEvents sync | cursor、幂等、DB rollback、overview replay、InFlight |
| iCloud placeholder | 不隐式下载、不推进失败 cursor、不修改用户文件 |
| note sidecar | DB/sidecar 一致、冲突 fail closed、DB 失败恢复 sidecar |

真实 iCloud 环境、Developer ID、公证、DMG、clean Mac 和外部测试者属于发布证据，不能由本地 fixture
关闭。状态从 [residual ledger](../../workflow/residuals/README.md) 查阅。

## 性能

Rust：

```bash
cargo test --manifest-path core/Cargo.toml \
  --release --bench core_hot_paths -- --ignored --nocapture
```

macOS：

```bash
./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests
./dev test macos --only-testing AreaMatrixTests/ObservabilityPerformanceTests
```

Rust benchmark 的阈值当前只打印，需要人工检查每个 `result`；macOS performance XCTest 会 assertion。
详见 [performance.md](performance.md)。

## 手工冒烟

本地功能冒烟可覆盖：

- 初始化空资料库和接管已有目录。
- Copy/Move/Index 导入与 duplicate 决策。
- Finder create/modify/rename/remove 后 UI 刷新。
- note、tags、search、Undo/Redo 和恢复入口。
- 退出后重启、staging recovery 和 metadata diagnostics。
- generated overview 只写允许位置，用户 `README.md` 保持不变。

手工冒烟必须记录环境、动作、FS 状态和 DB/UI 结果。它不替代自动测试、独立 review、远端 CI 或正式
发布证据。

## CI

Core CI 使用：

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-features --workspace
cargo llvm-cov --workspace --lcov --output-path lcov.info --fail-under-lines 70
```

macOS CI 使用 `./dev build core-sdk` 一次生产并上传 CoreSDK artifact，下游 Xcode job 恢复同一
artifact 后执行 `./dev test macos` coverage gate；iOS package job 恢复并校验同一 artifact，建立
`apps/ios/.core-sdk` 指针后执行 `swift build --package-path apps/ios` 与
`swift test --package-path apps/ios`，不再启动第二条 Cargo 构建链。tracked bindings 由 CoreSDK
job 中的 `./dev bindings verify` 校验。SwiftLint 和 SwiftFormat 保持独立并行。治理 CI 覆盖 governance、docs、
skills、quality、品牌资产、Codex OS、wording、task-loop、prompts、diff 和 secret scan。

## 反模式

- 用 sleep 代替 expectation/barrier 控制并发。
- 共享可变全局 fixture。
- 只断言无错误，不检查 FS/DB/状态结果。
- 只覆盖 happy path。
- 为测试添加生产路径 hardcoded success。
- 使用过期日志或另一个工作区结果声称完成。

## Related

- [coding-standards.md](coding-standards.md)
- [ci-governance.md](ci-governance.md)
- [performance.md](performance.md)
- [recovery.md](recovery.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [../../CODE_REVIEW.md](../../CODE_REVIEW.md)
