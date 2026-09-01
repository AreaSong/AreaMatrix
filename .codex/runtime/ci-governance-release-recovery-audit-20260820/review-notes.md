# 全仓库治理、发布与恢复审计工作笔记

审计 ID：`ci-governance-release-recovery-audit-20260820`

本台账只记录本次只读审计过程和证据分类。没有修改产品代码、workflow、脚本、历史证据、residual、任务状态或 Git 历史；没有提交、推送、创建远端对象、签名、公证、上传制品或操作真实用户文件。

## 结论边界

- 固定初始快照的分类守恒成立：`5109 = PASS 50 + FINDING 11 + BLOCKED 4889 + NOT_APPLICABLE 159`。
- 当前工作树在快照后持续漂移，新增/修改路径未全部逐行复核；当前树人工逐文件逐行审计为 `BLOCKED`。
- 远端治理、branch protection、required checks/reviews、远端 CODEOWNERS、Actions runs 和独立 reviewer 均为 `BLOCKED`。`gh auth status` 显示未登录；没有发起 GitHub API 或网络查询。
- 正式 `v0.1.0` 发布为 `BLOCKED`：真实 iCloud、Developer ID/notary/staple/formal DMG、clean Mac、正式 tag/release、可信测试者和发布后观察证据均不完整。
- 恢复闭环为 `BLOCKED`/证据不足：M-02 无真实 iCloud 环境；M-01/M-03/M-04 的 PASS 记录不是按模板逐项结构化记录，测试也没有按 `manual_evidence_id` 解析字段。
- 两个空的 task-loop PASS 记录只表示空 summary/index 结构，不表示任何 task PASS；不能替代 verify log、CI、review 或 release evidence。

## 时间和快照

- 审计目录创建：`2026-08-20T04:46:21+08:00`。
- 初始 inventory：约 `2026-08-20T04:58:24+08:00`；固定快照 captured_at 写为 `2026-08-20T05:00:00+08:00`。
- 初始范围：tracked `5052`、untracked nonignored `57`、文本 `4947`、binary/opaque `152`、symlink `10`、可计文本行 `1,554,494`。
- ignored workspace artifacts `791,088`，单独计数，不进入 tracked + untracked nonignored 守恒式。
- 复核者：`PENDING`。子代理仅作为只读线索，主审计者复核了每条纳入最终 finding 的源行。

## 漂移记录

固定快照之后，其他审计目录继续生成文件，用户/子代理也继续修改产品源文件。`coverage.jsonl` 的最终化运行记录了当时的 added/removed/changed 列表；随后在 `2026-08-20T06:09:50+08:00` 的独立只读观察中，范围为 `5129`（相对初始 `5109` 新增 `20`、删除 `0`、变化 `89`，哈希阶段消失 `0`）。该观察已追加到 `blocked-evidence.jsonl`，并同步到 `scope.json.latest_scope_observation`，不替换固定初始快照。由于工作树不是冻结状态，不能把任何“当前路径总数”解释为全仓人工复核完成。解冻条件仍是冻结工作树、重建不可变快照、逐一复核新增/变化文本文件并重新计算守恒。

## 覆盖统计

`inventory.jsonl` 每一条初始快照路径都有状态、人工行区间（若有）、审计者、时间、finding ID 和 binary/symlink provenance 字段。覆盖分类为：

| 类别 | 数量 | 解释 |
|---|---:|---|
| PASS | 50 | 局部静态审阅且未发现本次审计 finding；不是远端/发布 PASS |
| FINDING | 11 | 局部静态审阅发现可行动问题 |
| BLOCKED | 4,889 | 未逐行读取、快照变化、外部证据缺失或人工覆盖不足 |
| NOT_APPLICABLE | 159 | binary/opaque/symlink 等有单项 provenance 分类；不等于忽略 |

文本覆盖：`61` 个完整直读、`25` 个局部摘录、`4,861` 个未完整读取。人工逐行总覆盖因此不是全仓完成。`workflow/versions/v1-mvp/execution/_shared/prompt_pipeline_lib/failure_recovery.py` 曾被人工覆盖表引用，但不在初始 inventory，保持缺口，不补造状态。

## 证据层级核对

1. **本地静态源**：workflow、规则、脚本、发布模板和 residual 索引的行号证据；可支持局部 PASS/FINDING。
2. **本地辅助命令**：只运行了文件清单、哈希、行数、`file`/`lipo`、Git tag 列表、`gh` 存在性/认证检查和 JSONL 解析；未运行测试、lint、doctor、task-loop、release wrapper 或 remote wrapper。
3. **task-loop 单任务 PASS**：无法重建。145 条历史结构化记录中 143 条引用的本地 copy/verify log 不存在，99 条含 completed task 但缺当前 verify log；2 条 PASS 是空结构记录。
4. **远端治理**：`gh version` 为 `2.96.0`，`gh auth status` 退出码 1；`api_attempted=false`、`network_attempted=false`。本地文档不能冒充远端证据。
5. **独立 reviewer**：没有合格独立 reviewer 身份、PR approval 或远端 review snapshot；`v2-risk-001` 仍为 `open`。
6. **正式发布**：本地 tag 只有 `v0.1.0-unnotarized-preview.2`；没有正式 `v0.1.0` tag/release、Developer ID、notary accepted log、staple、clean Mac 或真实 iCloud 记录。

## 最终台账校验

在 `2026-08-20T06:10` 左右执行只读 Ruby JSONL/字段校验：11 个 JSONL 文件全部可解析，状态值均在允许枚举内；`inventory.jsonl` 5109 条路径唯一，`coverage.jsonl` 5109 条文件记录与 inventory 路径集合一致，守恒式 `5109 = 159 + 4889 + 50 + 11` 成立；`findings.jsonl` 有 14 个唯一 finding（P1=6、P2=6、P3=2）；所有固定快照行区间格式有效，162 个 binary/symlink 记录均有 provenance，coverage 没有未知 finding 引用，最新 scope 观察与 `blocked-evidence.jsonl` 最后一条记录一致。该校验结果为 `PASS`，只证明台账结构和固定快照统计完整，不改变当前人工逐行覆盖、远端治理、正式发布、独立 reviewer 或恢复闭环的 `BLOCKED` 判定。

## 排除项

- checkpoint 先提交实现再提交 evidence 的双 commit 顺序是为避免 evidence 自引用；代码会在 evidence commit 失败时停止，当前没有足够证据把它列为可绕过门禁的独立 finding，作为残余运维风险保留。
- `RISK_POLICY=allow` 已列为 `F-GOV-003` 的中置信度政策冲突，而不是证明已发生破坏性操作；本次未执行任何 Mission-Critical 写操作。
- Rust/Swift 工具未完全固定列为 `F-CI-005` P3 可重复性风险；没有把它夸大为已证明的 CI bypass。
- tracked `libarea_matrix_core.a` 列为 `F-SC-001` P2 provenance finding，而不是断言它一定被错误消费；需要 build/link-map 证据决定删除或补 provenance。
- release checklist 的 2026-06-23 远端成功句子列为 `F-REMOTE-001` 历史证据可复核性问题；不是断言历史 run 必然虚假。

## 复核交接

本审计结束时不应运行会改变工作树或产生外部副作用的命令。补证顺序应为：冻结工作树并重建快照 -> 完成剩余文本逐行覆盖 -> 独立 reviewer 复核 findings -> 在认证只读环境中运行仓库 remote wrapper -> 补正式发布/恢复证据 -> 再做最小 JSONL/守恒校验。历史 progress、logs、summary、residual 和 Git 历史不得回填或重写。
