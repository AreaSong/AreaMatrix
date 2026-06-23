# v1-mvp Release Evidence Residuals

正式 Stage 1 alpha 发布证据遗留项索引。

阅读时长：约 4 分钟。

---

## 权威来源

- [release-checklist.md](../evidence/release-checklist.md)
- [recovery-scenarios.md](../evidence/recovery-scenarios.md)
- [release.md](../../../../docs/development/release.md)
- [build.md](../../../../docs/development/build.md)

## 当前 release blockers

| ID | 状态 | 源文件 | 当前影响 | 关闭条件 |
|---|---|---|---|---|
| `v1-rl-002` | `blocked-external` | [release-checklist.md](../evidence/release-checklist.md) / [recovery-scenarios.md](../evidence/recovery-scenarios.md) | formal alpha blocked | 真实 iCloud placeholder 环境手工冒烟证据写入 release checklist。 |
| `v1-rl-003` | `blocked-external` | [release-checklist.md](../evidence/release-checklist.md) | formal alpha blocked | Developer ID signed app、notarytool accepted log、stapled DMG、正式 checksum、干净 Mac 首启证据齐全。 |
| `v1-rl-004` | `blocked-decision` | [release-checklist.md](../evidence/release-checklist.md) | formal alpha blocked | 正式 release candidate commit 和全部发布门禁关闭后创建并推送 `v0.1.0` tag。 |
| `v1-rl-006` | `blocked-decision` | [release-checklist.md](../evidence/release-checklist.md) | formal alpha blocked | alpha tester 名单、GitHub Discussions 或 issue template 入口、反馈路径写入证据。 |

## 非 release blocker

- `0.1.0-local-qa` 是内部 QA 产物，不等于正式 alpha。
- `v0.1.0-unnotarized-preview.2` 可作为可信测试者 GitHub prerelease，不等于正式 alpha。
- 同机 smoke、ad-hoc signing、local QA DMG 不能替代 Developer ID signing、notarization 或 clean Mac evidence。

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
