# v1-mvp Checkpoint Accepted Exceptions

Reviewed at: `2026-06-16T08:54:09Z`

本文件记录 v1 closeout 对 35 个历史 task-loop checkpoint 缺口的正式处置决定。
这些任务视为已完成，但不把缺失的 `git_checkpoint_status` / `git_commit` 回填到 `progress.json`。

## Decision

- Decision: accept 35 historical checkpoint gaps as closeout exceptions.
- Reason: these runs were interrupted / resumed or otherwise executed with `git.checkpoint=off`; task completion evidence exists locally and in tracked run summaries, but per-task Git checkpoint metadata was not produced.
- Scope: checkpoint evidence only. This does not release Stage 1 alpha, does not close release blockers, and does not apply to `3-1/task-05`.
- Guardrail: do not rewrite `workflow/versions/v1-mvp/execution/_shared/progress.json`, task-loop logs, run summaries, or Git history to fabricate checkpoint metadata.

## Acceptance Criteria Used

Each accepted exception below satisfied all of these checks:

- `progress.json` status is `completed`.
- The referenced final copy log exists locally.
- The referenced final verify log exists locally and contains `VERIFY_RESULT: PASS`.
- The matching `workflow/versions/v1-mvp/evidence/task-loop-runs/<run_id>/summary.json` exists and is tracked in Git.
- The tracked run summary records the task as `completed`.
- The tracked run summary records `git.checkpoint=off`, explaining why per-task checkpoint metadata is absent.

## Summary

| Metric | Count |
|---|---:|
| Accepted checkpoint exceptions | 35 |
| Needs review | 0 |
| Release-gate entries excluded | 1 |

## Accepted Exceptions

| Task | Risk | Run | Attempts | Verify | Summary | Disposition |
|---|---|---|---:|---|---|---|
| `1-2/task-16` | Mission-Critical | `20260502_085733` | 3 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `2-1/task-15` | High | `20260504_125337` | 2 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `2-1/task-18` | High | `20260504_190145` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `2-1/task-20` | High | `20260505_222707` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `2-2/task-01` | High | `20260506_111508` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `2-2/task-06` | High | `20260506_174405` | 5 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `2-2/task-08` | High | `20260507_011233` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `2-2/task-17` | High | `20260507_111520` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `2-2/task-21` | High | `20260507_203441` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `2-3/task-34` | High | `20260509_025922` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `3-1/task-02` | Mission-Critical | `20260509_124002` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-1/task-16` | High | `20260515_171239` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-1/task-17` | High | `20260516_123504` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-1/task-117` | High | `20260524_190717` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-1/task-127` | High | `20260525_114004` | 5 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-1/task-134` | High | `20260525_225451` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-1/task-143` | Mission-Critical | `20260527_124638` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-2/task-03` | Mission-Critical | `20260527_153014` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-2/task-06` | High | `20260527_172849` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-2/task-53` | High | `20260529_121328` | 4 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-2/task-60` | High | `20260530_125901` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-2/task-63` | High | `20260531_012005` | 6 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-2/task-74` | High | `20260601_091326` | 4 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-2/task-79` | Mission-Critical | `20260601_223559` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-19` | High | `20260602_164403` | 4 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-95` | Mission-Critical | `20260605_144547` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-111` | High | `20260606_181200` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-114` | High | `20260606_214229` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-117` | High | `20260607_120307` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-122` | High | `20260608_115651` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-126` | High | `20260608_175917` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-147` | High | `20260609_121309` | 2 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-148` | High | `20260609_192932` | 2 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-164` | High | `20260610_222843` | 2 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |
| `4-3/task-165` | Mission-Critical | `20260611_142440` | 1 | `PASS` | tracked, `git.checkpoint=off` | accepted-exception |

## Excluded Release Gate Entry

- `3-1/task-05` remains a release-gate review item. It has no task-loop run id, copy log, verify log, or run summary, and must be handled through the Stage 1 release checklist and local QA notes.

## Remaining Closeout Work

- Keep `archive_readiness` blocked until release blockers are closed or explicitly deferred.
- Decide whether to archive the local copy / verify logs as a separate evidence bundle, or rely on this accepted-exception record plus tracked run summaries.
- Handle `3-1/task-05` through release evidence review.
