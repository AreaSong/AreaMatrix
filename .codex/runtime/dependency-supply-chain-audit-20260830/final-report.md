# AreaMatrix 全仓依赖、许可证与供应链审计最终报告

> 总体状态：`BLOCKED / NOT READY`。全仓逐文件覆盖和机器守恒已经闭合，但仍有 19 条未解决 finding、36 个 `BLOCKED` 文件，以及外部平台、远端治理和法律复核缺口。不得据此宣称审计完成、许可证闭合或产品可发布。

## Findings

本轮共记录 39 条候选：`FIXED=19`、`FIXED_LOCAL_BLOCKED_EXTERNAL=1`、未闭合 19 条。没有 P0。未闭合项为 P1 5 条、P2 8 条、P3 6 条；完整结构化字段见 `findings.jsonl`。

### P1

#### SC-002 `BLOCKED_EXTERNAL`：Windows native core 没有可发布制品

- 位置：`apps/windows/AreaMatrix/native-core.manifest.json:1-9`；`apps/windows/AreaMatrix/Core/NativeCoreLibrary.Loading.cs:23-39,115-261`。
- 链路与暴露：Windows app -> `AreaMatrixNativeCoreClient` -> manifest/hash/path 验证 -> `NativeLibrary.Load`；将进入 Windows Core/FFI、用户文件处理与产品包。
- 已有控制：loader 对 manifest、RID/架构、SHA-256、路径和 symlink fail-closed；当前 `artifacts=[]`，因此不会误加载占位物。
- 阻断原因：没有真实 DLL、source commit、签名、SBOM、NOTICE、许可证闭包或 package inspection。
- 最小闭合与回滚：由 Windows runner 生成并证明 RID/架构绑定制品；在证据完成前保持 Windows native launch/release 禁用。

#### SC-010 `BLOCKED`：tracked 历史 macOS 静态库 provenance 不完整

- 位置：`apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a.provenance.json:1-79`；`apps/macos/XcodeGen/project.yml:91-99,153-179`。
- 链路与暴露：历史 `libarea_matrix_core.a` 是潜在 macOS 构建输入；权威工程已改为 fingerprinted CoreSDK XCFramework。
- 已有控制：记录 blob hash、size、lipo 信息；canonical project 不再消费 legacy archive。
- 阻断原因：仍为 `historical-unattested`，缺 artifact-to-commit、完整 SBOM/NOTICE、签名/公证和可重复构建证明。
- 最小闭合与回滚：经独立审批删除该历史 blob，或用完整 attestation 重建；此前继续从发布根排除并只保留 CoreSDK 路径。

#### SC-014 `BLOCKED_EXTERNAL`：发布 SBOM/NOTICE/source-offer/签名公证闭环未完成

- 位置：`THIRD_PARTY_NOTICES.md:25-39`；`scripts/dev_tools/supply_chain.py:1-500`；`.github/workflows/release-supply-chain.yml:81-167`。
- 链路与暴露：真实发布制品 -> hash -> target-specific SBOM/NOTICE/source-offer -> 外部 review record -> 签名、公证、staple 和分发。
- 已有控制：本地生成器已绑定 artifact hash、Cargo/NuGet 组件和 review gate。
- 阻断原因：没有真实 release artifact、Developer ID、notary、package inspection 或合格法律 reviewer 记录；生成器通过不等于制品内容通过。
- 最小闭合与回滚：在受保护 release workflow 对真实制品完成 readback；否则保持 release blocked，不分发。

#### SC-015 `BLOCKED_EXTERNAL`：Linux native core 仍为 fixture-only

- 位置：`apps/linux/AreaMatrix/native-core.manifest.json:1-9`；`apps/linux/AreaMatrix/Core/NativeCoreLibrary.Loading.cs:24-35`；`apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:1-25`。
- 链路与暴露：Linux app -> verified loader -> `area_matrix_core.so` -> Core/FFI/用户文件路径。
- 已有控制：默认 fail-closed，开发 fixture/override 有 hash 和 loader 测试。
- 阻断原因：没有产品 `.so`、签名、SBOM、许可证证据或 clean Linux publish/runtime 测试。
- 最小闭合与回滚：由 Linux runner 构建并证明目标 RID/架构制品，或明确移除产品分发目标；此前保持 fixture-only。

#### SC-026 `BLOCKED_EXTERNAL`：跨平台 clean build/package/FFI 证据缺失

- 位置：`scripts/dev_tools/core_sdk.py:321-485`；`apps/ios/Package.swift:1-49`；`.github/workflows/macos-ci.yml:61-69,350-367`；Windows/Linux native manifests。
- 链路与暴露：Rust Core -> UniFFI -> Apple CoreSDK、Windows DLL、Linux SO -> 平台 package。
- 已有控制：source/tool fingerprint、内部文件 hash、lockfile、loader 与绑定 contract tests。
- 阻断原因：缺 universal CoreSDK、真实 iOS target、Windows/Linux clean runner、签名/公证、干净机安装与 package contents 证据。
- 最小闭合与回滚：分别在受支持平台执行隔离 clean build/package 并归档 hash、SBOM、签名和 FFI smoke evidence；此前不发布相关平台。

### P2

#### SC-011 `BLOCKED`：Inter 字体及派生品牌资产需许可证复核

- 位置：`assets/brand/provenance.json:1-26`；`assets/brand/wordmark-outlines.json:1-20`；`licenses/OFL-1.1-Inter.txt:1`；`docs/ux/brand-assets.md:90-105`。
- 已确认：上游 commit/blob、路径、大小、输入 SHA-256 与派生 hash 技术链一致。
- 阻断原因：OFL-1.1、字体派生字标、商标/归属及最终分发义务尚无合格 reviewer 签核。
- 最小闭合：对输入字体和每个入包派生物做独立许可证/归属复核；失败则从发布制品排除并采用独立授权替代物。

#### SC-022 `BLOCKED`：16 个品牌历史探索稿来源与授权未知

- 位置：`assets/brand/archive/**`；`assets/brand/provenance.json:29-153`；`THIRD_PARTY_NOTICES.md:22-24`。
- 已确认：每个 archive 文件有独立 hash，状态为 `evidence-blocked`，并排除 release root。
- 阻断原因：hash 不能证明来源、作者或再分发授权；仓库分发本身仍有风险。
- 最小闭合：取得来源/授权，或在明确审批和可恢复方案下从仓库移除；本轮未擅自删除历史资产。

#### SC-024 `BLOCKED`：Cargo/NuGet 逐包许可证闭包未完成

- 位置：`core/Cargo.lock:1-1500`；`apps/windows/AreaMatrix/packages.lock.json:1-220`；`THIRD_PARTY_NOTICES.md:20-39`。
- 链路与暴露：164 个 Cargo 包与 15 个 NuGet 包覆盖 runtime、build/proc-macro、FFI 和 Windows restore/package。
- 已有控制：Cargo checksum、NuGet contentHash、locked restore、source mapping、signature validation 与 target-aware SBOM extraction。
- 阻断原因：NuGet registration 多数为 `NOASSERTION`；Cargo 复合许可证、MPL/LGPL/exception、逐包 NOTICE/源码提供义务尚未从精确 archive 和真实制品闭合。
- 最小闭合：抽取精确包许可证/NOTICE，生成目标制品 SBOM 并由合格 reviewer 确认；此前不得把项目许可证当作第三方闭包。

#### SC-031 `BLOCKED`：版本化 workflow 文档基线漂移

- 位置：`workflow/versions/v2/baseline/docs.yaml:1`；`workflow/versions/v3/baseline/docs.yaml:1`；`workflow/versions/v4/baseline/docs.yaml:1`。
- 证据：`./dev workflow doctor` 返回 8 个唯一漂移项，涉及 v2 governance/CI、v3 migration/classifier/coding/testing/CI、v4 testing。
- 风险：版本化执行材料与当前权威文档不一致，无法证明治理和供应链门禁的历史基线仍有效。
- 最小闭合：由各版本 owner 逐项审阅后只刷新获批 baseline；不得在当前混合脏工作树中批量接受漂移。

#### SC-032 `BLOCKED_LEGAL`：gitleaks-action 专有 EULA 未批准

- 位置：`.github/workflows/governance-ci.yml:82-83`；`docs/development/ci-governance.md:248-252`。
- 已确认：Action 固定完整 SHA；当前 GitHub 账户公开类型为个人 `User`，EULA 文本称个人账户无需 key。
- 阻断原因：专有 EULA、账户范围和未来组织化使用尚未进入 AreaMatrix 批准记录。
- 最小闭合：由合格 reviewer 确认精确 EULA/account scope 并登记，或在独立依赖变更中替换；远端 CI 需复核实际账户语义。

#### SC-034 `BLOCKED_EXTERNAL`：远端分支保护、required checks 与 environment 未取证

- 位置：`docs/development/ci-governance.md:77-78,117-155`；`.github/workflows/remote-governance.yml:1`；`.github/workflows/release-supply-chain.yml:1`。
- 风险：仓库内 workflow 正确不等于 GitHub 远端实际启用了 required checks、reviewers、环境保护和最小权限。
- 阻断原因：本轮没有使用真实凭据，无法合法读取私有/受保护设置和实际 run。
- 最小闭合：使用经批准的最小权限凭据运行只读远端审计，归档 branch protection、environment、required review 和 run URL/readback。

#### SC-037 `BLOCKED_OWNER_DECISION`：.NET SDK 未由 `global.json` 固定

- 位置：Windows/Linux app 与 test `.csproj` 的 `net9.0`/`net9.0-windows` target declarations。
- 风险：`dotnet restore/build/test/package` 选择维护者或 runner 全局 SDK；本地观测为 9.0.306，但无仓库级 roll-forward 政策。
- 最小闭合：owner 批准并新增 `global.json` 的 SDK/rollForward 规则，再在真实 Windows/Linux runner 完成 locked restore/build/test/package。
- 回滚：若固定版本不可用，恢复前一批准 policy，而不是依赖隐式全局选择。

#### SC-038 `BLOCKED_EXTERNAL`：Apple CI 使用 moving `macos-14` 默认 Xcode

- 位置：`.github/workflows/core-ci.yml:24-100`；`.github/workflows/macos-ci.yml:19-455`；`.github/workflows/release-evidence.yml:27`。
- 风险：runner image 和默认 Xcode 会移动，日志中打印版本不能使未来 rebuild 选择同一工具链。
- 本地观测：Xcode 26.4.1 / Swift 6.3.1；不能证明远端 runner 或历史制品使用相同工具链。
- 最小闭合：采用经批准的精确 Xcode/image 选择策略，并将版本绑定到 CoreSDK/release provenance 后做远端 clean build readback。

### P3

#### SC-020 `BLOCKED_OWNER_DECISION`：anyhow 1.0.102 命中 RUSTSEC-2026-0190

- 位置：`core/Cargo.lock:36`；经 UniFFI runtime/build/meta/bindgen 进入闭包。
- 证据：RustSec/OSV 确认 `<1.0.103` 受 `Error::downcast_mut` unsoundness 影响；本地 AreaMatrix 与 UniFFI 0.28.3 源码未发现 `downcast_mut` 调用路径。
- 风险判断：已确认受影响版本，但未建立当前产品触发链，因此为 P3，不夸大为可利用漏洞。
- 最小闭合：在独立依赖变更中升级到 `>=1.0.103` 并重建验证，或由 owner 批准有期限、带可达性证据的例外。

#### SC-023 `BLOCKED`：第三方行为准则改编材料需法律复核

- 位置：`CODE_OF_CONDUCT.md:77-83`；`licenses/CC-BY-4.0-Contributor-Covenant.txt:1`；`licenses/MPL-2.0-Mozilla-Inclusion.txt:1`；`THIRD_PARTY_NOTICES.md:17-18`。
- 已确认：固定 upstream tag/commit、许可证文本与 notices 已补齐。
- 阻断原因：Contributor Covenant / Mozilla 参考材料的具体改编范围、归属和再分发义务尚无合格 reviewer 结论。
- 最小闭合：记录法律/归属签核；若不批准，替换为独立创作的治理文本。

#### SC-033 `BLOCKED_LEGAL`：rust-cache Action 的 LGPL-3.0 使用方式未专项复核

- 位置：`.github/workflows/core-ci.yml:58,74,92,110`；`.github/workflows/macos-ci.yml:53`。
- 已确认：`Swatinem/rust-cache` 固定到 v2.8.1 的签名 annotated tag/commit，许可证为 LGPL-3.0。
- 阻断原因：CI-only 执行、缓存产物、NOTICE/源码义务与再分发边界尚未进入批准记录。
- 最小闭合：完成专项许可证与缓存 threat-path 复核，或在独立依赖变更中替换。

#### SC-035 `BLOCKED_OWNER_DECISION`：bincode 1.3.3 已停止维护

- 位置：`core/Cargo.lock:1`；经 UniFFI proc-macro 闭包进入构建链。
- 证据：OSV/RustSec `RUSTSEC-2025-0141` 为 unmaintained informational，不是已确认漏洞。
- 最小闭合：升级 UniFFI 闭包或登记有期限的替换/例外计划；变更后重跑 bindings、CoreSDK、fmt、clippy、test。

#### SC-036 `BLOCKED_OWNER_DECISION`：paste 1.0.15 已停止维护

- 位置：`core/Cargo.lock:1`；经 UniFFI core/bindgen/build proc-macro 路径在构建期执行。
- 证据：OSV/RustSec `RUSTSEC-2024-0436` 为 unmaintained informational，不是已确认漏洞。
- 最小闭合：升级 UniFFI 闭包移除 paste，或登记有期限的例外；变更后重建完整生成链。

#### SC-039 `BLOCKED_OWNER_DECISION`：本地开发工具版本与 CI 固定版本不一致

- 位置：`.github/workflows/governance-ci.yml:28-30`；`.github/workflows/release-supply-chain.yml:77-79`；`.github/workflows/macos-ci.yml:414-455`；`scripts/dev_tools/checks.py:3273-3293`。
- 证据：CI 固定 Python 3.12.11、SwiftLint 0.65.0、SwiftFormat 0.62.1；本地分别为 3.9.6、0.63.2、0.61.1。
- 风险：本地 PASS 与受保护 CI 不具版本等价性，可能产生解析、格式或生成结果差异。
- 最小闭合：加入不安装依赖的精确版本 gate/wrapper，或由 owner 批准有期限的本地验证例外。

## 已修复项

以下 19 条本地修复已由当前源码和验证证据确认：

| ID | 结果 |
|---|---|
| SC-001 | Rust MSRV 统一为 1.88.0。 |
| SC-004 | 移除用户文件删除路径对 PATH `osascript`/`trash` 的依赖候选。 |
| SC-005 | Pillow 固定为 12.3.0、官方 binary wheel、`--require-hashes`；公开 OSV 查询为 0 条。 |
| SC-006 | Pillow MIT-CMU 文本与品牌开发/CI 边界进入政策和 notices。 |
| SC-007 | UniFFI runtime/build feature 拆分。 |
| SC-008 | bindgen fallback 改为锁定 wrapper/cache 校验。 |
| SC-009 | 关键 Cargo 命令使用 `--locked`。 |
| SC-012 | GitHub Actions 和下载工具固定不可移动 SHA/version/hash。 |
| SC-013 | governance workflow 权限/token 暴露收紧。 |
| SC-016 | 原型移除动态 Google Fonts 网络依赖。 |
| SC-017 | 文档移除 `curl | sh` 和浮动 stable 示例。 |
| SC-018 | 移除未使用 `tracing-appender`。 |
| SC-019 | 用 `serde_yaml_ng` 替换 deprecated `serde_yaml`。 |
| SC-021 | AI 外部 runtime 增加 approved manifest、path/hash/provider/privacy 绑定；产品模式 fail-closed。 |
| SC-025 | 7 个 Action 与 SwiftLint/SwiftFormat 对象身份由公开只读证据复核。 |
| SC-027 | CoreSDK manifest 绑定内部 archive、headers、Swift binding、Package.swift、Info.plist 等逐文件 hash，并有篡改负测。 |
| SC-028 | checkout 统一 `persist-credentials:false`，发布 ref 与触发 SHA 绑定。 |
| SC-029 | Inter provenance validator 精确限制 owner/repo/path/commit/input object。 |
| SC-030 | tracked UniFFI Swift/header 与 UDL/API 重新生成并通过 verify。 |

SC-003 为 `FIXED_LOCAL_BLOCKED_EXTERNAL`：Windows 已有 `packages.lock.json`、`RestoreLockedMode=true`、NuGet source mapping、`signatureValidationMode=require` 与 target-aware SBOM；真实 Windows restore、包签名和 package closure 仍由 SC-024/SC-026 阻断。

## 覆盖与守恒

| 项目 | 数量 |
|---|---:|
| 仓库纳入文件总数 | 5089 |
| PASS | 4957 |
| FINDING | 71 |
| NOT_APPLICABLE | 25 |
| BLOCKED | 36 |
| PENDING | 0 |
| IN_PROGRESS | 0 |

守恒证明：`4957 + 71 + 25 + 36 = 5089`。`inventory.jsonl` 与 `coverage.jsonl` 均为 5089 行；当前 scope drift 为 0，冻结后新增的非 runtime 文件为 0。

文件类型：文本 4927、二进制 152、符号链接 10，共 5089；文本总行数 1,512,716。25 个 `NOT_APPLICABLE` 均是逐路径记录的不可逐行阅读图片/图标确定性副本，证据字段说明其来源、hash/生成关系和入包边界。其余二进制与符号链接分别按来源、校验、生成链和目标复核，没有整目录批量排除。

113 个未跟踪 `.codex/runtime/**` 运行证据逐项列入 `scope.json` 的排除清单；tracked runtime 内容仍纳入。机器本地且 git-ignored 的 `.gemini/`、`.codex/skills/` 不属于仓库受控分发范围，仓库外 skill symlink 目标未读取或修改。

## 依赖台账

`dependency-ledger.jsonl` 共 228 条，记录名称、版本/范围、来源、直接或传递关系、runtime/dev/build 用途、声明和使用位置、许可证、锁定、完整性、风险和复核状态。

| 关系 | 数量 |
|---|---:|
| 直接 | 31 |
| 传递 | 160 |
| 隐式工具 | 19 |
| 平台 SDK/framework | 15 |
| 项目本地包 | 2 |
| 项目根组件 | 1 |

| 生态 | 数量 |
|---|---:|
| Cargo | 164 |
| NuGet | 15 |
| Apple SDK/framework | 15 |
| GitHub Action | 7 |
| system tool | 7 |
| system toolchain | 5 |
| native artifact | 3 |
| third-party content | 2 |
| Swift local package | 2 |
| release tool | 2 |
| 其他单项生态 | 6 |

未发现一个“已确认进入产品但完全没有进入台账”的第三方 package。发现并入账的未声明/环境隐式依赖包括：PATH 选择的 Python、SwiftLint、SwiftFormat、.NET SDK、Apple/Xcode 工具链、Rust targets、Git、Shell、curl、unzip、shasum、jq，以及仅用于只读远端审计的 `gh`。这些依赖的版本/平台漂移分别由 SC-037、SC-038、SC-039 和平台证据 finding 承接；`xcodegen` 当前缺失且不是 canonical 构建依赖。

## 许可证矩阵

| 政策分类 | 数量 | 结论 |
|---|---:|---|
| DEFAULT_ALLOWED | 39 | 许可证表达式符合默认允许集合，但仍需与真实制品/NOTICE 匹配。 |
| MANUAL_REVIEW_REQUIRED | 164 | 主要为 Cargo 复合/传递闭包；需逐包精确 archive 与合格 reviewer。 |
| EVIDENCE_INSUFFICIENT | 20 | 来源、许可证表达式、资产授权或平台制品证据不足。 |
| PROJECT_LICENSE | 4 | AreaMatrix 自有项目材料。 |
| BLOCKED_PENDING_ARTIFACT_REVIEW | 1 | 历史 native artifact 尚无完整 attestation。 |

默认阻断候选包括未知来源品牌 archive、缺失的 Windows/Linux native artifact、历史 unattested `.a` 和未批准的 gitleaks EULA。它们在结构化台账中按 `EVIDENCE_INSUFFICIENT`、`BLOCKED_PENDING_ARTIFACT_REVIEW` 或 finding 状态表达，不能因 `DEFAULT_BLOCK` 计数为 0 而视为允许。

Pillow 12.3.0 当前许可证为 MIT-CMU，且只用于品牌开发/CI，不进入产品运行时；历史 HPND 特例不再适用于当前锁定版本。MPL-2.0、LGPL-3.0、CC-BY-4.0、OFL-1.1、复合许可证和 `NOASSERTION` 元数据均保持人工/法律复核状态，没有作无依据的法律定论。

## 高风险执行与分发链

- Native/FFI：historical macOS `.a`、fingerprinted CoreSDK XCFramework、缺失的 Windows DLL 与 Linux SO。CoreSDK 内部逐文件 hash 已修复，但真实跨平台制品仍阻断。
- 构建期任意代码：Cargo `build.rs`、proc-macro、UniFFI bindgen、bundled SQLite/native compiler 链；均进入 ledger，依赖 checksum 完整，但 unmaintained/许可证闭包仍有 finding。
- CI Actions：`actions/checkout`、`actions/setup-python`、`actions/upload-artifact`、`actions/download-artifact`、`dtolnay/rust-toolchain`、`Swatinem/rust-cache`、`gitleaks/gitleaks-action` 共 7 个，全部固定完整 SHA；后两项许可证仍需专项确认。
- 下载器/系统工具：curl、unzip、shasum 只处理固定 URL/version/hash 的 Swift 工具与 artifact；没有 `curl | sh`。
- 外部 AI runtime：仅显式 debug fixture 可 opt-in；产品 debug/release 对未知 path/hash/provider/privacy manifest fail-closed，Core 不直接读取 Keychain 或自行发起网络。
- 发布：SBOM、NOTICE、source-offer 和 manifest 生成链本地存在，但签名、公证、staple、真实 package inspection 和法律 review gate 没有外部证据。

## 已排除候选

- “版本较旧”本身未记为漏洞；只有 anyhow 的已确认 advisory 与 bincode/paste 的 unmaintained 情报进入 finding，并按可达性和暴露范围降级处理。
- AreaMatrix 与本地 UniFFI 0.28.3 源码未发现 `anyhow::Error::downcast_mut`，因此 SC-020 不宣称已证实可利用路径。
- `r-efi` 的许可证表达式存在 MIT/Apache 允许选项且为 target-specific 路径，不作为 GPL 产品链接阻断；仍留在逐包人工复核闭包。
- Pillow 12.3.0 的官方精确版本公开 OSV 查询为 0 条，wheel hash 与仓库 requirement 一致；不把历史 Pillow 11.3.0 advisory 重复报告为当前漏洞。
- 所有 GitHub Action workflow 引用均为完整 commit SHA，未发现残留 branch/tag 浮动引用。
- 原型页面不再动态加载 Google Fonts，未发现远端 web-font 进入产品运行时。
- 没有证据表明 dev/test-only 依赖意外进入当前产品 package；真实 package inspection 尚未完成，因此不扩大结论。

## 外部证据与缺口

本地已确认：manifest/lock/source/usage/build/release 路径、Cargo/NuGet 锁定元数据、Action pin、下载 hash、生成绑定、CoreSDK 内部 integrity、fail-closed loader/runtime、静态验证和测试。

公开外部情报已确认：RustSec/OSV 精确版本结果、Pillow PyPI/OSV、7 个 Action commit/license、SwiftLint/SwiftFormat release digest、Inter immutable blob、NuGet registration metadata。公开结果只代表 2026-08-30 查询时点。

仍缺：

- 法律：Inter/OFL 派生、品牌 archive、Contributor Covenant/Mozilla、Cargo/NuGet 逐包闭包、gitleaks EULA、rust-cache LGPL。
- 平台：真实 Windows DLL/WinUI package、Linux SO/package、universal CoreSDK、iOS target、干净机安装、ABI/FFI smoke。
- 发布：Developer ID、notary、staple、签名、真实制品 SBOM/NOTICE/source-offer/package comparison。
- 远端治理：branch protection、required checks、environment reviewers、实际 workflow run、runner image/Xcode readback。
- Owner 决策：anyhow/bincode/paste 依赖变更或时限例外、`.NET global.json`、本地工具版本 gate。

## 验证结果

| 验证 | 结果 |
|---|---|
| `cargo metadata --locked --offline` | PASS |
| `cargo tree --locked --edges normal,build,dev` | PASS |
| `cargo fmt --all -- --check` | PASS |
| `cargo clippy --locked --all-targets --all-features -- -D warnings` | PASS |
| `cargo test --locked --all-features --workspace` | PASS |
| Python `test_*.py` 全量 | PASS，439 tests |
| `./dev bindings verify` | PASS |
| macOS modules `swift test` | PASS |
| iOS package host `swift build` | PASS，但不是 iOS target 证据 |
| governance/docs/wording/secrets/localization/skills/quality/prompts/diff/task-loop/codex-os checks | PASS |
| SwiftFormat lint / SwiftLint strict / `git diff --check` | PASS |
| `./dev workflow doctor` | FAIL，8 个 docs baseline 漂移，SC-031 |
| `./dev build core-sdk --verify-only` | FAIL，恢复 artifact fingerprint 过期 |
| Xcode universal/iOS target build | BLOCKED，缺 Rust targets/CoreSDK |
| Windows/Linux clean build/package | BLOCKED，当前 host 不具目标环境/制品 |
| `./dev release preflight --json` | BLOCKED，无 Developer ID/notary profile |
| 远端治理 readback | BLOCKED，未使用真实凭据 |

## 最终判定

覆盖清单和逐文件状态已经机器闭合，本地可实施的供应链修复也通过相应验证；但 19 条 finding 仍等待真实平台制品、远端配置、owner 依赖决策或合格法律/许可证 reviewer。AreaMatrix 当前不能被判定为“供应链审计完成”或“发布就绪”。

恢复条件是：`findings.jsonl` 中所有 `BLOCKED*` 项获得真实证据并转为 PASS/FIXED，36 个 `BLOCKED` 文件逐项重审，`./dev workflow doctor`、目标平台 clean build/package、release preflight、签名/公证和远端治理 readback 全部通过，同时重新生成并验证本目录台账守恒。
