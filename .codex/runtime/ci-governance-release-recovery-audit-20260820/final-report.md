# 全仓库治理、发布与恢复证据闭环审计

审计 ID：`ci-governance-release-recovery-audit-20260820`  
最终状态：`BLOCKED`

本报告是只读审计交付物。它没有修改产品代码、workflow、脚本、历史证据、residual、任务状态或 Git 历史，也没有创建远端对象、签名、公证、上传制品或操作真实用户文件。

## Findings First

以下问题按严重度排序。完整结构化字段、证据链和关闭条件见 `findings.jsonl`；每条都经过主审计者沿精确行号复核，但没有独立合格 reviewer，因此 findings 集合本身不能标记为 review PASS。

### P1

| ID | 位置 | 结论和影响 |
|---|---|---|
| `F-CI-001` | `.github/workflows/release-evidence.yml:33-57,71-75` | 三个发布命令均是 `command \| tee` 且 `continue-on-error`；未显式 `pipefail`，生产者失败可能被 `tee` 隐藏，最终 outcome gate 可能错误放行不完整快照。应捕获真实 producer exit code，并用强制失败测试验证。 |
| `F-CI-002` | `.github/workflows/remote-governance.yml:40-45` | remote audit 通过 `tee` 输出但没有显式 `pipefail`；认证不足或 wrapper `BLOCKED` 可能被上传为绿 job。应让 wrapper 非零严格传播，同时保留失败 artifact。 |
| `F-GOV-001` | `CODE_REVIEW.md:36-45`; `scripts/task_loop/runner.py:786-813`; `scripts/task_loop/git.py:417-471` | runner 只把 `Expected New Paths` 用作 stale-resume dirty allowlist；checkpoint 未对 manifest 的 Expected/Forbidden 路径做最终 staged diff enforcement，可能提交 task scope 外文件。应在 commit 前解析 allow/deny manifest 并对新增、修改、删除、重命名逐项阻断。 |
| `F-GOV-002` | `.ai-governance/workflows/prompt-task-runtime.md:83-92`; `workflow/versions/v1-mvp/execution/_shared/prompt_pipeline_lib/commands.py:178-210`; `repository.py:198-229` | 保留的 v1 `mark --status completed` 可在无 verify log、`VERIFY_RESULT: PASS`、summary、checkpoint hash 或恢复授权时写入 completed；`--force` 还可绕过依赖。它与“不得伪造历史证据”冲突。应改成只读历史检查或绑定不可伪造的 verify evidence，不能回填旧历史。 |
| `F-REL-001` | `scripts/dev_tools/release_status.py:63-98,321-330,626-648`; `workflow/versions/v1-mvp/evidence/distribution-signing-notarization.md:100-116` | formal DMG checksum 只要求非空，不校验 64 位十六进制格式、与实际 artifact 绑定或跨记录一致；`spctl` 的 `Notarized Developer ID` required source 也未被验证。手填字段可能关闭 `v1-rl-003/004`。应加入 digest、artifact identity、notary/staple/spctl transcript 关联验证。 |
| `F-REC-001` | `workflow/versions/v1-mvp/evidence/recovery-scenarios.md:59-81,92-111,175-223`; `core/tests/recovery_scenarios.rs:225-247` | M-01/M-03/M-04 虽在 prose 中写 pass，却没有按记录提供 operator、evidence_paths 和全部 user-file invariant 字段；测试只在整篇文档搜索关键词，顶部模板即可满足。应改为逐 `manual_evidence_id` 解析的 schema negative tests。 |

### P2

| ID | 位置 | 结论和影响 |
|---|---|---|
| `F-CI-003` | `.github/workflows/release-evidence.yml:5-10,45-63`; `scripts/dev_tools/release_status.py:14` | `inputs.release` 只改变 artifact 名称，命令未接收该 release，status 工具硬编码 `v0.1.0`；输入其他版本会产生“名称与内容不一致”的证据。应移除输入或把经过校验的 release ID 写入每个 payload。 |
| `F-CI-004` | `.github/workflows/remote-governance.yml:3-6,28-38` | workflow 未声明 `workflow_dispatch.inputs.branch` 却读取它；手动选择分支实际无效并回退 default branch，可能把证据归给错误分支。应声明/校验输入或删除死路径。 |
| `F-GOV-003` | `.ai-governance/workflows/prompt-task-runtime.md:11,41-42`; `:56`; `.ai-governance/workflows/external-capability-admission.md:72` | `RISK_POLICY=allow` 说 High/Mission-Critical 不再等待确认，与相邻 Mission-Critical 必须显式确认的规则冲突。未证明本次发生破坏性操作，但授权语义不清。应使用 task-scoped approval，缺审批时默认 pause。 |
| `F-REL-002` | `docs/development/release.md:155-160`; `workflow/versions/v1-mvp/evidence/distribution-signing-notarization.md:112-116`; `scripts/dev_tools/release.py:816-820` | 长期发布指南对 DMG 使用 `spctl --type open`，证据模板/工具使用 `--type install`；未来结果不可直接比较。应统一命令语义并记录完整工具版本/输出。 |
| `F-REMOTE-001` | `workflow/versions/v1-mvp/evidence/release-checklist.md:67` | 2026-06-23 远端 CI success 只有日期、commit 前缀和 workflow 名，没有 run ID、URL 或机器快照；可作为历史叙述，不能作为当前可复核 remote evidence。 |
| `F-SC-001` | `apps/macos/AreaMatrix/Bridge/UniFFI/libarea_matrix_core.a`（binary）；`docs/development/build.md:48-56`; `apps/macos/AreaMatrix.xcodeproj/project.pbxproj:2611,4073` | tracked 约 94 MB universal x86_64/arm64 archive（Git blob `093146...`，当前 sha256 `69ef...`）没有 source/tool fingerprint 或明确 consumer binding；文档说正式输出在 ignored `Bridge/Generated`。需证明可重现和消费关系，或移除 stale bytes。 |

### P3

| ID | 位置 | 结论和影响 |
|---|---|---|
| `F-CI-005` | `.github/workflows/core-ci.yml:35-97`; `.github/workflows/macos-ci.yml:42,88,345-391` | Rust `stable`、无版本号的 `cargo-llvm-cov`、Homebrew 当前 SwiftLint/SwiftFormat 使同一 commit 的工具结果可能漂移。暂未证明可绕过门禁；应建立受审查的 toolchain/version manifest。 |
| `F-REL-003` | `docs/development/release.md:191-196`; `scripts/dev_tools/release_status.py:63-98` | 发布后要求监控 crash/import/DB/iCloud/AI provider 并记录 owner/SLO，但 residual closure schema 没有观察窗口、数据源或升级/回滚结论字段。正式发布后无法机械证明观察闭环。 |

## 守恒与范围

初始固定快照（tracked + untracked nonignored，审计目录除外）统计：

| 项目 | 数量 |
|---|---:|
| 文件总数 | 5,109 |
| tracked | 5,052 |
| untracked nonignored | 57 |
| 文本 | 4,947 |
| binary/opaque | 152 |
| symlink | 10 |
| 可计文本行 | 1,554,494 |
| ignored workspace artifacts（单独计数） | 791,088 |

固定快照分类守恒：`5109 = 50 PASS + 11 FINDING + 4889 BLOCKED + 159 NOT_APPLICABLE`。文本人工覆盖只有 61 个完整直读、25 个局部摘录、4,861 个未完整读取；所以“固定快照分类守恒”不等于“全仓逐行审计通过”。

快照后其他审计目录和用户/子代理继续写入，`coverage.jsonl` 最终化记录了当时的 drift。随后在 `2026-08-20T06:09:50+08:00` 的独立只读观察中，当前范围为 `5129`（相对初始 `5109` 新增 `20`、删除 `0`、变化 `89`，哈希阶段消失 `0`）；该观察已追加到 `blocked-evidence.jsonl`，并写入 `scope.json.latest_scope_observation`，不替换固定初始快照。`scope.json`/`blocked-evidence.jsonl` 明确把当前树标为 `BLOCKED`，解冻条件是冻结工作树、重建不可变快照、逐一复核所有新增/变化文本文件并重新守恒。

## CI 矩阵

| Workflow | 本地源审计 | 权限/缓存/制品 | 退出码结论 | 远端状态 |
|---|---|---|---|---|
| Core CI | `FINDING`（工具版本可漂移） | `contents: read`；Rust cache；coverage-lcov | 主要命令直接阻断；未证明 pipeline 吞错 | `BLOCKED` |
| Governance CI | `PASS`（仅结构/声明） | 默认 read；gitleaks job 有 `security-events: write`；无制品 | 直接命令和 action 门禁存在 | `BLOCKED` |
| macOS App CI | `FINDING`（工具版本可漂移） | CoreSDK build-once、artifact restore/verify、xcresult/diagnostics/metrics | build/test/lint 是阻断；feedback metric 明确非权威 | `BLOCKED` |
| Remote Governance | `FINDING` (`F-CI-002`,`F-CI-004`) | read-only actions/contents/PR；remote JSON artifact | `tee` 未显式 pipefail；branch 输入未声明 | `BLOCKED` |
| Release Evidence | `FINDING` (`F-CI-001`,`F-CI-003`) | contents read；三个 JSON snapshot artifact | `continue-on-error` + `tee` 可能隐藏 producer 失败 | `BLOCKED` |

本地 workflow 结构不能证明 Actions run、required contexts、cache 实际命中、artifact 内容或 branch protection 已生效。

## 本地治理、task-loop 和 review

| 控制 | 状态 | 证据/说明 |
|---|---|---|
| CODE_REVIEW、风险等级、独立 reviewer 政策 | `PASS`（本地静态） | `CODE_REVIEW.md:19-47`；政策要求 L3/L4/High/Mission-Critical 独立复核 |
| task scope 最终 enforcement | `FINDING` | `F-GOV-001` |
| v1 historical mark 防伪 | `FINDING` | `F-GOV-002`；不得把旧历史回填成 PASS |
| RISK_POLICY precedence | `FINDING` | `F-GOV-003`；本次未执行高风险写操作 |
| task-loop 结构化记录 | `BLOCKED` | 145 条：143 BLOCKED、2 空结构 PASS；143 缺本地日志，99 有 completed 但无 current verify log |
| checkpoint accepted exceptions | `NOT_APPLICABLE`/历史状态 | 35 条，均 `git.checkpoint=off`；不得回填历史 |
| 独立合格 reviewer | `BLOCKED` | 无身份、PR approval 或远端 review snapshot；`v2-risk-001` open |
| merge-ready / release-ready | `BLOCKED` | 本地 task PASS、截图、dry-run、旧日志都不能替代 CI/review/release |

## 远端证据

只执行了认证前置检查：`gh version 2.96.0`（本地 binary 存在）和 `gh auth status`（退出码 1：未登录任何 GitHub host）。因此：

- `api_attempted: false`
- `network_attempted: false`
- branch protection、strict/up-to-date、required checks、required reviews、CODEOWNERS、Actions runs、独立 reviewer 全部 `BLOCKED`
- 没有运行 `./dev governance remote-audit --json` 或 `./dev governance status --json`，因为未认证时用户规则要求不发起 API 请求

补证条件是认证的只读 GitHub CLI、仓库既有 remote wrapper 输出、分支/commit/run 时间、required contexts/reviews 和远端 CODEOWNERS readback。任何本地历史句子都不能替代这些字段。

## 发布与分发

| 门禁 | 状态 | 当前证据 |
|---|---|---|
| Cargo/marketing version | `BLOCKED` | `0.1.0` 字符串存在，但 Xcode build number 为 `202605101812`，没有同一正式 release candidate 绑定 |
| 正式 tag/release | `BLOCKED` | 只有 `v0.1.0-unnotarized-preview.2`；正式 `v0.1.0` created/pushed/GitHub Release URL 均 absent |
| Developer ID | `BLOCKED` | 无真实 Developer ID identity 证据 |
| notarization/staple | `BLOCKED` | no accepted notary log、stapled app/DMG |
| formal DMG/checksum | `BLOCKED` | no artifact-bound formal DMG/checksum；只读 status validation 仍有 `F-REL-001` |
| Gatekeeper/clean Mac | `BLOCKED` | 同机 local QA/ad-hoc 不能替代 clean Mac first launch |
| iCloud placeholder | `BLOCKED` | `v1-rl-002`；真实 UI Download & retry、DB row 和 invariant 缺失 |
| trusted testers/feedback | `BLOCKED` | `v1-rl-006`；名单、邀请、公告、triage owner 缺失 |
| post-release observation | `BLOCKED`/schema gap | `F-REL-003` |

## Recovery / rollback

恢复模板在 `recovery-scenarios.md:59-81` 要求 `manual_evidence_id`、environment、operator、executed_at、result、evidence_paths 和四类 user-file invariant。M-01、M-03、M-04 的 PASS 段落只在 prose 中描述这些事实，未按每条记录提供完整字段；M-02 明确没有真实 iCloud 环境。`core/tests/recovery_scenarios.rs:225-247` 只做全篇 substring 断言，不能证明每个 PASS record 合规。

已记录的 local QA 观察（源文件 checksum、staging、DB integrity、README/AREAMATRIX 不覆盖）只能作为辅助线索；它们不是正式分发机 TCC、clean Mac、iCloud 或发布后恢复闭环证据。回滚流程在 `docs/development/release.md:198-205` 有文字步骤，但没有真实 formal release/rollback event、受影响版本、观察窗口和替换 release 记录。

## Residual 全量对账

来源为 `workflow/residuals/README.md`、全局 YAML 及每个 `version_residuals[].source`。共 21 个 ID，所有 source 路径存在；状态分布为 closed 8、blocked-external 2、blocked-decision 2、deferred 3、open 1、accepted-exception 1、reference-only 3、template-only 1。

| ID | 状态 | 类型/当前影响 | 本次审计结论 |
|---|---|---|---|
| `global-product-restore-file-contract` | closed | product contract / none | `PASS`（索引对账；未重跑实现验证） |
| `global-product-metadata-reader-write-flags` | closed | file safety / none | `PASS`（索引对账；未重跑验证） |
| `global-product-soft-delete-retention` | closed | product contract / none | `PASS`（历史 closure，不回填） |
| `global-product-ui-localization` | closed | product contract / none | `PASS`（索引对账；未重跑 macOS gates） |
| `global-docs-core-module-doc-coverage` | closed | product docs / none | `PASS`（索引对账） |
| `global-governance-ios-bindings-verify-gap` | closed | file safety / none | `PASS`（索引对账；未运行 bindings verify） |
| `global-ai-classification-call-log-gate` | closed | product contract / none | `PASS`（索引对账；未重跑测试） |
| `global-ai-semantic-search-remote-route` | closed | product contract / none | `PASS`（索引对账；未重跑测试） |
| `global-ref-areaflow` | reference-only | historical reference / none | `NOT_APPLICABLE`，不进入 task-loop |
| `global-template-vtemplate` | template-only | template reference / none | `NOT_APPLICABLE`，blocked-by-design |
| `global-ref-closed-backlog-packages` | reference-only | backlog reference / none | `NOT_APPLICABLE`，5 closed/0 open |
| `global-marker-product-doc-status-words` | reference-only | product-doc marker / none | `NOT_APPLICABLE`，产品状态词非 task state |
| `v1-rl-002` | blocked-external | real iCloud / formal alpha blocked | `BLOCKED`，真实环境和 UI/DB/invariant 缺失 |
| `v1-rl-003` | blocked-external | signing/notary/DMG/clean Mac | `BLOCKED`，外部 Apple/clean Mac 证据缺失；并受 `F-REL-001` 影响 |
| `v1-rl-004` | blocked-decision | formal tag/release | `BLOCKED`，gates 未闭合、正式 tag/release absent |
| `v1-rl-006` | blocked-decision | testers/feedback route | `BLOCKED`，名单、邀请、公告、owner absent |
| `v1-ex-001` | accepted-exception | 35 historical checkpoint gaps | `NOT_APPLICABLE`，不得回填旧历史 |
| `v1-ref-003-1-task-05` | deferred | fresh release review | `BLOCKED`，不得伪造 task-loop verify PASS |
| `v2-risk-001` | open | independent review | `BLOCKED`，无合格独立 reviewer |
| `v2-dep-003` | deferred | execution authorization | `BLOCKED`，不授权 promotion/apply/runner |
| `v2-dep-004` | deferred | remote merge controls | `BLOCKED`，本地不能替代 remote evidence |

## 验证边界

已执行且只读：目录/文件 inventory、SHA-256、行数统计、Git status/tag 列表、file/lipo 对 opaque archive、gh --version、gh auth status、JSONL 解析、守恒统计，以及最终台账字段校验（11 个 JSONL 全部可解析、路径集合一致、finding ID 唯一、最新 scope 观察对齐）。未执行：测试、lint、doctor、workflow doctor、task-loop、release preflight/evidence/status wrapper、remote governance wrapper、GitHub API/curl、签名/公证/staple/DMG、真实 iCloud/clean Mac/外部 tester 操作。

## 最终判定

| 维度 | 判定 |
|---|---|
| 固定初始快照分类守恒 | `PASS`（只证明统计守恒） |
| 当前工作树全仓逐文件逐行人工审计 | `BLOCKED` |
| 本地静态 CI/治理审阅 | `FINDING`（存在上列问题） |
| 本地辅助检查 | `PASS`（仅限已执行的只读统计/解析） |
| task-loop 单任务 PASS | `BLOCKED`/不可重建 |
| 远端 CI/Actions/branch protection/CODEOWNERS | `BLOCKED` |
| 独立合格 reviewer | `BLOCKED` |
| 正式签名/公证/DMG/clean Mac 发布 | `BLOCKED` |
| 真实 iCloud/外部测试/发布后观察 | `BLOCKED` |
| recovery/manual evidence 闭环 | `BLOCKED`/证据不足 |

因此不能宣称 AreaMatrix 已通过全仓人工审计、治理、merge readiness、正式发布或恢复闭环。补证必须在冻结且可复核的新快照上继续，不能通过改写历史记录或把本地/旧证据升级为远端、独立 reviewer 或正式发布证据。
