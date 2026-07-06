# v1-mvp Checkpoint Gap Review

本文件记录 `workflow/versions/v1-mvp/execution/_shared/progress.json` 中已完成但缺少 committed Git checkpoint metadata 的条目。
它只做收口审计，不修改 `progress.json`、task-loop logs、run summaries 或 Git 历史。

## Summary

| Metric | Count |
|---|---:|
| Total checkpoint gaps | 36 |
| Reviewed entries | 36 |
| Recoverable local `VERIFY_RESULT: PASS` evidence | 35 |
| Tracked run summary exists | 35 |
| Run summary shows `git.checkpoint=off` | 35 |
| Tracked `3-1/task-05` incomplete summaries excluded from PASS evidence | 5 |
| Copy / verify logs tracked in Git | 0 |
| Local QA / release gate sync without verify log | 1 |
| High risk | 28 |
| Mission-Critical risk | 7 |
| Unspecified risk | 1 |

## Evidence Review Result

- `accepted-exception / runner-checkpoint-off`: 35 entries.
  - `progress.json` marks the task `completed`.
  - The referenced local copy log exists.
  - The referenced local verify log exists and contains `VERIFY_RESULT: PASS`.
  - The matching `workflow/versions/v1-mvp/evidence/task-loop-runs/<run_id>/summary.json` exists and is tracked in Git.
  - The run summary records `git.checkpoint=off`, so the missing per-task checkpoint fields are a historical runner mode / evidence-policy gap, not evidence that the task failed.
  - The copy / verify logs themselves are not tracked in Git, so these entries still need an archive evidence bundle or an explicitly accepted closeout exception before v1 archive can be considered complete.
- `release-gate-review`: 1 entry.
  - `3-1/task-05` has a completed local QA / release gate sync note but no completed task-loop run id, copy log, verify log, or completed run summary.
  - Existing tracked task-loop summaries for `3-1/task-05` are incomplete attempts: the run status is `failed` or `running`, the task remains `in_progress`, and the referenced `.codex/task-loop-logs/**` copy / verify logs are not available as archived evidence.
  - A tracked `summary.json` with `status=running`, task `in_progress`, and missing copy / verify logs must not be counted as `VERIFY_RESULT: PASS` evidence and must not close any release evidence blocker.
  - `3-1/task-05` must be handled through `workflow/versions/v1-mvp/evidence/release-checklist.md` and `workflow/versions/v1-mvp/evidence/release-notes/release-notes-0.1.0.md`.
- `accepted-exception`: 35 entries, recorded in `workflow/versions/v1-mvp/closeout/checkpoint-accepted-exceptions.md`.
- `unrecoverable`: 0 entries found during this review.

## Disposition Rules

- 不手写或回填 `git_checkpoint_status` / `git_commit`，避免伪造 evidence。
- 不把本地未跟踪 copy / verify logs 描述成 committed checkpoint evidence。
- 不把 tracked 但仍为 `status=running` / task `in_progress` 且 copy / verify logs 缺失的 `summary.json` 描述成 `VERIFY_RESULT: PASS`。
- 35 个 `recoverable-evidence` 条目已作为 accepted closeout exceptions 处置，详见 `checkpoint-accepted-exceptions.md` 和 `checkpoint-evidence-index.md`。
- `3-1/task-05` 不进入 task-loop checkpoint exception；它属于 release gate evidence 处置。
- `archive_readiness` 现已在 `version.yaml` 和 `closeout.yaml` 记录为 `evidence-bundle-ready`；formal alpha release 仍由 release blockers 单独阻断。

## Gap Table

| Task | Risk | Run | Evidence review | Missing checkpoint cause | Disposition |
|---|---|---|---|---|---|
| `1-2/task-16` | Mission-Critical | `20260502_085733` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `2-1/task-15` | High | `20260504_125337` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `2-1/task-18` | High | `20260504_190145` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `2-1/task-20` | High | `20260505_222707` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `2-2/task-01` | High | `20260506_111508` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `2-2/task-06` | High | `20260506_174405` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `2-2/task-08` | High | `20260507_011233` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `2-2/task-17` | High | `20260507_111520` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `2-2/task-21` | High | `20260507_203441` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `2-3/task-34` | High | `20260509_025922` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `3-1/task-02` | Mission-Critical | `20260509_124002` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `3-1/task-05` | Unspecified | tracked incomplete summaries only | local QA / release gate sync note; tracked summaries are `failed` / `running` with task `in_progress` | no completed task-loop PASS evidence; referenced logs unavailable | release-gate-review |
| `4-1/task-16` | High | `20260515_171239` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-1/task-17` | High | `20260516_123504` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-1/task-117` | High | `20260524_190717` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-1/task-127` | High | `20260525_114004` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-1/task-134` | High | `20260525_225451` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-1/task-143` | Mission-Critical | `20260527_124638` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-2/task-03` | Mission-Critical | `20260527_153014` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-2/task-06` | High | `20260527_172849` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-2/task-53` | High | `20260529_121328` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-2/task-60` | High | `20260530_125901` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-2/task-63` | High | `20260531_012005` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-2/task-74` | High | `20260601_091326` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-2/task-79` | Mission-Critical | `20260601_223559` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-19` | High | `20260602_164403` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-95` | Mission-Critical | `20260605_144547` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-111` | High | `20260606_181200` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-114` | High | `20260606_214229` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-117` | High | `20260607_120307` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-122` | High | `20260608_115651` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-126` | High | `20260608_175917` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-147` | High | `20260609_121309` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-148` | High | `20260609_192932` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-164` | High | `20260610_222843` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |
| `4-3/task-165` | Mission-Critical | `20260611_142440` | local PASS log + tracked run summary | `git.checkpoint=off`; logs untracked | accepted-exception / runner-checkpoint-off |

## Next Review

1. `3-1/task-05` 已确定走 release evidence review：以 `workflow/versions/v1-mvp/evidence/release-checklist.md` 和 `workflow/versions/v1-mvp/evidence/release-notes/release-notes-0.1.0.md` 为处置来源；tracked 但 `status=running` / task `in_progress` 且 copy / verify logs 缺失的 `summary.json` 不算 `VERIFY_RESULT: PASS`，也不能关闭 release evidence blocker。
2. 决定是否复制本地 copy / verify logs 到长期 archive evidence bundle；当前索引已列出全部路径。
3. 不因 evidence bundle ready 而放行 formal alpha；release gate review 和 release blockers 仍属于 formal distribution track。
