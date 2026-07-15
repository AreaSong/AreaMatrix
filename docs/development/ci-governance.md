# CI Governance

> AreaMatrix 的持续集成治理：所有 PR 都要跑核心、macOS、prompt、skill 和治理门禁。
>
> 阅读时长：约 4 分钟。

---

## 目标

CI 是合并前的最低共同质量线。它不能替代 review，但可以阻止明显不完整、不可复现或不可追溯的改动进入主线。

## 必跑矩阵

| Workflow | 目的 | 触发 |
|---|---|---|
| `core-ci.yml` | Rust fmt、clippy、test、universal build、coverage | 所有 PR、main push |
| `macos-ci.yml` | Core build、tracked Swift bindings drift、Xcode build/test、Swift Watcher / Bridge coverage、SwiftLint、SwiftFormat | 所有 PR、main push |
| `governance-ci.yml` | governance files、skills、quality smoke、品牌资产、Codex OS、task-loop、prompt doctor、diff check、secret scan | 所有 PR、main push |

macOS app 与 `AreaMatrix.xcodeproj` 已是仓库必需组成部分。`macos-ci.yml` 必须先显式检查工程和源码目录；
任一目录缺失都应立即失败，不得通过条件表达式跳过 build/test、SwiftLint 或 SwiftFormat。
`./dev check governance` 还会把磁盘上的 `*GovernanceTests.swift` 和
`MacOSGovernance*TestSupport.swift` 与 `AreaMatrixTests` target 的 Sources membership 双向核对，
防止治理测试只有文件引用、没有进入可执行 XCTest target 时被 CI 静默漏跑。
它还会核对 Core 与 macOS 之间的 `AREAMATRIX_*_RUNTIME` key 合同，防止新增或改名 runtime 后只有一侧更新。

## 本地等价检查

提交前至少运行与改动范围匹配的检查：

```bash
./dev check governance
./dev check skills
./dev check quality
./dev check codex-os
./dev check wording
./dev check task-loop
./dev check prompts
./dev check diff
./dev check secrets          # 默认 diff 模式：未提交变更 + 领先 origin/main 的 commit
./dev build core
./dev bindings verify        # 只读比较当前 UDL 与 Xcode tracked Swift bindings
python3 -m venv .brand-venv
.brand-venv/bin/pip install --requirement scripts/brand/requirements.txt
.brand-venv/bin/python scripts/brand/validate_assets.py
```

`./dev release status --json --remote` 和 `./dev release evidence-audit --json` 是 release owner
的只读发布聚合 / 记录一致性检查，不属于普通 PR 的必跑 CI 门禁。普通 PR 中若 status 因正式发布证据、
正式 tag 或外部分发条件缺失而 `BLOCKED`，不应把它记录为 CI failure；只有执行正式发布流程时，
才按 [release.md](release.md) 的发布门禁处理。`evidence-audit` 即使 `PASS`，也只说明 evidence
record 与 residual 索引一致，不证明发布 ready。
`./dev release final-tag-readiness-audit --json --remote` 同样是 release owner 的只读 tag 前门禁审计，
不属于普通 PR 或 CI 必跑项。它不会创建 tag、推送 tag 或创建 GitHub Release；当前因其他发布证据
阻断而 `BLOCKED` 时，不应记为普通 CI failure。
`./dev release icloud-placeholder-smoke-audit --json` 是 release owner 的只读 iCloud smoke record
审计，不属于普通 PR 或 CI 必跑项。它只读取 evidence record 和 residual 索引，不接收路径、不运行
`mdls`、不触发 iCloud 下载、不读取用户文件内容、不写 DB、不写 `.areamatrix/`；当前
`smoke_evidence_gate: BLOCKED` 表示 M-02 发布证据仍缺失，不应记为普通 CI failure。
`./dev release task05-release-review-audit --json` 是 release owner 的只读 release evidence review
审计，不属于普通 PR 或 CI 必跑项。它只读取对应的 v1 evidence record 和 residual 索引，
不读取 `.codex/task-loop-logs/**`、不回填 progress、logs、summaries、checkpoint metadata、commit
或 tag；当前 `release_evidence_review_gate: BLOCKED` 表示 fresh review 证据仍缺失，不应记为普通
CI failure。
`./dev release distribution-artifact-probe --app-path <APP_PATH> --dmg-path <DMG_PATH> --json`
同样是 release owner 的只读产物 probe，不属于普通 PR 或 CI 必跑项；它不会写产物或提交公证，
但也不能证明正式分发 ready。
`./dev release alpha-feedback-decision-audit --json` 是 release owner 的只读反馈路线决策审计，
不属于普通 PR 或 CI 必跑项。它只核对本地 issue template、Discussion links 和
`alpha-feedback-route.md` 中的 decision record；当前缺 tester 名单、announcement / Discussion、
备用反馈路线、triage owner 或响应 SLO 时返回 `BLOCKED` 是正确的发布阻断，不应记为普通 CI failure。
`./dev release readiness-build --install` 会写入本机 Applications 目录，不属于 CI 门禁；
CI 和普通 PR 不应安装或替换 `/Applications/AreaMatrix.app`。

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

## Task-loop 与 CI

Task-loop 的 `VERIFY_RESULT: PASS` 是单任务验收证据。合并前仍需 CI 作为远端质量门禁。

如果 `GIT_CHECKPOINT=push` 自动上传 PASS task：

- commit 必须包含 progress/log/summary evidence；
- PR 仍需要 governance/core/macos CI；
- CI 失败时不得继续合并，需要新 commit 修复。

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
