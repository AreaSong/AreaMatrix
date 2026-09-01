# AreaMatrix 全仓依赖、许可证与供应链审计

> **结论：冻结快照的静态文件覆盖已守恒；当前工作树有 69 个范围内文件发生审计后漂移，整体审计与发布结论为 BLOCKED，不得宣称“当前全仓已审完”“无供应链问题”或“可发布”。**
> 未修改业务代码、manifest、lockfile、workflow、配置、依赖或发布状态；本目录仅保存审计证据。

## Findings（先列问题）

严重度计数：`P1=2`、`P2=14`、`P3=7`。

### SC-001 [P1] Rust MSRV 声明与锁定闭包不一致
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_with_registry_metadata`
- 位置：`core/Cargo.toml:5`; `core/Cargo.lock:1049-1050`; `core/Cargo.lock:1368-1369`; `README.md:50`; `README.zh-CN.md:50`
- 依赖/资产与路径：Cargo 依赖闭包（Cargo dependency closure）；cargo build/test/clippy 按 core/Cargo.lock 解析；文档与 manifest 宣称 Rust 1.75 可构建
- 暴露与完整性：开发者与 CI 构建；声明的受支持环境无法重现锁定闭包；lock checksum 存在，但锁定包最高 rust_version=1.88，高于声明 1.75
- 许可证/维护/执行风险：非主问题；许可证闭包在独立台账中记录；本地 metadata 快照确认；修复前仍需复核目标版本上游 metadata；导致构建失败或环境分叉，本身不构成任意代码执行
- 产品/Core/用户文件/发布范围：可阻断 Core/FFI 构建；无直接产品运行时路径
- 现有控制不足：三类控制对最低 Rust 版本给出互相不成立的契约
- 最小修复：提升并统一真实 MSRV，或约束/替换要求 1.88 的包后受审重建 lockfile
- 回滚：将 manifest、lockfile 与文档作为同一受审变更整体回滚
- 需要补证：cargo metadata --locked，并在声明 MSRV 与当前 toolchain 各做兼容构建验证

### SC-002 [P1] Windows native core 发布/加载链未闭环
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed`
- 位置：`apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:1-22`; `apps/windows/AreaMatrix/Core/NativeCoreLibrary.cs:242-260`
- 依赖/资产与路径：area_matrix_core.dll；Windows 应用 -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault/Load -> NativeLibrary.Load
- 暴露与完整性：Windows 运行时、Core/FFI 及经 bridge 到达的用户文件操作；无 project item、源码 revision、hash、签名、架构或 SBOM 证明加载的 DLL
- 许可证/维护/执行风险：实际加载 DLL 的许可证未知；仓库本地缺口；外部 DLL 来源不可得；不受控 DLL 加载会造成应用权限下代码执行与 ABI 替换风险
- 产品/Core/用户文件/发布范围：Windows 产品运行时及全部 bridged 文件路径
- 现有控制不足：文件存在与符号查找不能认证来源、版本或签名
- 最小修复：通过批准构建产生 RID/架构绑定的 fingerprint native asset，加载前验 hash/signature 并附 notices
- 回滚：禁用 Windows native launch，或恢复上一份已验证 artifact/loader manifest
- 需要补证：clean Windows build/publish、制品 hash/signature、ABI contract test 与 package inspection

### SC-003 [P2] Windows NuGet 传递闭包没有仓库内锁定
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_with_external_registry_gap`
- 位置：`apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:1-22`; `apps/windows/AreaMatrix/AreaMatrix.Windows.csproj:21`
- 依赖/资产与路径：Microsoft.WindowsAppSDK；Microsoft.WindowsAppSDK -> WinUI SDK/runtime assets -> Windows 构建/发布
- 暴露与完整性：Windows 构建与分发包；无 packages.lock.json、NuGet.config source mapping 或仓库内 package hash
- 许可证/维护/执行风险：Microsoft Software License Terms 与未闭合的传递包许可证；官方顶层包来源确认；registration/catalog 更深闭包查询不稳定；restore 时包替换、feed/cache 投毒与 RID asset 漂移风险
- 产品/Core/用户文件/发布范围：Windows 产品包与构建输出
- 现有控制不足：顶层精确版本不能锁定传递包、feed、RID 资产和 package hash
- 最小修复：提交 packages.lock.json 与 approved feed/source mapping，以 locked mode 验 hash/license/SBOM
- 回滚：回滚 lock/config 前仅保留开发引用，不把未锁定 restore 作为发布证据
- 需要补证：clean locked restore、完整 dependency graph/SBOM 与 package content hash 比对

### SC-004 [P2] macOS 用户文件删除路径间接按 PATH 执行 osascript
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_with_external_source_review`
- 位置：`core/src/storage/delete.rs:31`; `core/src/storage/replacement_trash.rs:105-118`; `core/Cargo.lock:1177-1180`; `core/Cargo.toml:33-34`
- 依赖/资产与路径：trash 5.2.5；delete_file -> send_to_system_trash -> trash::delete -> macOS 上游 Command::new("osascript")
- 暴露与完整性：macOS 产品运行时的用户文件删除/移入废纸篓路径；Cargo checksum 存在，但 osascript 由环境 PATH 解析
- 许可证/维护/执行风险：trash metadata 为 MIT；上游实现与系统工具条款需独立复核；本地调用链确认；外部 crate 源行为需按锁定版本复核；PATH 劫持可替换处理用户文件时执行的 osascript
- 产品/Core/用户文件/发布范围：Core 与 macOS bridge 的用户文件路径
- 现有控制不足：抽象层最终仍执行无绝对路径的外部命令
- 最小修复：改用可信平台 API/受控系统绝对路径并验证，或下沉到 Swift 平台服务
- 回滚：保留禁用破坏性操作的开关并恢复原 adapter，直到文件安全回归通过
- 需要补证：sandbox fixture 中 PATH substitution 测试与用户文件安全回归

### SC-005 [P2] CI 品牌图片解析器使用存在公开漏洞的 Pillow 11.3.0
- 置信度/状态：`MEDIUM` / `OPEN`；证据类别：`local_call_path_plus_external_advisory`
- 位置：`scripts/brand/requirements.txt:1`; `.github/workflows/governance-ci.yml:40-46`; `scripts/brand/validate_assets.py:90-106`
- 依赖/资产与路径：Pillow；PR checkout -> pip install -> validate_assets.py -> Image.open（仓库控制的二进制）
- 暴露与完整性：pull_request CI runner；未发现产品运行时路径；版本精确但无 artifact hash；11.3.0 命中 18 个唯一 GHSA，其中 PSD/FITS/McIdas Image.open 候选与未限制 formats 最接近
- 许可证/维护/执行风险：PyPI 为 MIT-CMU；仓库政策错误写为 HPND（SC-006）；PyPI 标记 Mature/not yanked；advisory 查询截至 2026-08-20；候选影响含 native memory corruption、信息泄漏与 DoS；并非 18 条均已证明本地可达
- 产品/Core/用户文件/发布范围：仅 CI/品牌开发工具，不进入 app/Core/FFI
- 现有控制不足：Image.open 未限制 formats，固定扩展名不约束文件 magic；版本仍有公开修复版本
- 最小修复：在独立变更中升级到覆盖相关修复的受审版本、pin hashes/index，并显式限制允许格式/magic/资源上限
- 回滚：回滚品牌依赖更新或临时禁用 PR 图片解析步骤，不影响产品运行时
- 需要补证：去重 GHSA 复核、恶意 PSD/FITS/McIdas fixture、资源上限与 clean CI 重放

### SC-006 [P2] Pillow 许可证政策口径和完整性锁定不一致
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_with_external_registry_and_legal_gap`
- 位置：`docs/development/dependency-policy.md:61`; `docs/development/dependency-policy.md:66`; `scripts/brand/requirements.txt:1`; `.github/workflows/governance-ci.yml:40-46`
- 依赖/资产与路径：Pillow；policy -> requirements exact version -> pip resolver -> CI/品牌工具
- 暴露与完整性：开发与 CI；不进入产品运行时；只 pin 版本，不 pin index/artifact hash；查询到的 sdist hash 未入库
- 许可证/维护/执行风险：PyPI/upstream 为 MIT-CMU，仓库政策声称 HPND；需合格许可证 reviewer 确认兼容与归属；来源官方且未 yanked；政策证据已漂移；pip 安装执行第三方 package build/install 逻辑；当前通常消费 wheel，但未锁 artifact
- 产品/Core/用户文件/发布范围：品牌工具与 CI，不进入 app/Core/FFI
- 现有控制不足：版本 pin 不能修复许可证错误，也不能证明实际下载 artifact
- 最小修复：复核并修正文档许可证，采用 hash-locked requirements/受控 index，归档 attribution/license evidence
- 回滚：移除品牌自动化依赖与对应 CI step；产品运行时不受影响
- 需要补证：PyPI/upstream license readback、选定 wheel/sdist hash 与合格 reviewer 签核

### SC-007 [P2] UniFFI runtime 依赖错误启用 build feature
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed`
- 位置：`core/Cargo.toml:17`; `core/Cargo.toml:36-37`; `core/build.rs:1-15`
- 依赖/资产与路径：uniffi 0.28.3 与 bindgen 构建工具链；runtime dependency uniffi(build feature) + build-dependency uniffi(build feature) -> proc-macro/build/bindgen 闭包
- 暴露与完整性：所有 Core 构建与 FFI 生成；Cargo.lock/checksum 固定，但 runtime edge 不必要地启用 build feature
- 许可证/维护/执行风险：UniFFI 家族含 MPL-2.0，需人工确认链接/修改/分发义务；锁定 0.28 系列；未声称上游已停止维护；扩大 proc-macro/build dependency 与构建期执行面
- 产品/Core/用户文件/发布范围：Core/FFI build closure，并可能扩大最终 feature graph
- 现有控制不足：同一 build feature 同时出现在运行时与 build dependency，职责未最小化
- 最小修复：在独立变更中验证后从 runtime uniffi 移除 build feature，仅保留实际所需 feature
- 回滚：若 bindings/scaffolding 回归，恢复 feature 并记录理由
- 需要补证：cargo tree -e features、locked clean build、bindings drift 与全平台 FFI tests

### SC-008 [P2] UniFFI fallback 从任意 Cargo cache/环境可执行文件取工具，来源闭环不足
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed`
- 位置：`scripts/dev_tools/build.py:77-88`; `scripts/dev_tools/build.py:220-279`; `scripts/dev_tools/build.py:246-270`
- 依赖/资产与路径：uniffi-bindgen fallback；UNIFFI_BINDGEN/AREAMATRIX_UNIFFI_BINDGEN override 或 Cargo cache source -> 临时 wrapper cargo build -> 生成 bindings
- 暴露与完整性：开发/CI 构建期代码生成；版本从 lock 读取，但 cache path/环境 executable 未自行校验 crate checksum/hash/signature
- 许可证/维护/执行风险：UniFFI MPL-2.0 family；环境 override executable 许可证未知；fallback 有 locked fetch/offline build；实际 cache/override owner 未登记；构建期执行可替换 generator，可污染 Swift/C headers 与 native artifact
- 产品/Core/用户文件/发布范围：Core/FFI 生成物和下游 Apple 包
- 现有控制不足：控制锁版本但没有认证 cache source tree 或 override executable 身份
- 最小修复：绑定允许的 generator provenance/hash/version，校验 cache checksum，限制或移除任意 override
- 回滚：禁用 override/fallback，恢复已验证生成物并要求受控 clean generation
- 需要补证：篡改 cache/override 负测、bindings deterministic diff 与 clean isolated rebuild

### SC-009 [P2] CI/构建关键 Cargo 命令普遍缺少 --locked
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed`
- 位置：`.github/workflows/core-ci.yml:38`; `.github/workflows/core-ci.yml:53`; `.github/workflows/core-ci.yml:66`; `.github/workflows/core-ci.yml:100`; `scripts/dev_tools/core_sdk.py:115`; `scripts/dev_tools/build.py:313,755`
- 依赖/资产与路径：Cargo 解析器与构建脚本；CI 与 CoreSDK/build helpers 直接调用 cargo fmt/clippy/test/build/llvm-cov，未统一传 --locked
- 暴露与完整性：CI、开发构建、CoreSDK artifact 与 FFI；Cargo.lock 已提交，但部分命令允许 resolver 在 lock 不适用/漂移时改写或继续
- 许可证/维护/执行风险：Cargo 闭包许可证另表；主问题为解析可复现性；本地命令链确认；意外解析不同 build.rs/proc-macro/native crate 会扩大构建期执行风险
- 产品/Core/用户文件/发布范围：Core/FFI 与 Apple artifact
- 现有控制不足：存在 lockfile 不等于每个生产/CI 入口都 fail closed 使用它
- 最小修复：为解析/构建/test/coverage 入口统一 --locked，并在 helper tests 断言
- 回滚：恢复命令参数；保留当前 Cargo.lock 与可重放基线
- 需要补证：故意漂移 manifest/lock 的 fail-closed 测试与 clean cache build

### SC-010 [P2] tracked UniFFI 静态库缺少来源、SBOM、签名和许可证闭包
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed`
- 位置：`apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a（SHA-256 69ef0816...1db44）`; `apps/macos/XcodeGen/project.yml:1`
- 依赖/资产与路径：libarea_matrix_core.a；XcodeGen generated project link reference；canonical AreaMatrix.xcodeproj 当前改用 CoreSDK XCFramework
- 暴露与完整性：tracked 94 MB universal archive；潜在 legacy/generated project 链接输入；本地 hash/architecture/symbol 可确认，source commit、build manifest、签名与复现命令未绑定
- 许可证/维护/执行风险：项目与 Cargo 对象混合；无 archive-specific notices/SBOM；仓库内静态制品；canonical 与 XcodeGen 路径并存；链接未验证对象会把任意 native code 带入 app
- 产品/Core/用户文件/发布范围：若走 XcodeGen 路径会进入 macOS Core/FFI 产品
- 现有控制不足：另一路 tracked archive 未继承 CoreSDK provenance/notices/signature
- 最小修复：删除/替换需另行确认；最小治理是为 archive 建 source commit、deterministic command、SBOM、notices、hash/signature 并统一 canonical path
- 回滚：恢复该 frozen hash，或回退到已验证 CoreSDK reference
- 需要补证：clean rebuild byte/symbol diff、XcodeGen/canonical project package inspection 与许可证 readback

### SC-011 [P2] Inter 字体生成的 wordmark 缺少来源、版本、许可证和输入 hash
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_with_legal_gap`
- 位置：`assets/brand/wordmark-outlines.json:5`; `assets/brand/wordmark-outlines.json:9`; `assets/brand/README.md:74`; `docs/ux/brand-assets.md:27,101`
- 依赖/资产与路径：Inter-Bold 字体输入与派生轮廓品牌资产；Inter-Bold 字体 -> generate_wordmark_outlines.swift -> wordmark-outlines.json -> build_source_assets.py -> final SVG/PNG/PDF/TIFF/runtime 副本
- 暴露与完整性：品牌、文档、印刷、社交与应用内 runtime copies；outline JSON 与派生文件有 hash，但字体输入与首次生成记录缺失
- 许可证/维护/执行风险：仓库未记录 Inter 输入字体版本、来源或许可证；需合格许可证 reviewer 确认；派生几何已固化；上游字体身份不可追溯；不是任意代码执行；风险为未经验证的第三方字体分发义务
- 产品/Core/用户文件/发布范围：55 个识别出的字标/lockup/stacked/social/print/runtime artifact 可能进入产品/文档/发布
- 现有控制不足：轮廓化和 hash 不能证明最初字体文件的授权与来源
- 最小修复：记录字体 source/version/license text/input hash、生成命令与修改/归属声明，并保留必要 notices
- 回滚：用可验证的自有/vector 字标替换，或移除受影响副本
- 需要补证：许可证复核、字体 archive/hash 与全量 regeneration diff

### SC-012 [P2] CI Action、Rust channel 与 Homebrew 工具链使用可移动/未锁定引用
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_with_external_ref_query`
- 位置：`.github/workflows/core-ci.yml:35,47,62,75,90,97`; `.github/workflows/macos-ci.yml:42,88,345,374-391`; `.github/workflows/governance-ci.yml:24,64`
- 依赖/资产与路径：GitHub Actions 与 runner 工具；所有 CI checkout/cache/build/test/security/format/artifact jobs
- 暴露与完整性：PR/main CI runner 与发布证据输入；workflow 使用 major tag/stable/brew latest；查询日 commit 只是一时解析，不是 pin
- 许可证/维护/执行风险：各 Action/工具许可证未形成仓库内 notices/审阅清单；外部 refs 需持续监控；dtolnay stable 未能按固定 tag 解析；上游 ref/formula 变化会在 CI 权限下执行代码或改变 artifact
- 产品/Core/用户文件/发布范围：构建产物、测试结论、缓存与 release evidence；非产品运行时依赖
- 现有控制不足：major/channel/formula 引用仍可移动，且工具版本/hash 未绑定
- 最小修复：按审阅 commit/version pin Action/工具，建立受控升级与 provenance/hash 记录
- 回滚：回退至上一已审 commit；provenance 失败时停用相关 job/artifact
- 需要补证：commit pin review、Action provenance/SLSA 证据与 clean runner replay

### SC-013 [P2] Governance PR job 给 checkout 脚本环境 security-events:write 并传入 token
- 置信度/状态：`MEDIUM` / `OPEN`；证据类别：`local_confirmed_with_remote_governance_gap`
- 位置：`.github/workflows/governance-ci.yml:20-24`; `.github/workflows/governance-ci.yml:63-66`
- 依赖/资产与路径：gitleaks action 与 PR checkout；pull_request -> checkout PR tree -> 多个本地脚本 -> gitleaks action(GITHUB_TOKEN)
- 暴露与完整性：fork 与同仓 PR；token 降权取决于远端 event/settings；action 使用可移动 v2；远端权限行为未由本地证明
- 许可证/维护/执行风险：gitleaks action 上游许可证未随仓库归档；公开 action；远端 settings/run evidence 缺失；job 级 security-events:write 加显式 token 会放大 workflow/action compromise
- 产品/Core/用户文件/发布范围：仅 CI，但影响合并门禁与安全报告
- 现有控制不足：本地 YAML 无法证明 fork/同仓 PR 权限矩阵，且第三方 action 接收 token
- 最小修复：最小权限隔离 secret scan，验证 fork/同仓 token 行为并固定 action commit
- 回滚：撤回权限变更或暂时禁用上传/reporting path
- 需要补证：fork PR run audit、权限矩阵、action source/provenance 与远端 settings readback

### SC-014 [P2] 缺少发布用 SBOM、THIRD_PARTY_NOTICES 与第三方归属闭包
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_with_legal_and_release_gap`
- 位置：`core/Cargo.lock:1-1830`; `docs/development/dependency-policy.md:53-81`; `docs/development/release.md:178-189`
- 依赖/资产与路径：Cargo/UniFFI/Microsoft/Pillow/native 与品牌依赖闭包；Cargo/UniFFI/Microsoft/Pillow/native/brand 闭包 -> Core/FFI -> Apple/Windows 制品 -> 发布包
- 暴露与完整性：发布分发与许可证合规；存在 Cargo checksum/部分 artifact hash，但无逐发布 SBOM/notices/source-offer manifest 绑定最终包
- 许可证/维护/执行风险：含 MPL-2.0、LGPL option、双许可证、Microsoft/字体未知项；需合格 reviewer；本地仓库缺口；最终包尚未提供可读闭包；本身不是代码执行漏洞，但会掩盖未审组件与分发义务
- 产品/Core/用户文件/发布范围：所有发布包与 FFI 制品
- 现有控制不足：政策/checklist 不是 artifact-specific SBOM、notice、源码提供或归属证据
- 最小修复：每次发布生成/归档 SBOM、THIRD_PARTY_NOTICES、source-offer、artifact manifest，并由合格 reviewer readback
- 回滚：暂停分发或移除义务未闭合组件
- 需要补证：最终包内容与 license matrix 双向比对、法律签核与 clean package inspection

### SC-015 [P2] Linux native core 代码存在但产品/发布声明与校验链缺失
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_readiness_gap`
- 位置：`apps/linux/AreaMatrix/AreaMatrix.Linux.csproj:1-20`; `apps/linux/AreaMatrix/Core/NativeCoreLibrary.cs:224-242`; `docs/product/current-implementation-inventory.md:616-618`
- 依赖/资产与路径：area_matrix_core.so；LinuxDesktopShell -> AreaMatrixNativeCoreClient -> NativeCoreLibrary.LoadDefault
- 暴露与完整性：当前 headless/UI contract fixture；若启用则为 Linux 运行时；无 Linux package/publish asset、RID、hash/signature 或系统依赖声明
- 许可证/维护/执行风险：实际 .so、GTK/desktop system packages 的许可证未知；文档明确当前不是可启动 GTK 产品；启动时系统库搜索路径可加载不受控 native library
- 产品/Core/用户文件/发布范围：当前未证明进入发布；启用后会影响 Core/FFI/用户文件路径
- 现有控制不足：测试检查源码/符号，不证明已签名可分发 .so 或系统包闭包
- 最小修复：正式保持 fixture-only 并阻止 launch，或补完整 RID/package/native provenance 与 Linux system dependency manifest
- 回滚：保持 Linux feature disabled，移除运行入口直到闭环
- 需要补证：clean Linux build/package、loader hardening、GTK/system package 与 artifact/license manifest

### SC-021 [P2] AI 外部 runtime 可执行程序没有供应链身份绑定
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_external_capability_gap`
- 位置：`core/src/ai_classification_suggestion/executor.rs:16-17,77-100`; `core/src/ai_tags_suggestion/executor.rs:14-15,78-105`; `core/src/ai_summary/executor.rs:14-15,67-94`; `core/src/semantic_search/executor.rs:12,88-113`; `core/src/external_runtime.rs:50-106`
- 依赖/资产与路径：AREAMATRIX_*_RUNTIME 可执行程序族；AI classification/tags/summary/semantic executor -> Command::new(runtime_path) -> external_runtime::run -> stdin 传入序列化内容
- 暴露与完整性：可选本地/远程 AI 路径；可能处理用户内容与 provider 配置；未绑定名称、版本、来源、hash、签名、SBOM 或允许清单
- 许可证/维护/执行风险：未知；仓库未登记实现供应商或分发条款；仅有协议与安全执行器；实际 runtime 实现不在仓库；启用该能力即执行环境指定程序；来源错误会在应用权限下运行代码并读取 stdin payload
- 产品/Core/用户文件/发布范围：Core AI/远程数据边界；当前平台装配未证明正式发布包已提供该 runtime
- 现有控制不足：这些控制限制子进程行为，但不认证 executable 身份、许可证或更新来源
- 最小修复：为每个允许 runtime 建立受审版本/来源/hash/signature/许可证清单和平台装配边界，默认 fail closed
- 回滚：保持环境变量未设置并禁用对应 AI route；撤回未验证 runtime bundle
- 需要补证：签名/hash 替换测试、payload 最小化/隐私验证、clean package inspection 与外部能力准入复核

### SC-016 [P3] 原型页面动态加载 Google Fonts，来源与离线/许可边界未记录
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed_low_scope`
- 位置：`assets/prototypes/landing/index.html:8`; `assets/prototypes/workspace/index.html:7`
- 依赖/资产与路径：Google Fonts Inter CSS；prototype HTML 在浏览器加载 -> fonts.googleapis.com CSS/字体
- 暴露与完整性：仅 prototype/demo，不进入产品运行时；网络响应浮动且离线不可复现
- 许可证/维护/执行风险：仓库未记录 font/provider 条款；外部服务；有限原型网络边界；未观察到 CI 执行
- 产品/Core/用户文件/发布范围：仅 prototype
- 现有控制不足：未记录来源/许可证，也无本地可复现 fallback
- 最小修复：登记 provider/license，并使用本地已验证字体或明确 prototype-only exception
- 回滚：移除外部 link，改用系统字体栈
- 需要补证：资产 owner 确认与离线渲染检查

### SC-017 [P3] 开发文档保留 curl | sh 与浮动 stable 工具安装示例
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_confirmed`
- 位置：`docs/development/setup.md:51`
- 依赖/资产与路径：rustup 安装脚本与 Rust stable channel；开发者按 setup 文档从网络取得 rustup shell script 并立即执行
- 暴露与完整性：开发工作站/bootstrap；curl|sh 与 stable channel 均可变
- 许可证/维护/执行风险：installer/tool 许可证未随仓库固定；外部 installer/service；在仓库控制生效前直接执行网络响应
- 产品/Core/用户文件/发布范围：间接影响构建环境，不是产品运行时
- 现有控制不足：installer 在任何仓库 hash/signature 控制之前执行
- 最小修复：提供已验证 checksum/signature 或受控 package-manager 路径，并固定 toolchain
- 回滚：移除 pipe-to-shell 示例，保留人工校验安装说明
- 需要补证：不执行远端脚本的 fresh-machine bootstrap 复核

### SC-018 [P3] tracing-appender 直接声明但未发现 Core 源码使用
- 置信度/状态：`MEDIUM` / `OPEN`；证据类别：`local_confirmed_low_confidence`
- 位置：`core/Cargo.toml:31`; `core/Cargo.lock:1114-1120`
- 依赖/资产与路径：tracing-appender；manifest/lock 声明；扫描 build.rs 与全部 core/**/*.rs 未发现 tracing_appender token
- 暴露与完整性：所有 Core resolve/build，经 time/crossbeam/parking_lot 扩大闭包；checksum 固定，但无效依赖扩大 closure 与 MSRV 压力
- 许可证/维护/执行风险：MIT；本地未使用证据确认；外部维护状态未作结论；增加 resolve/build surface，未观察到功能价值
- 产品/Core/用户文件/发布范围：间接 build/runtime 闭包；无直接调用路径
- 现有控制不足：政策/CI 没有 unused dependency gate
- 最小修复：删除或用精确使用位置与 feature scope 证明必要性
- 回滚：若日志实现恢复则还原依赖
- 需要补证：cargo tree/source search 与移除后的行为/构建测试

### SC-019 [P3] Cargo 闭包包含停止维护或 deprecated 组件，需维护者处置
- 置信度/状态：`MEDIUM` / `OPEN`；证据类别：`external_advisory_with_local_reachability_gap`
- 位置：`core/Cargo.lock:122-129`; `core/Cargo.lock:643-649`; `core/Cargo.lock:881-890`
- 依赖/资产与路径：bincode, paste, serde_yaml；Cargo metadata 显示经 UniFFI/build 或 Core serialization edge 可达
- 暴露与完整性：依 target/feature 的 build/runtime 闭包；各包 checksum 已记录
- 许可证/维护/执行风险：MIT 或 MIT/Apache metadata；本 finding 不主张许可证违规；外部 advisory/deprecated metadata；不是本地漏洞证明；维护停止导致未来补丁/兼容性风险
- 产品/Core/用户文件/发布范围：可能为传递闭包；精确 runtime reachability 仍需 owner 确认
- 现有控制不足：无 replacement/accepted-exception 依据
- 最小修复：映射真实可达性，低风险替换或记录有期限维护例外
- 回滚：兼容验证前保留锁定版本
- 需要补证：cargo tree -i、target/feature 源码复核；不得把版本年龄直接当漏洞

### SC-020 [P3] anyhow RustSec 命中但本地触发路径未确认
- 置信度/状态：`LOW` / `BLOCKED`；证据类别：`external_advisory_blocked_local_validation`
- 位置：`core/Cargo.lock:36-40`
- 依赖/资产与路径：anyhow；Cargo metadata 显示在 UniFFI/build 传递图；已审本地源码未发现 downcast_mut 调用
- 暴露与完整性：除非后续证明 runtime path，否则暂按构建工具链；Cargo checksum 已记录
- 许可证/维护/执行风险：MIT OR Apache-2.0（双许可证需人工确认）；外部 advisory 截至查询日；数据库新鲜度与完整适用性需复查；unsoundness advisory；未确认本地 exploit path
- 产品/Core/用户文件/发布范围：尚未建立
- 现有控制不足：静态审阅不能证明全部传递 macro/build 调用路径
- 最小修复：独立验证 reachability；适用则升级，否则登记可审计 exception
- 回滚：兼容/reachability 证据形成前保留当前 lock
- 需要补证：独立 RustSec/OSV 复核与 cargo tree/source call-path 证明

### SC-022 [P3] 16 个品牌历史探索稿缺少逐项来源与授权记录
- 置信度/状态：`HIGH` / `OPEN`；证据类别：`local_per_asset_hash_with_provenance_gap`
- 位置：`assets/brand/README.md:23,80`; `assets/brand/archive/early-drafts/areamatrix-app-icon.png`; `assets/brand/archive/early-drafts/areamatrix-app-icon.svg`; `assets/brand/archive/early-drafts/areamatrix-logo-lockup.png`; `assets/brand/archive/early-drafts/areamatrix-logo-lockup.svg`; `assets/brand/archive/early-drafts/areamatrix-logo-mark.png`; `assets/brand/archive/early-drafts/areamatrix-logo-mark.svg`; `assets/brand/archive/v2/areamatrix-v2-app-icon.png`; `assets/brand/archive/v2/areamatrix-v2-app-icon.svg`; `assets/brand/archive/v2/areamatrix-v2-distinctive-concepts.png`; `assets/brand/archive/v2/areamatrix-v2-distinctive-concepts.svg`; `assets/brand/archive/v2/areamatrix-v2-logo-lockup.png`; `assets/brand/archive/v2/areamatrix-v2-logo-lockup.svg`; `assets/brand/archive/v3/areamatrix-v3-logo-directions.png`; `assets/brand/archive/v3/areamatrix-v3-logo-directions.svg`; `assets/brand/archive/v4/areamatrix-v4-reference-inspired-directions.png`; `assets/brand/archive/v4/areamatrix-v4-reference-inspired-directions.svg`
- 依赖/资产与路径：assets/brand/archive/** PNG/SVG 历史资产；archive 仅保存于源码仓库；未发现 README/UI/CI/发布 manifest 的正式引用
- 暴露与完整性：源码分发与设计回溯；当前未进入产品运行时/发布资源路径；逐文件 SHA-256、MIME 与 SVG 结构已确认，但创作者、原始输入、参考素材授权和生成命令未登记
- 许可证/维护/执行风险：未知；静态历史资产，无上游更新身份；不执行代码；风险集中在来源、参考素材和再分发授权
- 产品/Core/用户文件/发布范围：不应进入产品包；仍随源码仓库分发
- 现有控制不足：禁止产品引用不能补足源码分发时的来源与许可证证据
- 最小修复：由资产 owner 为每个历史家族记录创作者、来源/参考、授权、生成链和保留理由；无法追溯者移出可分发仓库需另行确认
- 回滚：不修改现有资产；后续治理变更可恢复至本次冻结 hash 清单
- 需要补证：资产 owner 与合格许可证 reviewer 逐项签核；确认 release/source archive 包内容

### SC-023 [P3] 行为准则记录了改编来源，但未记录上游许可证条款与固定版本证据
- 置信度/状态：`MEDIUM` / `OPEN`；证据类别：`local_attribution_with_external_license_gap`
- 位置：`CODE_OF_CONDUCT.md:1`; `CODE_OF_CONDUCT.md:75-83`
- 依赖/资产与路径：Contributor Covenant 2.1 与 Mozilla 社区影响执行阶梯；上游治理文本 -> 中文改编 CODE_OF_CONDUCT.md -> 随源码仓库分发
- 暴露与完整性：文档与源码分发；不进入产品运行时；来源 URL 与版本部分存在，但无 upstream revision/hash 或保存的 license evidence
- 许可证/维护/执行风险：仓库未记录具体许可证表达式/许可证链接；需外部与法律复核；公开上游；本轮未对上游当前许可证作法律定论；无代码执行风险；存在 attribution/修改声明/许可条款证据不完整风险
- 产品/Core/用户文件/发布范围：源码仓库与文档分发
- 现有控制不足：来源声明本身不能证明当前 attribution、license link、修改声明与再分发义务全部满足
- 最小修复：固定上游版本/revision，记录适用许可证、归属与修改声明；由合格许可证 reviewer 确认文本
- 回滚：恢复至本次 CODE_OF_CONDUCT.md hash 并保留现有来源声明
- 需要补证：上游许可证原文/版本 hash、attribution 清单与法律/许可证复核


## 覆盖与守恒

- 冻结 commit：`cf3647378d64885e8e6a44a2a5b60d8926668982`；范围文件：`5053`（文本 4,891、二进制 152、符号链接 10；文本约 1,498,027 行）。
- 本次覆盖：`PASS=4845`、`FINDING=114`、`NOT_APPLICABLE=25`、`BLOCKED=69`、`PENDING=0`、`IN_PROGRESS=0`。
- 守恒式：`5053 = 4845 + 114 + 25 + 69`；`PENDING/IN_PROGRESS=0`。
- 逐文件证据：本次 inventory 的每个 SHA-256 与 `.codex/runtime/full-repo-audit-20260819/final-status.tsv` 逐项相同；历史证据来自同一 commit 的逐文件逐行阅读。本次重新按依赖/许可证/供应链语义复核，不把历史 PASS 当作自动合规结论。
- 最终复算：冻结范围中 `4984` 个文件仍与 inventory 同字节，`69` 个已变化并逐项标为 `BLOCKED`；审计启动后新增的非 runtime 文件 `6` 个，另有 `85` 个 `.codex/runtime/` 并行审计证据文件不递归纳入本范围。
- 未纳入冻结范围的新增非 runtime 文件：`apps/ios/AreaMatrix/Features/Import/ShareImportExtensionLifecycle.swift`、`apps/ios/AreaMatrix/Features/Import/ShareImportRepositoryAccess.swift`、`apps/ios/AreaMatrixTests/ShareImportModelTestSupport.swift`、`apps/windows/AreaMatrix/Features/Library/WindowsMainWindowViewModel.RepositoryLoad.cs`、`apps/windows/AreaMatrix/MainWindow.RouteTransitions.cs`、`core/src/icloud_conflicts/token.rs`；这些文件未被本次逐行证据覆盖，不能纳入当前全仓完成声明。
- 注意：以上漂移与新增文件数字是生成时的点时快照；并行工作树若继续变化，必须重新冻结范围和哈希，不能沿用本报告数字作当前状态证明。
- 交付前独立只读复算（2026-08-19T22:14:09Z）已观察到漂移增至至少 `72` 个；这验证了工作树仍在变化，不能把上面的生成时计数解释为当前状态。
- `25` 个确定性/不可逐字阅读的资源保留 `NOT_APPLICABLE` 并逐项记录来源/哈希/生成或副本理由；tracked 静态库已转为 `FINDING`，没有批量排除二进制目录。

## 依赖台账

- 总记录：`305`，其中 Cargo `198`、非 Cargo `107`；`dependency-ledger.jsonl` 保留每项版本/范围、来源、用途、调用位置、许可证、锁定、校验、风险与复核状态。
- Cargo：项目根 `1`、direct `18`、transitive `179`；197 个 registry crates.io 包和 1 个 path root；Cargo.lock v4，registry 包均有 checksum。
- NuGet：`11` 条记录，含 1 个顶层包、9 个父 nuspec 已知子包和 1 个“更深闭包未解析”哨兵；缺 `packages.lock.json`，不得把这些记录误作完整 NuGet 闭包。
- 隐式工具：`61` 条逐工具记录；Pillow、CoreSDK/XCFramework、tracked native archive、GitHub Actions、Rust/Swift/Xcode/.NET 工具链、系统命令和 prototype Google Fonts 也均进入台账。
- 未声明/隐式依赖重点：Windows native DLL 搜索路径、Linux `.so` 搜索路径、Homebrew latest、Rust stable、未固定 cargo-llvm-cov、macOS `osascript`、字体输入文件、网络字体和外部 action tags。

## 许可证矩阵

- 记录总数：`528`，其中逐项资产/制品对象 `221`；分类统计：`{'BLOCKED_PENDING_NOTICES': 3, 'BLOCKED_PENDING_PROVENANCE_AND_NOTICES': 2, 'DEFAULT_ALLOWED': 32, 'EVIDENCE_INSUFFICIENT': 82, 'EVIDENCE_MISSING': 1, 'MANUAL_REVIEW_REQUIRED': 250, 'PROJECT_LICENSE': 158}`。
- 默认允许范围按仓库政策执行：MIT、Apache-2.0、BSD-2-Clause、BSD-3-Clause、ISC、Unicode-DFS-2016。
- 需要人工确认：9 个 MPL-2.0 UniFFI 包、含 LGPL 选项的表达式、Zlib/Unlicense/BSL/LLVM exception 组合、Microsoft license.txt、Pillow MIT-CMU 与 HPND 政策冲突、Inter 字体、第三方 Action/工具许可证。
- 默认阻断候选：直接 GPL/AGPL 产品链接、未知来源/未知许可证资产；本轮未把未经证实的 GPL 代码断言为已存在，但发布链因 notices/SBOM/法律复核缺口保持 BLOCKED。

## 高风险构建/分发链

1. `core/build.rs` + UniFFI proc-macro/build feature + fallback bindgen。
2. Windows/Linux native loader 与未验证 DLL/SO。
3. macOS CoreSDK/XCFramework 与 tracked static archive 的替代路径。
4. CI 可移动 Action/tag、stable channel、Homebrew latest、Pillow parser 和 gitleaks token 权限。
5. brand font -> outlined JSON/SVG/PNG/print/runtime copies 的输入许可证缺口。
6. 缺失 SBOM、THIRD_PARTY_NOTICES、source-offer 和 per-artifact license manifest。

## 已排除/校准候选

- 官方 `actions/*@v4` major tag 本身没有被单独定性为漏洞；问题是可移动引用和缺少 commit pin。
- Apple CoreSDK 是有意的源码生成/CI artifact 链；风险限定为工具链未固定、签名/SBOM/notices 缺口，不称其为未知下载。
- tracked DMG 有生成命令、SHA-256 和 prerelease/internal 限制；本地确认未签名/stapled 与文档一致，不报告为来源未知。
- Linux 目前是 headless/UI contract fixture，没有证据证明已形成携带错误库的发布包；SC-015 是 readiness/provenance finding。
- bundled SQLite 有 Cargo checksum；未发现 extension loading API 或用户可控 SQL 注入；SQLite upstream advisory 仅记录为外部情报缺口。
- 10 个 `.agents/skills/*` 符号链接均指向仓库内 `.codex/skills-src/*`，未发现 tracked MCP/plugin/automation 绕过准入门禁。

## 证据缺口与验证边界

- 外部漏洞库/registry：Pillow 和 RustSec/OSV 结果是查询日公开证据；全量 advisories、NuGet registration catalog、Action tag 历史不可变性仍需独立复核，不能推断“无漏洞”。
- 法律：MPL/LGPL/双许可证、Pillow MIT-CMU vs HPND、Inter 字体、Microsoft license 和发布源码提供义务需合格 license reviewer 确认。
- 远端治理：GitHub fork PR token 降权、分支保护、Action allowlist、artifact retention/signature 未由本地源码证明。
- 动态验证：本轮没有运行测试、构建、restore、安装、更新、未知脚本或真实凭据；需要在隔离环境完成 clean locked build、native artifact/signature、SBOM/package inspection 和 hostile image tests。

## 台账文件

- `scope.json`：冻结范围、工作树既有改动和守恒规则。
- `inventory.jsonl`：5,053 个文件及类型/哈希。
- `coverage.jsonl`：逐文件状态与证据。
- `dependency-ledger.jsonl`：`305` 条依赖记录，含 198 个 Cargo 包和 `107` 条非 Cargo/隐式依赖。
- `license-ledger.jsonl`：`528` 条逐依赖/资产许可证策略和待复核义务，其中 `221` 个逐项资产/制品对象。
- `findings.jsonl`：结构化 finding、证据类别、最小修复、回滚和验证要求。
- `review-notes.md`：过程、子代理边界、外部查询和未决项。
