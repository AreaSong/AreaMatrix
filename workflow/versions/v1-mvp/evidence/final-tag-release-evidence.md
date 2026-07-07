# Final Tag Release Evidence

> v1 正式 `v0.1.0` tag 创建、推送和 release decision 前置条件记录。
>
> 阅读时长：约 4 分钟。

---

## 当前结论

当前结论：**不关闭 `v1-rl-004`**。

正式 `v0.1.0` tag 仍未创建，也未推送。`v0.1.0-unnotarized-preview.2` 是可信测试者
preview tag / prerelease 轨道，不能替代正式 `v0.1.0` tag、正式 notarized release artifact、
正式 release notes 或最终 release decision。

本文件只记录最终 tag 的前置条件和关闭字段，不创建 tag、不推送 tag、不发布 GitHub Release。

## 证据记录模板

真实补证时，release owner 必须先确认所有 release gates 已关闭，再创建并推送正式 tag。任一字段
仍为 `pending`、`blocked` 或 `fail` 时，release gate 保持阻断。

```yaml
schema_version: 1
mode: final_tag_release_record
residual_id: v1-rl-004
release: v0.1.0
status: blocked
closes_residual: false
release_gate: block_until_all_release_gates_closed_and_final_tag_pushed

release_candidate:
  commit: null
  branch: main
  status: pending
  ci_status: pending
  release_checklist_status: blocked

required_gates:
  v1_rl_002_icloud_placeholder:
    status: blocked
    required_evidence: real iCloud placeholder Download & retry smoke
  v1_rl_003_distribution:
    status: blocked
    required_evidence: Developer ID signed, notarized, stapled formal DMG and clean Mac first launch
  v1_rl_006_feedback_route:
    status: blocked
    required_evidence: tester list, announcement or Discussion, feedback route, and triage owner

final_tag:
  name: v0.1.0
  created: false
  annotated: pending
  command: git tag -a v0.1.0 -m <release message>
  pushed: false
  push_command: git push origin main v0.1.0

formal_release:
  github_release_url: null
  artifact_dmg_path: null
  artifact_dmg_sha256: null
  release_notes_path: null
  notarization_evidence_path: null

readiness_audit:
  command: ./dev release final-tag-readiness-audit --json --remote
  status: BLOCKED
  pre_tag_release_evidence_gate: BLOCKED
  tag_prerequisite_gate: BLOCKED
  ready_to_create_formal_tag: false
  closes_residual: false

does_not_prove:
  - preview tag is a formal release tag
  - unnotarized preview is a formal release artifact
  - release gates are closed
  - final v0.1.0 tag has been pushed
  - formal alpha release readiness
```

## 使用规则

1. 不得在 `v1-rl-002`、`v1-rl-003` 和 `v1-rl-006` 仍为 blocked 时创建正式
   `v0.1.0` tag。
2. `v0.1.0-unnotarized-preview.2` 只能作为可信测试者 preview 证据；不得把它写成正式
   `v0.1.0` tag。
3. 创建 tag 前必须记录 release candidate commit、main 分支 CI 状态、release checklist 放行状态。
4. 创建 tag 后必须记录 annotated tag、push 结果、GitHub Release URL、正式 DMG SHA-256 和 release notes。
5. 只有上述字段全部为真实 `pass` / `created` / `pushed`，并且 release checklist 同步更新后，
   才能把 `closes_residual` 改为 `true`。

## 当前待补证字段

| 字段 | 当前状态 | 关闭所需证据 |
|---|---|---|
| `release_candidate.commit` | `pending` | 正式 release candidate commit 记录。 |
| `required_gates.v1_rl_002_icloud_placeholder.status` | `blocked` | 真实 iCloud placeholder 手工冒烟通过。 |
| `required_gates.v1_rl_003_distribution.status` | `blocked` | Developer ID / notarization / formal DMG / clean Mac 证据齐全。 |
| `required_gates.v1_rl_006_feedback_route.status` | `blocked` | tester / announcement / feedback route / triage owner 决策齐全。 |
| `final_tag.created` | `false` | 创建 annotated `v0.1.0` tag。 |
| `final_tag.pushed` | `false` | `git push origin main v0.1.0` 成功。 |
| `formal_release.github_release_url` | `pending` | 正式 GitHub Release URL。 |
| `formal_release.artifact_dmg_sha256` | `pending` | 正式 notarized DMG checksum。 |

## Related

- [release-checklist.md](release-checklist.md)
- [distribution-signing-notarization.md](distribution-signing-notarization.md)
- [icloud-placeholder-smoke-evidence.md](icloud-placeholder-smoke-evidence.md)
- [alpha-feedback-route.md](alpha-feedback-route.md)
- [v1 release residuals](../residuals/release-evidence.md)
