# 跨平台运行时与 E2E 审计记录

## 结论状态

- 审计状态：`IN_PROGRESS`；交付门禁：`NOT-READY`。
- 本轮没有修改产品源码、文档、工程文件、bindings、测试或生成物；只更新本目录允许的审计台账。
- 未运行 `build_ledger.py`，避免重置已有覆盖台账。
- 冻结范围为 5,053 个文件、1,498,037 行；历史人工审阅 SHA-256 5,053/5,053 匹配。
- 哈希匹配只继承 `full-repo-audit-20260819` 的人工审阅记录，不等于 2026-08-20 本轮重新逐文件逐行阅读；`coverage.jsonl` 保持 `current_semantic_status=PENDING` 全量不变。

## 规则与上下文

- 已读取根、`core/`、`apps/macos/`、`workflow/` 最近的 `AGENTS.md`，以及产品工作流/界面、分层/FFI、恢复、测试、发布、隐私、Core API/UDL 等权威文档。
- 本轮按企业治理、文件安全、验证驱动和 macOS UI 技能的证据分级执行。
- 子代理仅只读：macOS 代理收束 session metadata/silent save；Windows/Linux 代理收束 native export、decoder、picker、preview 和 packaging；Core/FFI 代理未完成连接，主代理沿源码和已有动态证据复核。
- 当前主机：macOS 26.4.1 arm64，Xcode 26.4.1，Rust 1.94.1，.NET 9.0.306；WinUI runtime、真实 iOS device、真实 iCloud/OneDrive、远程 Provider 均不可用或未授权。

## Findings 复核

- 共 15 条：P1=4，P2=11；没有 P0/P3。
- 隔离 fixture 直接确认：`CP-E2E-002`（.areamatrix symlink DB 写入）、`CP-E2E-003`（iCloud 中间 symlink Trash）、`CP-E2E-004`（macOS session symlink 删除/覆盖）、`CP-E2E-005`（stale preview apply）。
- 其余条目是静态闭合调用链、harness 失败或环境阻断，不把编译/测试升级为目标平台 E2E。
- 关键 P1 是 AI privacy producer 脱离 evaluator、Core metadata symlink 越界、iCloud conflict symlink 越界、macOS import session symlink 越界。
- Windows/Linux export 和 decoder 是静态确认；Linux hostless native harness 另有 `EntryPointNotFoundException load_config` 失败证据。

## 已排除或降级

- macOS InFlight filtered-only cursor：符合 `docs/architecture/fs-watcher.md` 的 ordered window/ack 合同，降为设计 residual，不记 finding。
- import/category/external-sync 中间 symlink：没有闭合到已确认误操作的动态路径，除已确认的 Core/iCloud/session 条目外不扩报。
- batch category/rename preview token 不完整：尚未证明实际错误操作，保留 residual。
- Share ticket ID 路径问题：需要篡改 app-group ticket，置信度不足，排除。
- 其他并发治理审计的 release/promotion/task-loop findings 不合并，避免跨审计污染。

## 验证记录

- PASS：`cargo fmt --all -- --check`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --workspace --all-features`。
- PASS：`swift build --package-path apps/ios`、`swift test --package-path apps/ios`（106 tests）、`./dev bindings verify`、`./dev build core-sdk --verify-only`（fingerprint `265bee1ffba7`）。
- PASS：`./dev test macos --temporary-derived-data --disable-parallel-testing`（1357 tests、9 skipped、0 failures、81-key localization PASS）。
- PASS：Linux managed project build、Windows hostless tests；这些均标记为 harness/fixture。
- BLOCKED：Windows WinUI product build（macOS 无法执行 `XamlCompiler.exe`）、真实 iOS device/Share Extension、真实云账号、真实 Provider、clean notarized Mac。
- 所有安全 fixture 使用新的临时目录、临时 HOME/Trash 或 test target；结束后复核 fixture root 不存在，未访问真实用户文件。

## 收尾门禁

- JSONL 与 `scope.json` 必须逐文件用 `jq -e .` 校验。
- 只允许本目录九个台账文件发生本轮编辑；工作树其余脏改动均为既有用户/并发审计改动，不能回滚或混入本审计。
- 在 coverage 仍有 5,053 个 `PENDING`、真实平台流程未建立、finding 未完成修复/复验前，禁止写“审计完成”“正式支持”或“跨平台 E2E PASS”。
