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
| `macos-ci.yml` | Xcode build/test、SwiftLint、SwiftFormat | 所有 PR、main push |
| `governance-ci.yml` | governance files、skills、quality smoke、Codex OS、task-loop、prompt doctor、diff check、secret scan | 所有 PR、main push |

macOS app 工程尚未存在时，`macos-ci.yml` 可以按现有保护逻辑跳过 app build/test，但 workflow 本身必须运行。

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
```

`./dev check codex-os` 会覆盖 Codex OS 第二阶段 flow 入口的 CLI smoke，包括
`start-flow`、`run-validation`、`repair-plan`、`close-flow` 和 `ops-flow`。

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
- 环境性失败必须在 PR 中写明失败 job、错误摘要、重跑结果和残余风险。
- 不允许用本地截图替代可复现命令输出。

## Task-loop 与 CI

Task-loop 的 `VERIFY_RESULT: PASS` 是单任务验收证据。合并前仍需 CI 作为远端质量门禁。

如果 `GIT_CHECKPOINT=push` 自动上传 PASS task：

- commit 必须包含 progress/log/summary evidence；
- PR 仍需要 governance/core/macos CI；
- CI 失败时不得继续合并，需要新 commit 修复。

## 跳过规则

只有以下情况允许跳过部分检查：

- 目标工程尚未存在，workflow 内部已显式检测并说明。
- 外部服务不可用，且 PR 描述记录了命令、错误和补跑计划。
- 文档-only 改动无需跑产品 build，但 governance/prompt/skill 检查仍必须跑。

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
