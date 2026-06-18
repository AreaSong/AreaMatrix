# v1-mvp Closeout Decision

> v1-mvp 的 637-task live queue 已达到技术完成；正式 Stage 1 alpha 分发不放行。本文件记录结案口径，让后续 v* planning 可以开始，但不把发布阻断项伪装成已关闭。

Decision date: 2026-06-17 CST

## Decision Summary

- Technical queue: complete. `workflow/versions/v1-mvp/execution/_shared/progress.json` 记录 `637/637` tasks completed，`./task-loop status` 无 live lock、无 stale in-progress。
- Formal alpha: blocked. `0.1.0-local-qa` 只允许内部 QA，`v0.1.0-unnotarized-preview.2` 只允许可信测试者 prerelease。
- Release blockers: deferred for the formal distribution track, not closed. 它们继续由 `workflow/versions/v1-mvp/evidence/release-checklist.md` 管理。
- Checkpoint gaps: 35 个 historical checkpoint gaps 已接受为 closeout exceptions；不得回填或伪造 `progress.json` / Git history。
- Release-gate entry: `3-1/task-05` 作为 release-gate review item 处置，不补造 task-loop verify evidence。
- Workflow state: `v1-mvp` 已切换为 `lifecycle_status: archived`。工具链仍要求后续版本使用 explicit approval 和 live mapping，不能自动写入 `workflow/versions/v1-mvp/execution/**`。
- Future v* planning: allowed after creating a real version directory from the workflow template, then passing discussion, middle-layer, changes, plans, drafts, and queue candidate gates. Promotion / apply into `workflow/versions/v1-mvp/execution/**` remains blocked until explicit approval and live mapping are configured.

## What This Is Not

- 不是正式 Stage 1 alpha 放行。
- 不是 Developer ID signed / notarized / stapled release evidence。
- 不是干净 Mac 首启证据。
- 不是 iCloud placeholder 真实环境 smoke 证据。
- 不是 live queue 归档、重命名、移动或重新生成。
- 不是对 `progress.json`、task-loop logs、run summaries 或 Git history 的 evidence 回填。

## Deferred Release Blockers

| Blocker | Status | Owner | Resume condition |
|---|---|---|---|
| M-02 iCloud placeholder real-environment smoke | deferred | release QA owner | 有可用 iCloud placeholder 测试环境后，补跑 `workflow/versions/v1-mvp/evidence/recovery-scenarios.md` 和 release checklist 证据。 |
| Developer ID signing | deferred | release owner | 加入 Apple Developer Program，取得 valid Developer ID Application certificate。 |
| Notarization and stapling | deferred | release owner | Developer ID signing 可用后，提交 notarytool，记录 accepted log 和 stapler evidence。 |
| Clean-Mac first launch / Gatekeeper validation | deferred | release owner | 有干净 Mac 或等价可信测试机，使用目标分发产物补首次启动证据。 |
| Formal `v0.1.0` tag and GitHub Release | deferred | release owner | 正式 alpha 门禁全部关闭后再创建；preview tag 不等于正式 release tag。 |
| `3-1/task-05` release-gate review item | deferred | closeout / release reviewer | 回到 release checklist 与 local QA notes，决定是否记录为 release evidence exception 或拆成后续 release task。 |

## Accepted Evidence

- Prompt doctor/status/page audit are the live queue evidence commands.
- `workflow/versions/v1-mvp/closeout/checkpoint-accepted-exceptions.md` accepts the 35 historical checkpoint gaps as closeout exceptions.
- `workflow/versions/v1-mvp/closeout/checkpoint-evidence-index.md` records local PASS log paths and tracked run summaries for those exceptions.
- `workflow/versions/v1-mvp/evidence/release-notes/release-notes-0.1.0.md` records internal local QA only.
- `workflow/versions/v1-mvp/evidence/release-notes/release-notes-v0.1.0-unnotarized-preview.2.md` records trusted-tester prerelease only.

## Allowed Next Steps

- Create a future real version, for example `v2`, with `./dev workflow init --version v2 --write`, then start discussion and planning through the normal workflow gate.
- Produce future-version middle-layer, changes, plans, drafts, and queue candidates for review only after that discussion gate is ready.
- Continue release evidence work on a separate formal distribution track.
- Optionally create an evidence bundle that snapshots accepted local PASS logs, run summaries, prompt manifests, and progress summaries.

## Still Forbidden

- Do not write new future-version work into `workflow/versions/v1-mvp/execution/**` without explicit approval and live mapping.
- Do not regenerate, rename, move, or archive the `workflow/versions/v1-mvp/execution/**` queue as part of this decision pass.
- Do not mark formal alpha released.
- Do not call ad-hoc signed, local QA, unnotarized preview, or same-machine smoke evidence equivalent to notarized distribution evidence.
- Do not rewrite `progress.json` or task-loop evidence to hide checkpoint gaps.
