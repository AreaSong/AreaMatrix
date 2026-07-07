# Stage 1 Alpha Feedback Route

> v1 formal alpha 反馈入口、缺口和关闭条件。本文只记录 release decision 状态，不创建
> GitHub Discussion、不邀请 tester，也不把未公证预览标记为正式 alpha。
>
> 阅读时长：约 4 分钟。

---

## 1. 当前结论

当前结论：**不关闭 `v1-rl-006`**。

`.github/ISSUE_TEMPLATE/alpha_feedback.md` 已提供可信测试者反馈 issue 模板，能够收集 build、
环境、iCloud、clean Mac、数据安全和复现步骤字段。该模板只是本地反馈入口准备，不等于可信
测试者名单、正式 announcement / Discussion 链接、最终反馈分流路线或 triage owner 已决策。
`./dev release alpha-feedback-decision-audit --json` 已提供只读审计入口，可核对 issue template、
Discussion links 和 release decision record 缺口；该命令不会创建 Discussion、邀请 tester、发布公告、
分配 owner 或把 formal alpha 标记 ready。

正式 Stage 1 alpha 分发前，release owner 必须把第 3 节的 release decision record 填为真实
值，记录 tester invitation / announcement / owner assignment side effects，并同步更新
[release-checklist.md](release-checklist.md) 与 residual ledger。缺任一字段时，Stage 1 alpha
仍保持 blocked。

## 2. 已有本地入口

| 项目 | 状态 | 证据 |
|---|---|---|
| Alpha feedback issue template | present | `.github/ISSUE_TEMPLATE/alpha_feedback.md` |
| Feedback labels | present | `alpha-feedback`、`needs-triage` |
| Build / environment fields | present | version、build、download source、DMG SHA-256、macOS、chip、clean Mac、repo location、iCloud Drive |
| Data safety fields | present | 用户文件、`.areamatrix/` DB、staging、索引损坏确认 |
| General Discussion links | present | `.github/ISSUE_TEMPLATE/config.yml` links Q&A / Ideas / Security |
| Read-only decision audit | present | `./dev release alpha-feedback-decision-audit --json` |
| Formal alpha announcement / Discussion | pending | no release announcement URL recorded |
| Trusted tester list | pending | no tester cohort recorded |
| Feedback triage owner | pending | no named person or release role decision recorded |

## 3. Release Decision Record

以下记录必须由 release owner 在正式 alpha 前填写为真实值；当前字段保持 `pending` / `null` /
`false`，不得用占位符关闭 blocker。`trusted_tester_list.tester_count` 必须是大于 0 的整数。

```yaml
schema_version: 1
mode: alpha_feedback_release_decision_record
residual_id: v1-rl-006
release: v0.1.0
status: blocked
closes_residual: false
release_gate: block_if_any_pending

alpha_feedback_release_decision:
  status: pending
  release_candidate: v0.1.0
  trusted_tester_list:
    status: pending
    source: null
    tester_count: null
  announcement:
    status: pending
    url: null
    audience: trusted-testers
  feedback_route:
    status: pending
    primary: "GitHub issue template: Alpha Feedback"
    secondary: null
    labels:
      - alpha-feedback
      - needs-triage
  triage_owner:
    status: pending
    owner: null
    response_slo: null

decision_audit:
  command: ./dev release alpha-feedback-decision-audit --json
  status: BLOCKED
  local_entrypoints:
    issue_template: PASS
    discussion_links: PASS
  decision_gate: BLOCKED
  closes_residual: false

decision_side_effects:
  github_discussion_created: false
  testers_invited: false
  announcement_published: false
  feedback_owner_assigned: false
  feedback_route_marked_ready: false

does_not_prove:
  - trusted tester list exists
  - trusted testers were invited
  - formal announcement or Discussion exists
  - feedback route is final
  - triage owner has accepted responsibility
  - v1-rl-006 is closed
  - formal alpha release readiness
```

## 4. 关闭条件

`v1-rl-006` 只能在以下条件全部满足后关闭：

1. 可信测试者名单或名单来源已记录，`tester_count` 是大于 0 的整数，且 tester invitation 已真实记录。
2. 正式 announcement / Discussion / release issue URL 已记录并发布。
3. 反馈主路线和备用路线已记录，且指向可访问入口。
4. triage owner 已记录，且不是空占位，并已接受分流责任。
5. [release-checklist.md](release-checklist.md)、`workflow/versions/v1-mvp/residuals/residuals.yaml`
   和 `tasks/indexes/residuals.md` 已同步。

## 5. 当前阻断

- `trusted_tester_list.status: pending`
- `decision_side_effects.testers_invited: false`
- `announcement.status: pending`
- `feedback_route.status: pending`
- `triage_owner.status: pending`
- `decision_audit.decision_gate: BLOCKED`
- `closes_residual: false`
- `release_gate: block_if_any_pending`

这些是 release decision blocker；不能由 local QA、未公证预览 DMG、issue template、自动化测试或同机
smoke 替代。

## Related

- [release-checklist.md](release-checklist.md)
- [release notes preview 2](release-notes/release-notes-v0.1.0-unnotarized-preview.2.md)
- [v1 residuals](../residuals/)
