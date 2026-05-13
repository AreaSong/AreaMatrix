# Stage 1 Release Checklist

> Stage 1 MVP alpha 分发前的发布清单、证据状态和阻断结论。
>
> 阅读时长：约 7 分钟。

---

## 1. 当前结论

当前结论：**不放行 Stage 1 alpha 分发**。

最终集成验收：**不放行**。原因是当前仍存在 P1 release 阻断项，且手工冒烟、Developer ID
签名、公证、正式 DMG、干净 Mac 首启和 release tag 证据尚未完成。当前项目尚未加入付费 Apple
Developer Program，不能取得 Developer ID Application 证书或完成公证；任何 local QA build、
自签名包或 ad-hoc signed `.app` 都不得标记为可 alpha 分发。

`0.1.0-local-qa`：**可用于内部测试**。该结论只覆盖本机/受控测试机 local QA，不代表
Stage 1 alpha 可分发。当前产物为 ad-hoc signed app 和 local QA DMG；没有 Developer ID
签名、公证、stapler 或干净 Mac Gatekeeper 证据。

本清单只汇总发布门禁和证据，不补产品功能。当前日期：2026-05-11。

## 2. 证据来源

本清单交叉读取以下源事实：

- [release.md](release.md)
- [build.md](build.md)
- [stage-1-mvp.md](../roadmap/stage-1-mvp.md)
- [CHANGELOG.md](../../CHANGELOG.md)
- [testing.md](testing.md)
- [recovery-scenarios.md](recovery-scenarios.md)
- [stage-1-performance-baseline.md](stage-1-performance-baseline.md)

状态含义：

- **通过**：已有可复现文件、命令或日志证据。
- **不通过**：当前证据明确不满足发布门禁。
- **不适用**：该项不适用于 Stage 1 alpha，且原因明确。
- **无法验证**：当前环境或证据不足，发布风险必须写明。

## 3. 发布门禁表

| 项目 | 状态 | 证据 | 发布风险 |
|---|---|---|---|
| CI / check-all | 通过 | 2026-05-11 00:31 CST 本地 `./dev check all` 已完整通过：governance、skills、task-loop、prompt doctor、`git diff --check`、Rust fmt / clippy / test、macOS prerequisite、universal Core build、macOS XCTest、SwiftFormat 和 SwiftLint 均通过；SwiftFormat 输出 `0/226 files require formatting, 3 files skipped`，SwiftLint 输出 `Found 0 violations, 0 serious in 228 files`。远端 CI 尚无 PR 或 tag 证据 | 本地综合门禁已关闭；发布仍需远端 CI/tag 证据 |
| macOS XCTest | 通过 | 2026-05-11 本地 `./dev check all` 内的 `./dev test macos` 已通过，覆盖大量 `CoreBridge()` 真实 Core 集成与 page integration verify 测试；2026-05-11 单跑 `./dev test macos --only-testing AreaMatrixTests/ImportBatchCopyImportModelTests` 和 `./dev test macos --only-testing AreaMatrixTests/ImportProgressCopyQueueRecoveryTests` 均 `TEST SUCCEEDED`；2026-05-10 18:12 CST 单跑 `./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests` 时标准 `xcodebuild test` 直接 `TEST SUCCEEDED`，5 个 `AreaMatrixPerfTests` 全部通过 | 该证据不能替代 Developer ID 签名、公证、DMG 公证或干净 Mac 首启 |
| P0 / P1 | 不通过 | `stage-1-performance-baseline.md` 已关闭真实 Release `.app` 启动到首屏 P1；`recovery-scenarios.md` 记录 M-01 Copy 中断恢复手工证据已通过、M-02 因当前没有 iCloud placeholder 环境而 blocked、M-03 权限恢复手工证据已通过、M-04 DB repair 手工证据已通过；2026-05-10 18:30 CST `./dev release preflight` 已运行但 BLOCKED：本机无 valid Developer ID Application signing identity，`AC_PASSWORD` notarytool keychain profile 不可用；当前无付费 Apple Developer Program，无法获取 Developer ID 证书或提交公证；2026-05-11 已生成 `AreaMatrix-0.1.0-local-qa.dmg`，但它只是 local QA DMG；干净 Mac 首启和 `v0.1.0` tag 仍缺发布证据 | 存在未关闭 P1 时不得放行最终集成验收；local QA build 只能用于内部测试，不能替代 alpha 分发 |
| 手工冒烟 | 不通过 | `testing.md#手工冒烟清单` 和 `recovery-scenarios.md#3-手工验证清单` 已定义；2026-05-10 21:27 CST M-01 Copy 中断恢复已在 local QA Release `.app` 手工通过；M-02 真实 iCloud placeholder 因当前没有 iCloud placeholder 环境而 blocked，后续补证模板已写入 `recovery-scenarios.md`；2026-05-10 22:21 CST M-03 权限恢复已在 local QA Release `.app` 手工通过，UI 显示 `Repository needs permission` / `PermissionDenied` / `Reconnect folder`，恢复权限后主列表可重新加载，DB `PRAGMA integrity_check` 返回 `ok`、用户文件 checksum 不变、staging 为 `0`、根目录未生成 `AREAMATRIX.md`；2026-05-10 21:58 CST M-04 DB repair 已在 local QA Release `.app` 手工通过，修复后主列表可加载、DB `PRAGMA integrity_check` 返回 `ok`、用户文件 checksum 不变、根目录未生成 `AREAMATRIX.md`；2026-05-11 DMG 内 `.app` 使用已配置 QA repo 启动到主窗口，`applicationLaunchToFirstScreen.localQA.dmgConfiguredRepo` 为 `668.973 ms < 1.5s`；2026-05-11 00:58 CST 另跑同机 local QA DMG 首启交互 smoke：`open -n "/Volumes/AreaMatrix 0.1.0 Local QA/AreaMatrix.app"` 成功，AppleScript 返回 `true, 60, 50, 1500, 980, AreaMatrix`，`/tmp/areamatrix_scroll_down.swift` 输出 `scroll_probe=posted events=7 point=900,610` | iCloud 未跑完，仍可能漏掉真实系统边界问题；M-03 本轮为 local QA repo 可逆 POSIX 权限阻断，不等同于正式分发机 TCC 数据库撤权；同机 local QA 交互 smoke 不能替代干净 Mac、Gatekeeper 或 notarized app 验证 |
| 性能基线 | 通过 | Core 与 Swift 指标通过；2026-05-10 18:12 CST `./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests` 标准 `xcodebuild test` 直接通过，Release build、ad-hoc `codesign --verify --deep --strict`、`otool -L` 自包含检查和真实 `.app` 启动 probe 均完成；`STAGE1_PERF name="applicationLaunchToFirstScreen.realApp" value_ms=777.606 threshold_ms=1500.000 result=PASS` | 性能 gate 已关闭；不能替代签名、公证、DMG 或干净 Mac 首启 |
| 依赖 dry-run | 通过 | 2026-05-10 18:07 CST 在 `core/` 执行 `cargo update --dry-run` 通过；crates.io index 可更新，dry-run 提示 8 个兼容更新并明确 `not updating lockfile due to dry run` | lockfile 未被修改；正式升级依赖仍需单独任务评估 |
| 文档 / API 一致性 | 通过 | `release.md`、`build.md`、Stage 1 MVP、本清单和文档锁定测试已对齐发布门禁；本地 `./dev check all` 已通过，覆盖 Core API / UDL 相关本地 validation | 远端 CI/tag 仍需补证 |
| CHANGELOG | 通过 | `CHANGELOG.md` 已切出 `[0.1.0] - 2026-05-10`，顶部 `[Unreleased]` 记录 `0.1.0-local-qa` 内部测试产物和 Swift `file_length` 修复；`release-notes-0.1.0.md` 已改为 `0.1.0-local-qa` internal QA notes，记录 artifact、checksum、validation snapshot 和 known issues | local QA notes 已可审阅；正式发布前仍需真实 tag |
| 版本号 | 部分通过 | `core/Cargo.toml` 与 Xcode `MARKETING_VERSION` 当前为 `0.1.0`；Xcode `CURRENT_PROJECT_VERSION` 已更新为 `202605101812`；当前工作区尚未提交，因此未创建 `v0.1.0` tag | 不得在未提交 release candidate 上提前打 tag |
| 已知问题 | 不通过 | 当前已知 P1：M-02 iCloud placeholder 手工冒烟因环境 blocked，Developer ID 签名/公证/正式 DMG/干净 Mac 首启 pending、`v0.1.0` tag 未创建；M-03 权限恢复已用 local QA repo 可逆 POSIX 权限阻断完成，未修改系统 TCC 数据库；已写入 `CHANGELOG.md` 和 `release-notes-0.1.0.md` | 已知问题未关闭或 release notes 未随最终 tag 发布时不得分发 |
| 不付费 local QA build | 通过 | 2026-05-11 已构建 `build/Build/Products/Release/AreaMatrix.app`，版本 `0.1.0` / build `202605101812`；使用 `CODE_SIGN_IDENTITY=-` 生成 ad-hoc signed app，`codesign --verify --deep --strict --verbose=2` 通过，`codesign -dv` 显示 `Signature=adhoc`、`TeamIdentifier=not set`、`Runtime Version=26.2.0`；`otool -L` 不再包含 `libarea_matrix_core.dylib`；`AreaMatrix-0.1.0-local-qa.dmg` SHA-256 为 `4e52b8e648326aaf3731fc61f12f4d576bbeeeff7a521d0efe528eec032c617b`，挂载后 `.app` 可验证并可打开已配置 QA repo 主窗口；同机窗口 resize/scroll probe 已通过 | 只允许内部测试；tester 可能需要手动信任或绕过 Gatekeeper，风险与体验均不同于 Developer ID notarized app |

## 4. Alpha 分发状态

| 项目 | 状态 | 证据 | 发布风险 |
|---|---|---|---|
| 签名 | 无法验证 | `stage-1-performance-baseline.md` 记录 ad-hoc `codesign --verify` 可作为本地 probe；2026-05-10 18:30 CST `./dev release preflight` 返回 BLOCKED：`no valid Developer ID Application signing identity found`；当前无付费 Apple Developer Program，不能签发 Developer ID Application 证书；2026-05-11 local QA app 是 `Signature=adhoc`、`TeamIdentifier=not set` | Gatekeeper、用户首次打开和崩溃定位均不可控；ad-hoc 签名只能证明本机包结构，不是分发签名 |
| 公证 | 无法验证 | `release.md` 定义 `xcrun notarytool submit` 和 stapler；2026-05-10 18:30 CST `./dev release preflight` 返回 BLOCKED：`AC_PASSWORD` profile 没有 keychain password item；未加入 Apple Developer Program 时不能提交 Developer ID 公证，当前无 notary id、log 或 stapled app 证据 | 未公证包可能被 macOS 阻止打开 |
| DMG | 无法验证（local QA 已生成） | `release.md` / `build.md` 定义 `hdiutil create`；2026-05-11 已生成 local QA DMG `AreaMatrix-0.1.0-local-qa.dmg`，SHA-256 `4e52b8e648326aaf3731fc61f12f4d576bbeeeff7a521d0efe528eec032c617b`，`hdiutil attach` CRC 验证通过，挂载路径 `/Volumes/AreaMatrix 0.1.0 Local QA` 内 `.app` 通过 ad-hoc `codesign --verify`；`spctl` 输出 `accepted` 但来源为 `override=security disabled`，不是 Developer ID 或 notarization 证据 | alpha tester 仍无 Developer ID signed / notarized DMG；local QA DMG 只能给受控测试机，不得作为正式 alpha |
| 干净 Mac 首启 | 无法验证 | Stage 1 MVP 要求安装后无需配置即可使用；当前没有干净 Mac 可用，状态为 `pending/no clean Mac available`，无干净 Mac 启动日志或截图。2026-05-11 00:58 CST 已完成同机 local QA 首启交互 smoke：DMG 挂载、`.app` 打开、AppleScript 窗口置前并调整为 `1500x980`、Swift CGEvent scroll probe 投递 7 次滚动事件 | 同机 local QA smoke 只能说明当前开发机包可打开和窗口可交互；首次启动、权限、Gatekeeper、repo 选择流程仍可能在干净用户机器失败 |
| 已知问题列表 | 通过 | 本清单第 5 节、`CHANGELOG.md` 和 `release-notes-0.1.0.md` 已记录当前 release blockers / known issues | 发布前仍需确认已知问题与最终 tag 对齐 |
| 反馈渠道 | 无法验证 | Stage 1 MVP 指向 GitHub Discussions；当前未记录 alpha tester 名单、Discussion 链接或 issue 模板入口 | tester 无明确反馈闭环 |

## 5. 当前阻断项

| ID | 等级 | 阻断项 | 必须补齐的证据 |
|---|---|---|---|
| P1-RL-001 | Closed | 真实 Release `.app` 启动到首屏证据已补齐 | 2026-05-10 18:12 CST `./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests` 标准 XCTest 通过，Release build、codesign、`otool -L` 与 `macos_launch_probe.swift` 均通过；真实 `.app` 首屏 `777.606 ms < 1.5s` |
| P1-RL-002 | P1 | M-01 Copy 中断恢复手工证据已通过；M-02 因当前没有 iCloud placeholder 环境而 blocked；M-03 权限恢复手工证据已通过；M-04 DB repair 手工证据已通过 | M-02 需要可用 iCloud 环境后重测；若后续要证明真实系统 TCC 数据库撤权，还需在发布机补充系统设置级证据 |
| P1-RL-003 | P1 | Developer ID 签名/公证预检已补可复现命令，但当前项目无付费 Apple Developer Program，环境 BLOCKED；正式 DMG、公证、干净 Mac 首启证据仍缺失；2026-05-11 只生成 local QA DMG，并完成同机 local QA 首启交互 smoke | 2026-05-10 18:30 CST `./dev release preflight` 退出码 1：无 valid Developer ID Application signing identity，`AC_PASSWORD` notarytool keychain profile 不可用；ad-hoc signed `.app`、同机 AppleScript/scroll smoke 或 `AreaMatrix-0.1.0-local-qa.dmg` 不能替代 Developer ID codesign、notarytool accepted log、stapler、DMG checksum、DMG 公证日志和干净 Mac 首启记录 |
| P1-RL-004 | P1 | CHANGELOG / release notes / build number 已完成；`v0.1.0` tag 尚未创建，状态为 `pending，不创建` | release candidate 提交、正式 alpha 门禁关闭后再创建并推送 `v0.1.0` tag；当前 local QA 不创建 GitHub Release |
| P1-RL-005 | Closed | 本地 check-all 已完整通过；依赖 dry-run 已补证；Swift `file_length` 工程门禁已通过拆分关闭 | 2026-05-11 00:31 CST `./dev check all` 退出码 0，SwiftFormat `0/226 files require formatting, 3 files skipped`，SwiftLint `Found 0 violations, 0 serious in 228 files`；2026-05-10 18:07 CST `cd core && cargo update --dry-run` 退出码 0 |

## 6. 放行规则

以下任一条件存在时，Stage 1 alpha 不得放行：

- 任一 P0 / P1 未关闭或未记录明确豁免依据。
- `./dev check all`、远端 CI 或 `git diff --check` 失败。
- 手工冒烟未跑，或任一手工冒烟结果为 fail / pending。
- 性能基线缺失，尤其是真实 Release `.app` 启动到首屏缺证据。
- 签名或公证状态不明。
- DMG 未生成、未签名、未公证，或未在干净 Mac 上首启验证。
- `CHANGELOG.md`、release notes、版本号或已知问题列表未完成。
- 产物只是 local QA build、自签名或 ad-hoc signed `.app`，却被标记为正式 alpha 分发物。

只有上述阻断项全部关闭后，发布人才能把本清单第 1 节改为放行结论；在那之前，
本文件不得出现当前已放行的结论文本。

## 7. 回滚

本任务只新增发布证据文档和文档锁定测试。若本清单需要回滚，只撤销：

- `docs/development/stage-1-release-checklist.md`
- `core/tests/stage1_release_checklist.rs`
- `docs/development/release.md` 中指向本清单的发布前说明
- `docs/development/build.md` 中 Stage 1 alpha 发布构建说明

不得把回滚扩大到产品实现、Core API、UDL、DB、用户文件或 macOS app 行为。

## Related

- [release.md](release.md)
- [build.md](build.md)
- [testing.md](testing.md)
- [recovery-scenarios.md](recovery-scenarios.md)
- [stage-1-performance-baseline.md](stage-1-performance-baseline.md)
- [../roadmap/stage-1-mvp.md](../roadmap/stage-1-mvp.md)
