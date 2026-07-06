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

正式 Stage 1 alpha 分发前，release owner 必须把第 3 节的 release decision record 填为真实
值，并同步更新 [release-checklist.md](release-checklist.md) 与 residual ledger。缺任一字段时，
Stage 1 alpha 仍保持 blocked。

## 2. 已有本地入口

| 项目 | 状态 | 证据 |
|---|---|---|
| Alpha feedback issue template | present | `.github/ISSUE_TEMPLATE/alpha_feedback.md` |
| Feedback labels | present | `alpha-feedback`、`needs-triage` |
| Build / environment fields | present | version、build、download source、DMG SHA-256、macOS、chip、clean Mac、repo location、iCloud Drive |
| Data safety fields | present | 用户文件、`.areamatrix/` DB、staging、索引损坏确认 |
| General Discussion links | present | `.github/ISSUE_TEMPLATE/config.yml` links Q&A / Ideas / Security |
| Formal alpha announcement / Discussion | pending | no release announcement URL recorded |
| Trusted tester list | pending | no tester cohort recorded |
| Feedback triage owner | pending | no named person or release role decision recorded |

## 3. Release Decision Record

以下记录必须由 release owner 在正式 alpha 前填写；不得用占位符关闭 blocker。

```yaml
alpha_feedback_release_decision:
  status: "pending | ready"
  release_candidate: "v0.1.0"
  trusted_tester_list:
    status: "pending | recorded"
    source: "<private tester list, team roster, or release issue URL>"
    tester_count: "<integer>"
  announcement:
    status: "pending | recorded"
    url: "<GitHub Discussion, release issue, or announcement URL>"
    audience: "trusted-testers"
  feedback_route:
    status: "pending | recorded"
    primary: "GitHub issue template: Alpha Feedback"
    secondary: "<Discussion category or private support route>"
    labels:
      - alpha-feedback
      - needs-triage
  triage_owner:
    status: "pending | recorded"
    owner: "<GitHub handle, release owner, or team alias>"
    response_slo: "<for example: first response within 2 business days>"
  release_gate: "block_if_any_pending"
```

## 4. 关闭条件

`v1-rl-006` 只能在以下条件全部满足后关闭：

1. 可信测试者名单或名单来源已记录，且不是空占位。
2. 正式 announcement / Discussion / release issue URL 已记录。
3. 反馈主路线和备用路线已记录，且指向可访问入口。
4. triage owner 已记录，且不是空占位。
5. [release-checklist.md](release-checklist.md)、`workflow/versions/v1-mvp/residuals/residuals.yaml`
   和 `tasks/indexes/residuals.md` 已同步。

## 5. 当前阻断

- `trusted_tester_list.status: pending`
- `announcement.status: pending`
- `feedback_route.status: pending`
- `triage_owner.status: pending`

这些是 release decision blocker；不能由 local QA、未公证预览 DMG、issue template、自动化测试或同机
smoke 替代。

## Related

- [release-checklist.md](release-checklist.md)
- [release notes preview 2](release-notes/release-notes-v0.1.0-unnotarized-preview.2.md)
- [v1 residuals](../residuals/)
