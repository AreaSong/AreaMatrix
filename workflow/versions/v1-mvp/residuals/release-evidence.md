# v1-mvp Release Evidence Residuals

正式 Stage 1 alpha 发布证据遗留项索引。

阅读时长：约 4 分钟。

---

## 权威来源

- [release-checklist.md](../evidence/release-checklist.md)
- [recovery-scenarios.md](../evidence/recovery-scenarios.md)
- [icloud-placeholder-smoke-evidence.md](../evidence/icloud-placeholder-smoke-evidence.md)
- [release-gate-review-task05.md](../evidence/release-gate-review-task05.md)
- [final-tag-release-evidence.md](../evidence/final-tag-release-evidence.md)
- [alpha-feedback-route.md](../evidence/alpha-feedback-route.md)
- [distribution-signing-notarization.md](../evidence/distribution-signing-notarization.md)
- [release.md](../../../../docs/development/release.md)
- [build.md](../../../../docs/development/build.md)

## 当前 release blockers

| ID | 状态 | 源文件 | 当前影响 | 关闭条件 |
|---|---|---|---|---|
| `v1-rl-002` | `blocked-external` | [release-checklist.md](../evidence/release-checklist.md) / [recovery-scenarios.md](../evidence/recovery-scenarios.md) / [icloud-placeholder-smoke-evidence.md](../evidence/icloud-placeholder-smoke-evidence.md) | formal alpha blocked | 结构化补证字段已存在，但 `closes_residual: false`；真实 iCloud placeholder 环境手工冒烟必须记录 helper metadata、UI `Download & retry`、retry 结果、repo 文件状态、DB row 和用户文件不变量。 |
| `v1-rl-003` | `blocked-external` | [release-checklist.md](../evidence/release-checklist.md) / [distribution-signing-notarization.md](../evidence/distribution-signing-notarization.md) | formal alpha blocked | 结构化补证字段已存在，但 `closes_residual: false`；Developer ID signed app、notarytool accepted log、stapled app / DMG、正式 checksum、spctl assess 和干净 Mac 首启证据齐全后才能关闭。 |
| `v1-rl-004` | `blocked-decision` | [release-checklist.md](../evidence/release-checklist.md) / [final-tag-release-evidence.md](../evidence/final-tag-release-evidence.md) | formal alpha blocked | 结构化 tag record 已存在，但 `closes_residual: false`；正式 release candidate commit、全部发布门禁关闭、annotated `v0.1.0` tag 创建和 push 证据齐全后才能关闭。 |
| `v1-rl-006` | `blocked-decision` | [release-checklist.md](../evidence/release-checklist.md) / [alpha-feedback-route.md](../evidence/alpha-feedback-route.md) | formal alpha blocked | alpha feedback issue template 和 route evidence 已存在，但 `closes_residual: false`；仍需 alpha tester 名单、正式 announcement Discussion / 反馈分流决策、反馈路径和 triage owner 证据。 |

## 非 release blocker

- `0.1.0-local-qa` 是内部 QA 产物，不等于正式 alpha。
- `v0.1.0-unnotarized-preview.2` 可作为可信测试者 GitHub prerelease，不等于正式 alpha。
- 同机 smoke、ad-hoc signing、local QA DMG 不能替代 Developer ID signing、notarization 或 clean Mac evidence。

## Deferred release evidence review

| ID | 状态 | 源文件 | 当前影响 | 关闭条件 |
|---|---|---|---|---|
| `v1-ref-003-1-task-05` | `deferred` | [checkpoint-gaps.md](../closeout/checkpoint-gaps.md) / [release-gate-review-task05.md](../evidence/release-gate-review-task05.md) | formal alpha blocked | 结构化 review record 已存在，但 `closes_residual: false`；只能通过 fresh formal release evidence review 处理，不得补造 task-loop `VERIFY_RESULT: PASS`、progress、summary、checkpoint metadata、commit 或 tag。 |

## 任务转换规则

这些条目默认不是 `tasks/active/**` 任务：

- iCloud placeholder 需要真实环境。
- Developer ID / notarization 需要 Apple Developer Program 与凭证。
- clean Mac 首启需要合适测试机器。
- final tag 需要 release decision。

只有当环境和 owner 明确后，才能人工创建 lightweight task 或 release checklist 更新任务。

## Related

- [residuals.yaml](residuals.yaml)
- [v1-mvp residuals](README.md)
