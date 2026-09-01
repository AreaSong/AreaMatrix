# 依赖、许可证与供应链审计记录

## 审计结论

- 审计 ID：`dependency-supply-chain-audit-20260830`
- 仓库：`/Users/as/Ai-Project/project/AreaMatrix`
- 冻结提交：`cf3647378d64885e8e6a44a2a5b60d8926668982`
- 分支：`codex/long-term-governance-bridge-contracts`
- 总体状态：`BLOCKED / NOT READY`
- 覆盖状态：机器守恒已闭合，`PENDING=0`、`IN_PROGRESS=0`；仍有 19 条未闭合 finding，因此不得宣称审计或发布准备完成。

## 权威规则

本轮先阅读根目录及相关目标目录最近的 `AGENTS.md`，并按顺序复核企业治理、验证、文档同步、文件安全与 macOS UI 规则。审计依据包括 `CODE_REVIEW.md`、`SECURITY.md`、`docs/development/dependency-policy.md`、`docs/development/ci-governance.md`、仓库许可证、第三方声明、构建和发布文档。

工作树冻结时已有大量用户/并发任务改动；完整状态保存在 `scope.json`。审计过程未清理、回滚、提交或推送这些改动，也未安装、升级或删除依赖。

## 并行审阅

按要求使用 3 个只读子代理并行审阅，分别覆盖：

- Rust、Cargo、UniFFI、`build.rs`、proc-macro、native/FFI、feature、`Cargo.lock` 与生成工具链。
- SwiftPM/Xcode、macOS/iOS、WinUI/.NET/NuGet、锁文件、native loader、预编译制品与平台分发链。
- Python、Shell、GitHub Actions、开发工具、下载脚本、品牌资产、字体、图标、样例资料、外部能力与许可证材料。

子代理不修改文件、不安装依赖、不执行破坏性操作，也不派生子代理。所有候选 finding 均由主代理回到声明、锁文件、实际调用方、构建脚本和发布路径交叉复核后才写入台账。

## 范围与方法

- 纳入文件：`5089`，其中 tracked `5052`、非忽略 untracked `37`。
- 文本 `4927`、二进制 `152`、符号链接 `10`、其他 `0`。
- 文本总行数：`1512716`。
- 当前字节与历史人工证据相同的文件复用逐文件证据；2026-08-22 快照后发生字节变化的 73 个文件在本轮重新阅读全文并复核依赖、下载、命令、权限、许可证、构建与发布语义。
- 二进制和确定性副本不逐字节解释，但逐项核对来源、目标、哈希、生成关系、是否入包及对应源文件。25 个不可逐行阅读的确定性图片/图标副本按路径分别记为 `NOT_APPLICABLE`，没有批量排除整个目录。
- 未跟踪的 `.codex/runtime/**` 运行证据共 113 项不属于仓库受控内容，逐项列在 `scope.json`；tracked runtime 文件仍纳入清单。
- `.gemini/` 与 `.codex/skills/` 中的机器本地、git-ignored 外部能力不属于仓库受控文件。`.codex/skills/frontend-design` 是指向仓库外的绝对符号链接，本轮未读取其外部目标、未修改，也未把它误记为仓库分发依赖。

覆盖状态仅使用 `PENDING`、`IN_PROGRESS`、`PASS`、`FINDING`、`NOT_APPLICABLE`、`BLOCKED`。每个纳入文件在 `coverage.jsonl` 中有独立状态、证据和备注。

## 辅助证据边界

人工审阅后才运行只读辅助命令和公开查询。没有运行 `cargo update`、`swift package update`、`dotnet add package`、`pip install`，没有执行来源不明的脚本或二进制，也没有上传源码、路径、凭据或用户数据。

只读外部证据包括：

- RustSec/OSV 对 164 个 Cargo registry 精确版本的公开查询。
- PyPI/OSV 对 Pillow 12.3.0 的版本、wheel 哈希、许可证与 advisory 查询。
- GitHub API 对 7 个 Action 固定 SHA、tag/commit 和许可证的公开查询。
- SwiftLint 0.65.0 与 SwiftFormat 0.62.1 官方 release asset digest 复核。
- Inter 上游 commit/blob、路径、大小与 SHA-256 复核。
- 15 个 NuGet 精确版本的公开 registration 元数据查询。

公开查询只能证明查询时点的远端状态，不能代替实际制品签名、包内容检查、法律批准、远端分支保护或受保护环境配置。

## 依赖与许可证台账

`dependency-ledger.jsonl` 和 `license-ledger.jsonl` 各有 228 条记录：直接 31、传递 160、隐式工具 19、平台 SDK/framework 15、项目本地包 2、项目根组件 1。

生态统计：Cargo 164、NuGet 15、Apple SDK/framework 15、GitHub Actions 7、系统工具 7、系统工具链 5、native artifact 3、第三方内容 2、Swift 本地包 2、release tool 2，以及 Python、字体、外部 runtime、生成 FFI、生成 native artifact、web-font 各 1。

许可证政策统计：`DEFAULT_ALLOWED=39`、`MANUAL_REVIEW_REQUIRED=164`、`EVIDENCE_INSUFFICIENT=20`、`PROJECT_LICENSE=4`、`BLOCKED_PENDING_ARTIFACT_REVIEW=1`。这些分类是政策路由，不等同于法律结论；180 条许可证/依赖记录仍以 `BLOCKED` 等待逐包、制品或法律闭合。

## 验证记录

本地通过：

- `cargo metadata --locked --offline`
- `cargo tree --locked --edges normal,build,dev`
- `cargo fmt --all -- --check`
- `cargo clippy --locked --all-targets --all-features -- -D warnings`
- `cargo test --locked --all-features --workspace`
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_*.py'`，439 个测试通过
- `./dev bindings verify`
- `swift test --package-path apps/macos/Packages/AreaMatrixModules`
- `swift build --package-path apps/ios`，仅证明当前 macOS host 可解析/构建，不能替代 iOS target 证据
- `./dev check governance/docs/wording/secrets/localization/skills/quality/prompts/diff/task-loop/codex-os`
- SwiftFormat lint、SwiftLint strict、`git diff --check`

未通过或环境阻断：

- `./dev workflow doctor`：8 个版本化 docs baseline 漂移，见 SC-031。
- `./dev build core-sdk --verify-only`：恢复的 CoreSDK fingerprint 与当前 source/tool fingerprint 不一致。
- 真实 Xcode universal CoreSDK/macOS/iOS 构建：缺 `x86_64-apple-darwin` 与 iOS Rust targets。
- `./dev release preflight --json`：无有效 Developer ID Application 身份，无可用 notary profile。
- Windows/Linux clean restore/build/test/package、真实 DLL/SO、签名与 package inspection：当前 macOS host 无法提供。
- 远端 branch protection、required checks、environment reviewers 与实际 workflow run：无经批准凭据，未取证。

## 工具链观察

- Rust：`rustc/cargo 1.88.0`。
- Python：本地 `3.9.6`，CI `3.12.11`。
- Swift/Xcode：本地 Swift `6.3.1`、Xcode `26.4.1 (17E202)`。
- .NET：本地 SDK `9.0.306`，无 workloads，仓库无 `global.json`。
- SwiftLint：本地 `0.63.2`，CI `0.65.0`。
- SwiftFormat：本地 `0.61.1`，CI `0.62.1`。
- 仅安装 Rust target `aarch64-apple-darwin`。

这些差异已作为 SC-037、SC-038、SC-039 记录，不能用本地通过结果替代受保护 CI 和目标平台证据。

## 审计运行目录事故记录

审计过程中，一次运行目录包装错误覆盖了旧的 `.codex/runtime/dependency-supply-chain-audit-20260822/` 快照内容。影响仅限未跟踪审计运行证据，没有修改业务代码、manifest、lockfile、workflow、用户文件或 git 历史。当前 `dependency-supply-chain-audit-20260830` 重新冻结范围并生成完整机器台账，作为后续权威快照；旧快照不再作为独立、完整的可恢复证据链引用。

## 台账哈希

- `scope.json`：`fb07419a284c488b8828918e0f4dd24c3fd61259b3f32fe45a0e738fe76c0f51`
- `inventory.jsonl`：`d44b4db0d20b5162bba66f0ab5fe4eebbbb17b6fd2305ca5ac4ed41b7ef51355`
- `coverage.jsonl`：`53963517f9678c95831831ade2d75b353ee603abc68c2233d99bc3a97757f65f`
- `dependency-ledger.jsonl`：`9935257db82b3290e3bbf0c41538c0c768bb1fbab93a631924dadbf02cae64fc`
- `license-ledger.jsonl`：`d1793f6043d986e17e263310bf7875e68f391864f8a19f1c854536e04329c35d`
- `findings.jsonl`：`bf03b884aecbd53dceb6d5d1af5ff2ba99aada2018d989c0c0f447e04feec34a`
- `cargo-metadata.json`：`72adb7ce7b62c72ae6da4cc9fb38c894252d2b947c52d7b1e0d8845b8952d254`

## 最终边界

本地可完成的代码、生成绑定、构建完整性、CI 固定引用与测试整改已经验证。仍缺的真实目标平台制品、签名/公证、远端治理 readback、逐包许可证闭包和合格法律 reviewer 记录不可由本机或代理伪造，因此本审计最终状态保持 `BLOCKED / NOT READY`。
