# Stage 1 Release Checklist

> Stage 1 MVP alpha 分发前的发布清单、证据状态和阻断结论。
>
> 阅读时长：约 7 分钟。

---

## 1. 当前结论

当前结论：**不放行 Stage 1 alpha 分发**。

最终集成验收：**不放行**。原因是当前仍存在 P1 release 阻断项，且手工冒烟、签名、
公证、DMG 和干净 Mac 首启证据尚未完成。任何 release candidate 在这些项目完成前，不得
标记为可 alpha 分发。

本清单只汇总发布门禁和证据，不补产品功能。当前日期：2026-05-09。

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
| CI / check-all | 不通过 | 本地 `./dev check all` 已运行：governance、skills、task-loop、prompt doctor、`git diff --check`、Rust fmt / clippy / test 均通过；macOS checks 在构建前因缺少 `uniffi-bindgen` 停止；远端 CI 尚无 PR 或 tag 证据 | check-all 未完整通过，不得合并或发布 |
| P0 / P1 | 不通过 | `stage-1-performance-baseline.md` 记录 P1：真实 Release `.app` 启动到首屏证据缺失；`recovery-scenarios.md` 记录 M-01..M-04 手工证据 pending | 存在 P1 时不得放行最终集成验收 |
| 手工冒烟 | 无法验证 | `testing.md#手工冒烟清单` 和 `recovery-scenarios.md#3-手工验证清单` 已定义；当前未记录发布机执行日志 | 真实 macOS、iCloud、TCC、强退恢复未跑完，可能漏掉用户文件安全问题 |
| 性能基线 | 不通过 | Core 与 Swift hostless 指标通过；真实 Release `.app` 启动到首屏被当前 sandbox 阻断 | 启动时间 `< 1.5s` 的最终 MVP 标准缺真实 `.app` 证据 |
| 依赖 dry-run | 无法验证 | 仓库根目录执行 `cargo update --dry-run` 因缺少根 `Cargo.toml` 失败；切到 `core/` 后因当前环境无法解析 `index.crates.io` 而失败 | dry-run 未完成时无法发现 lockfile、registry 或供应链升级风险 |
| 文档 / API 一致性 | 无法验证 | `release.md`、`build.md`、Stage 1 MVP 和本清单已对齐发布门禁；Core API / UDL 一致性仍依赖本地和 CI validation | API / UDL 漂移会让 alpha 包与文档不一致 |
| CHANGELOG | 不通过 | `CHANGELOG.md` 仍停留在 `[Unreleased]`，尚无 `[0.1.0] - YYYY-MM-DD` release 段落 | alpha 用户无法判断本版变更、已知问题和回滚范围 |
| 版本号 | 不通过 | `core/Cargo.toml` 与 Xcode `MARKETING_VERSION` 当前为 `0.1.0`，但 app build number 仍为 `1`，且 release tag 未确认 | 版本可见性和 crash/反馈定位不稳定 |
| 已知问题 | 不通过 | 当前已知 P1：真实 `.app` 启动证据缺失、手工恢复冒烟 pending、签名/公证/DMG pending | 已知问题未关闭或未写入 release notes 时不得分发 |

## 4. Alpha 分发状态

| 项目 | 状态 | 证据 | 发布风险 |
|---|---|---|---|
| 签名 | 无法验证 | `stage-1-performance-baseline.md` 记录 ad-hoc `codesign --verify` 可作为本地 probe；Developer ID 签名未记录 | Gatekeeper、用户首次打开和崩溃定位均不可控 |
| 公证 | 无法验证 | `release.md` 定义 `xcrun notarytool submit` 和 stapler；当前无 notary id、log 或 stapled app 证据 | 未公证包可能被 macOS 阻止打开 |
| DMG | 无法验证 | `release.md` / `build.md` 定义 `hdiutil create`；当前无 `AreaMatrix-0.1.0.dmg` checksum、签名或公证证据 | alpha tester 无可验证分发物 |
| 干净 Mac 首启 | 无法验证 | Stage 1 MVP 要求安装后无需配置即可使用；当前无干净 Mac 启动日志或截图 | 首次启动、权限、Gatekeeper、repo 选择流程可能在用户机器失败 |
| 已知问题列表 | 不通过 | 本清单第 5 节记录当前 release blockers；`CHANGELOG.md` 尚无 0.1.0 已知问题段落 | 分发说明不完整会误导 tester |
| 反馈渠道 | 无法验证 | Stage 1 MVP 指向 GitHub Discussions；当前未记录 alpha tester 名单、Discussion 链接或 issue 模板入口 | tester 无明确反馈闭环 |

## 5. 当前阻断项

| ID | 等级 | 阻断项 | 必须补齐的证据 |
|---|---|---|---|
| P1-RL-001 | P1 | 真实 Release `.app` 启动到首屏证据缺失 | 在非 Codex sandbox 的 macOS 桌面会话或 CI runner 上运行真实 `.app` launch / Instruments 证据，证明 `< 1.5s` |
| P1-RL-002 | P1 | M-01..M-04 手工恢复冒烟均为 pending | 为 import 中断、iCloud placeholder、TCC 权限、DB repair 写入结构化手工证据 |
| P1-RL-003 | P1 | Developer ID 签名、公证、DMG、干净 Mac 首启证据缺失 | 提供 codesign、notarytool、stapler、DMG checksum、公证日志和干净 Mac 首启记录 |
| P1-RL-004 | P1 | CHANGELOG / 版本发布切面未完成 | 将 `[Unreleased]` 切成 `[0.1.0] - YYYY-MM-DD`，确认 app build number、tag 和 release notes |
| P1-RL-005 | P1 | 本地 check-all 未完整通过，依赖 dry-run 无法完成 | 安装 `uniffi-bindgen`，在可访问 crates.io 的环境补跑 `./dev check all` 与 `cd core && cargo update --dry-run` |

## 6. 放行规则

以下任一条件存在时，Stage 1 alpha 不得放行：

- 任一 P0 / P1 未关闭或未记录明确豁免依据。
- `./dev check all`、远端 CI 或 `git diff --check` 失败。
- 手工冒烟未跑，或任一手工冒烟结果为 fail / pending。
- 性能基线缺失，尤其是真实 Release `.app` 启动到首屏缺证据。
- 签名或公证状态不明。
- DMG 未生成、未签名、未公证，或未在干净 Mac 上首启验证。
- `CHANGELOG.md`、release notes、版本号或已知问题列表未完成。

只有上述阻断项全部关闭后，发布人才能把本清单结论改为：

```text
当前结论：放行 Stage 1 alpha 分发
最终集成验收：放行
```

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
