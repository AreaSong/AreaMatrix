# CI Governance

> AreaMatrix 的持续集成治理：所有 PR 都要跑核心、macOS、prompt、skill 和治理门禁。
>
> 阅读时长：约 4 分钟。

---

## 目标

CI 是合并前的最低共同质量线。它不能替代 review，但可以阻止明显不完整、不可复现或不可追溯的改动进入主线。

企业治理检查同时验证 `ASW-EWF-001@1.0.0` 的 AreaMatrix 适配基线、G0-G8、L0-L4、治理登记册和 authoring-only 权限边界。CI 不能把外部签名、公证、独立复核、测试参与者或 AreaFlow execution 标记为完成。

## 必跑矩阵

| Workflow | 目的 | 触发 |
|---|---|---|
| `core-ci.yml` | Rust fmt、clippy、test、universal build、coverage | 所有 PR、main push |
| `macos-ci.yml` | CoreSDK artifact、tracked Swift bindings drift、Xcode build/test、Swift Watcher / Bridge coverage、SwiftLint、SwiftFormat | 所有 PR、main push |
| `governance-ci.yml` | governance files、文档链接与导航、skills、quality smoke、品牌资产、Codex OS、wording audit、task-loop、prompt doctor、diff check、secret scan | 所有 PR、main push |

macOS app 与 `AreaMatrix.xcodeproj` 已是仓库必需组成部分。`macos-ci.yml` 必须先显式检查工程和源码目录；
任一目录缺失都应立即失败，不得通过条件表达式跳过 build/test、SwiftLint 或 SwiftFormat。
CoreSDK job 只构建一次 fingerprinted XCFramework，验证 tracked bindings 和生成的 Swift Package 后上传
artifact；Xcode build/test job 下载并恢复完整 `.build/core-sdk/` 缓存条目与 `current` 指针。这保证
macOS 验证消费的是已验证制品，而不是在 Xcode Pre-Test Build Gate 内再启动一次 Cargo。
恢复后运行 `./dev build core-sdk --verify-only`，解析 manifest 并验证 fingerprint、schema、symlink
边界，以及 macOS、iOS device、iOS simulator 三个 XCFramework slice 的 architecture 和实际文件。
Xcode build/test job 同样安装 Rust toolchain，使 `--verify-only` 能用当前源码、Rust 与 Xcode 版本重新计算
source/tool-bound fingerprint；下载到结构完整但来源不同的 artifact 必须失败，不能仅凭缓存目录存在通过。
`./dev build core-sdk` 输出 status、cache hit/miss、Cargo lane 和 wall-clock duration；`./dev test macos` 输出
持久/临时 DerivedData、结果与 wall-clock duration。GitHub Actions 保留这些标准化行和 job/step
耗时，用于识别缓存回退、重复 Cargo 构建和 XCTest 延迟。
`./dev check governance` 还会把磁盘上的 `*GovernanceTests.swift` 和
`MacOSGovernance*TestSupport.swift` 与 `AreaMatrixTests` target 的 Sources membership 双向核对，
防止治理测试只有文件引用、没有进入可执行 XCTest target 时被 CI 静默漏跑。
它还会核对 Core 与 macOS 之间的 `AREAMATRIX_*_RUNTIME` key 合同，防止新增或改名 runtime 后只有一侧更新。
它同时检查 `docs/governance/` 的固定源事实、上游版本/hash、owner、复审字段、RAID、G0-G8、PR 模板字段，以及 promotion apply / execution / runner 仍被 shim 阻断。

`./dev check docs` 除了相对链接和 README 导航可达性，还检查每篇 Markdown 的唯一一级标题、
H1 后紧跟的摘要引用、代码块语言与闭合、`## Related` 章节和文件末尾单个换行；阅读时长估算与
标题层级不在其检查范围内，靠评审把关。`./dev check governance` 对固定上游规范快照执行登记册 SHA-256
校验；`./dev check diff` 同时检查 unstaged、staged 和 merge-base 到 HEAD 的 committed diff，避免只检查
当前工作区而漏掉已提交空白错误。

## 本地等价检查

提交前至少运行与改动范围匹配的检查：

```bash
./dev check governance
./dev check docs
./dev check skills
./dev check quality
./dev check codex-os
./dev check wording
./dev check task-loop
./dev check prompts
./dev check diff
./dev check secrets          # 默认 diff 模式：未提交变更 + 领先 origin/main 的 commit
./dev build core-sdk
./dev bindings verify        # 只读比较当前 UDL 与 Xcode tracked Swift bindings
python3 -m venv .brand-venv
.brand-venv/bin/pip install --requirement scripts/brand/requirements.txt
.brand-venv/bin/python scripts/brand/validate_assets.py
```

发布状态、证据审计、签名、公证、DMG 和外部测试属于发布门禁，不是普通 PR 的 CI 结果。CI 不安装或替换 `/Applications/AreaMatrix.app`，也不能把只读产物探针当作分发证据；正式发布统一遵循 [发布流程](release.md)。

`./dev check codex-os` 会覆盖 Codex OS flow 编排入口的 CLI smoke，包括
`go`、`flow`、`start-flow`、`now`、`run-validation --profile auto/full`、`repair-plan`、
`done`、`close-flow --from-latest-validation`、`todo` 和 `ops-flow --compact / --action-items`，
并运行 `scripts.dev_tools.test_codex_os` 回归测试。

维护者全历史审计：

```bash
AREAMATRIX_GITLEAKS_MODE=history GITLEAKS_LOG_OPTS="--all" ./dev check secrets
```

Rust 改动：

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --all-targets --all-features -- -D warnings
cd core && cargo test --workspace
```

Swift 改动：

```bash
./dev test macos
cd apps/macos && swiftlint lint --strict --config ../../scripts/dev_tools/swiftlint.yml --force-exclude . --no-cache
cd apps/macos && swiftformat --lint . --config ../../scripts/dev_tools/swiftformat.conf --exclude AreaMatrix/Bridge/Generated,AreaMatrix/Bridge/UniFFI,DerivedData --cache ignore
```

`./dev test macos` 会优先执行标准 `xcodebuild test`。只有本地沙箱阻断
`testmanagerd` 通信时，才改用 `xcrun xctest` 执行已构建的 XCTest bundle；CI
仍以 `.github/workflows/macos-ci.yml` 中的同一 Python 入口为远端门禁。

`AreaMatrixPerfTests` 是独立 performance gate，默认不参加普通 PR 全量
`./dev test macos`，避免共享 GitHub macOS runner 的 wall-clock / resident memory
抖动阻断功能 CI。需要验证性能基线时显式运行：

```bash
./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests
```

## 失败处理

- CI 失败默认阻断合并。
- 修复 CI 失败优先于继续堆叠功能。
- 环境性失败必须在 PR 中写明失败 job、错误摘要、重跑结果和残余风险；Xcode system content mismatch
  会以明确的非零 blocked 状态返回，不得被当作 XCTest PASS。
- 不允许用本地截图替代可复现命令输出。

## 任务验证与 CI

本地任务验证用于证明具体改动，远端 CI 用于提供可复现的合并质量门禁。任何本地任务结果、运行摘要或截图都不能替代 PR 所需的 governance、Core 和 macOS CI；CI 失败时不得合并。

## 跳过规则

只有以下情况允许跳过部分检查：

- 外部服务不可用，且 PR 描述记录了命令、错误和补跑计划。
- 文档-only 改动在本地可以按改动范围不跑产品 build，但远端 CI 仍运行完整 workflow；
  governance/prompt/skill 检查不得跳过。

## Quality Smoke

`./dev check quality` 是只读体验闭环检查，用来防止工程质量规则和 skill 路由靠人工记忆漂移。它检查：

- Rust / Swift / Markdown 编码规范、注释策略和函数 / 文件长度规则是否可发现。
- Core、macOS、DB / migration、CI、release、Git checkpoint 和 residual ledger 是否仍有明确 owner。
- repo-local skill 数量和导航是否与当前 9 个 AreaMatrix skills 一致。
- governance CI 是否继续运行这条 smoke gate。

它不替代 `cargo fmt`、`cargo clippy`、SwiftLint、SwiftFormat、XCTest、review 或 release evidence，只负责把“该读哪个规则、该触发哪个 owner”固定成可执行检查。

## Long-term Wording Audit

`./dev check wording` 是长期源事实口径门禁。它扫描 `docs/**`、Core 正式代码面、Core UDL / Cargo 元数据、README、治理规则、repo-local skills 和 `core/tests/**`，阻止当前长期源重新出现短期执行口径、旧发布轨道命名或历史拆分措辞。

专项审计可运行：

```bash
./dev wording audit --show-allowed
```

检查会把允许项单独分类：事务式 `staging`、Xcode `Build Phase`、Apple/macOS beta 测试、系统临时文件、治理规则中的受控词清单，以及集中历史证据测试。其他长期源事实命中必须改成长期产品、架构、API、UX、测试或发布语义。

唯一固定上游快照 `docs/governance/upstream/ASW-EWF-001-1.0.0.txt` 以
`allowed-upstream-snapshot` 分类显示。它是完整的外部规范副本，不代表 AreaMatrix 当前产品口径；
该例外只匹配精确路径，且文件内容必须继续通过治理登记册 SHA-256 校验。相邻文件或其他
`docs/governance/upstream/` 内容不会自动获得豁免。

## Secret Scan Checkout

`governance-ci.yml` 必须用 `actions/checkout` 的 `fetch-depth: 0`。`gitleaks/gitleaks-action`
在 push / merge commit 上会扫描 Git revision range；浅克隆缺少 parent commit 时会把
`<before>..<after>` 解析成 ambiguous revision，导致扫描未完成并以错误退出。

## Related

- [testing.md](testing.md)
- [git-workflow.md](git-workflow.md)
- [dependency-policy.md](dependency-policy.md)
- [../../CODE_REVIEW.md](../../CODE_REVIEW.md)
- [secret-scan-runbook.md](secret-scan-runbook.md)
