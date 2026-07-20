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

## Coverage

远端 CI 的现行门槛：

- Core line coverage：70%。
- Swift Watcher：60%。
- 手写 Swift Bridge：50%。

macOS coverage 从 `.xcresult` 校验实际文件清单；空集合、生成绑定或 hostless fallback 不能冒充 coverage
PASS。

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

macOS CI 使用 `./dev build core`、`./dev bindings verify`、带 coverage gate 的 `./dev test macos`、
SwiftLint 和 SwiftFormat。治理 CI 覆盖 docs、skills、quality、Codex OS、task-loop、prompts、diff 和
secret scan。

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
