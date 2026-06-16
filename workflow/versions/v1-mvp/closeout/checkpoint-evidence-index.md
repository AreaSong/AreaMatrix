# v1-mvp Checkpoint Evidence Index

Generated at: `2026-06-16T08:54:09Z`

本索引列出 35 个 accepted checkpoint exception 对应的 evidence 路径。
路径指向当前仓库工作区中的证据；本文件不复制日志内容，也不修改历史 progress / logs / summaries。

## Evidence Guarantees

- 每条 `verify_log` 在生成索引时均存在并包含 `VERIFY_RESULT: PASS`。
- 每条 `summary` 在生成索引时均存在并已由 Git 跟踪。
- 每条 `summary` 的 `git.checkpoint` 为 `off`。
- `copy_log` 和 `verify_log` 是本地日志路径，不是 Git-tracked checkpoint evidence。

## Index

| Task | Run | Copy log | Verify log | Summary | Verify result | Disposition |
|---|---|---|---|---|---|---|
| `1-2/task-16` | `20260502_085733` | `.codex/task-loop-logs/20260502_085733/phase-1/1-2-task-16-copy-attempt-3.log` | `.codex/task-loop-logs/20260502_085733/phase-1/1-2-task-16-verify-attempt-3.log` | `.codex/task-loop-runs/20260502_085733/summary.json` | `PASS` | accepted-exception |
| `2-1/task-15` | `20260504_125337` | `.codex/task-loop-logs/20260504_125337/phase-2/2-1-task-15-copy-attempt-2.log` | `.codex/task-loop-logs/20260504_125337/phase-2/2-1-task-15-verify-attempt-2.log` | `.codex/task-loop-runs/20260504_125337/summary.json` | `PASS` | accepted-exception |
| `2-1/task-18` | `20260504_190145` | `.codex/task-loop-logs/20260504_190145/phase-2/2-1-task-18-copy-attempt-1.log` | `.codex/task-loop-logs/20260504_190145/phase-2/2-1-task-18-verify-attempt-1.log` | `.codex/task-loop-runs/20260504_190145/summary.json` | `PASS` | accepted-exception |
| `2-1/task-20` | `20260505_222707` | `.codex/task-loop-logs/20260505_222707/phase-2/2-1-task-20-copy-attempt-1.log` | `.codex/task-loop-logs/20260505_222707/phase-2/2-1-task-20-verify-attempt-1.log` | `.codex/task-loop-runs/20260505_222707/summary.json` | `PASS` | accepted-exception |
| `2-2/task-01` | `20260506_111508` | `.codex/task-loop-logs/20260506_111508/phase-2/2-2-task-01-copy-attempt-1.log` | `.codex/task-loop-logs/20260506_111508/phase-2/2-2-task-01-verify-attempt-1.log` | `.codex/task-loop-runs/20260506_111508/summary.json` | `PASS` | accepted-exception |
| `2-2/task-06` | `20260506_174405` | `.codex/task-loop-logs/20260506_174405/phase-2/2-2-task-06-copy-attempt-5.log` | `.codex/task-loop-logs/20260506_174405/phase-2/2-2-task-06-verify-attempt-5.log` | `.codex/task-loop-runs/20260506_174405/summary.json` | `PASS` | accepted-exception |
| `2-2/task-08` | `20260507_011233` | `.codex/task-loop-logs/20260507_011233/phase-2/2-2-task-08-copy-attempt-1.log` | `.codex/task-loop-logs/20260507_011233/phase-2/2-2-task-08-verify-attempt-1.log` | `.codex/task-loop-runs/20260507_011233/summary.json` | `PASS` | accepted-exception |
| `2-2/task-17` | `20260507_111520` | `.codex/task-loop-logs/20260507_111520/phase-2/2-2-task-17-copy-attempt-1.log` | `.codex/task-loop-logs/20260507_111520/phase-2/2-2-task-17-verify-attempt-1.log` | `.codex/task-loop-runs/20260507_111520/summary.json` | `PASS` | accepted-exception |
| `2-2/task-21` | `20260507_203441` | `.codex/task-loop-logs/20260507_203441/phase-2/2-2-task-21-copy-attempt-1.log` | `.codex/task-loop-logs/20260507_203441/phase-2/2-2-task-21-verify-attempt-1.log` | `.codex/task-loop-runs/20260507_203441/summary.json` | `PASS` | accepted-exception |
| `2-3/task-34` | `20260509_025922` | `.codex/task-loop-logs/20260509_025922/phase-2/2-3-task-34-copy-attempt-1.log` | `.codex/task-loop-logs/20260509_025922/phase-2/2-3-task-34-verify-attempt-1.log` | `.codex/task-loop-runs/20260509_025922/summary.json` | `PASS` | accepted-exception |
| `3-1/task-02` | `20260509_124002` | `.codex/task-loop-logs/20260509_124002/phase-3/3-1-task-02-copy-attempt-1.log` | `.codex/task-loop-logs/20260509_124002/phase-3/3-1-task-02-verify-attempt-1.log` | `.codex/task-loop-runs/20260509_124002/summary.json` | `PASS` | accepted-exception |
| `4-1/task-16` | `20260515_171239` | `.codex/task-loop-logs/20260515_171239/phase-4/4-1-task-16-copy-attempt-1.log` | `.codex/task-loop-logs/20260515_171239/phase-4/4-1-task-16-verify-attempt-1.log` | `.codex/task-loop-runs/20260515_171239/summary.json` | `PASS` | accepted-exception |
| `4-1/task-17` | `20260516_123504` | `.codex/task-loop-logs/20260516_123504/phase-4/4-1-task-17-copy-attempt-1.log` | `.codex/task-loop-logs/20260516_123504/phase-4/4-1-task-17-verify-attempt-1.log` | `.codex/task-loop-runs/20260516_123504/summary.json` | `PASS` | accepted-exception |
| `4-1/task-117` | `20260524_190717` | `.codex/task-loop-logs/20260524_190717/phase-4/4-1-task-117-copy-attempt-1.log` | `.codex/task-loop-logs/20260524_190717/phase-4/4-1-task-117-verify-attempt-1.log` | `.codex/task-loop-runs/20260524_190717/summary.json` | `PASS` | accepted-exception |
| `4-1/task-127` | `20260525_114004` | `.codex/task-loop-logs/20260525_114004/phase-4/4-1-task-127-copy-attempt-5.log` | `.codex/task-loop-logs/20260525_114004/phase-4/4-1-task-127-verify-attempt-5.log` | `.codex/task-loop-runs/20260525_114004/summary.json` | `PASS` | accepted-exception |
| `4-1/task-134` | `20260525_225451` | `.codex/task-loop-logs/20260525_225451/phase-4/4-1-task-134-copy-attempt-1.log` | `.codex/task-loop-logs/20260525_225451/phase-4/4-1-task-134-verify-attempt-1.log` | `.codex/task-loop-runs/20260525_225451/summary.json` | `PASS` | accepted-exception |
| `4-1/task-143` | `20260527_124638` | `.codex/task-loop-logs/20260527_124638/phase-4/4-1-task-143-copy-attempt-1.log` | `.codex/task-loop-logs/20260527_124638/phase-4/4-1-task-143-verify-attempt-1.log` | `.codex/task-loop-runs/20260527_124638/summary.json` | `PASS` | accepted-exception |
| `4-2/task-03` | `20260527_153014` | `.codex/task-loop-logs/20260527_153014/phase-4/4-2-task-03-copy-attempt-1.log` | `.codex/task-loop-logs/20260527_153014/phase-4/4-2-task-03-verify-attempt-1.log` | `.codex/task-loop-runs/20260527_153014/summary.json` | `PASS` | accepted-exception |
| `4-2/task-06` | `20260527_172849` | `.codex/task-loop-logs/20260527_172849/phase-4/4-2-task-06-copy-attempt-1.log` | `.codex/task-loop-logs/20260527_172849/phase-4/4-2-task-06-verify-attempt-1.log` | `.codex/task-loop-runs/20260527_172849/summary.json` | `PASS` | accepted-exception |
| `4-2/task-53` | `20260529_121328` | `.codex/task-loop-logs/20260529_121328/phase-4/4-2-task-53-copy-attempt-4.log` | `.codex/task-loop-logs/20260529_121328/phase-4/4-2-task-53-verify-attempt-4.log` | `.codex/task-loop-runs/20260529_121328/summary.json` | `PASS` | accepted-exception |
| `4-2/task-60` | `20260530_125901` | `.codex/task-loop-logs/20260530_125901/phase-4/4-2-task-60-copy-attempt-1.log` | `.codex/task-loop-logs/20260530_125901/phase-4/4-2-task-60-verify-attempt-1.log` | `.codex/task-loop-runs/20260530_125901/summary.json` | `PASS` | accepted-exception |
| `4-2/task-63` | `20260531_012005` | `.codex/task-loop-logs/20260531_012005/phase-4/4-2-task-63-copy-attempt-6.log` | `.codex/task-loop-logs/20260531_012005/phase-4/4-2-task-63-verify-attempt-6.log` | `.codex/task-loop-runs/20260531_012005/summary.json` | `PASS` | accepted-exception |
| `4-2/task-74` | `20260601_091326` | `.codex/task-loop-logs/20260601_091326/phase-4/4-2-task-74-copy-attempt-4.log` | `.codex/task-loop-logs/20260601_091326/phase-4/4-2-task-74-verify-attempt-4.log` | `.codex/task-loop-runs/20260601_091326/summary.json` | `PASS` | accepted-exception |
| `4-2/task-79` | `20260601_223559` | `.codex/task-loop-logs/20260601_223559/phase-4/4-2-task-79-copy-attempt-1.log` | `.codex/task-loop-logs/20260601_223559/phase-4/4-2-task-79-verify-attempt-1.log` | `.codex/task-loop-runs/20260601_223559/summary.json` | `PASS` | accepted-exception |
| `4-3/task-19` | `20260602_164403` | `.codex/task-loop-logs/20260602_164403/phase-4/4-3-task-19-copy-attempt-4.log` | `.codex/task-loop-logs/20260602_164403/phase-4/4-3-task-19-verify-attempt-4.log` | `.codex/task-loop-runs/20260602_164403/summary.json` | `PASS` | accepted-exception |
| `4-3/task-95` | `20260605_144547` | `.codex/task-loop-logs/20260605_144547/phase-4/4-3-task-95-copy-attempt-1.log` | `.codex/task-loop-logs/20260605_144547/phase-4/4-3-task-95-verify-attempt-1.log` | `.codex/task-loop-runs/20260605_144547/summary.json` | `PASS` | accepted-exception |
| `4-3/task-111` | `20260606_181200` | `.codex/task-loop-logs/20260606_181200/phase-4/4-3-task-111-copy-attempt-1.log` | `.codex/task-loop-logs/20260606_181200/phase-4/4-3-task-111-verify-attempt-1.log` | `.codex/task-loop-runs/20260606_181200/summary.json` | `PASS` | accepted-exception |
| `4-3/task-114` | `20260606_214229` | `.codex/task-loop-logs/20260606_214229/phase-4/4-3-task-114-copy-attempt-1.log` | `.codex/task-loop-logs/20260606_214229/phase-4/4-3-task-114-verify-attempt-1.log` | `.codex/task-loop-runs/20260606_214229/summary.json` | `PASS` | accepted-exception |
| `4-3/task-117` | `20260607_120307` | `.codex/task-loop-logs/20260607_120307/phase-4/4-3-task-117-copy-attempt-1.log` | `.codex/task-loop-logs/20260607_120307/phase-4/4-3-task-117-verify-attempt-1.log` | `.codex/task-loop-runs/20260607_120307/summary.json` | `PASS` | accepted-exception |
| `4-3/task-122` | `20260608_115651` | `.codex/task-loop-logs/20260608_115651/phase-4/4-3-task-122-copy-attempt-1.log` | `.codex/task-loop-logs/20260608_115651/phase-4/4-3-task-122-verify-attempt-1.log` | `.codex/task-loop-runs/20260608_115651/summary.json` | `PASS` | accepted-exception |
| `4-3/task-126` | `20260608_175917` | `.codex/task-loop-logs/20260608_175917/phase-4/4-3-task-126-copy-attempt-1.log` | `.codex/task-loop-logs/20260608_175917/phase-4/4-3-task-126-verify-attempt-1.log` | `.codex/task-loop-runs/20260608_175917/summary.json` | `PASS` | accepted-exception |
| `4-3/task-147` | `20260609_121309` | `.codex/task-loop-logs/20260609_121309/phase-4/4-3-task-147-copy-attempt-2.log` | `.codex/task-loop-logs/20260609_121309/phase-4/4-3-task-147-verify-attempt-2.log` | `.codex/task-loop-runs/20260609_121309/summary.json` | `PASS` | accepted-exception |
| `4-3/task-148` | `20260609_192932` | `.codex/task-loop-logs/20260609_192932/phase-4/4-3-task-148-copy-attempt-2.log` | `.codex/task-loop-logs/20260609_192932/phase-4/4-3-task-148-verify-attempt-2.log` | `.codex/task-loop-runs/20260609_192932/summary.json` | `PASS` | accepted-exception |
| `4-3/task-164` | `20260610_222843` | `.codex/task-loop-logs/20260610_222843/phase-4/4-3-task-164-copy-attempt-2.log` | `.codex/task-loop-logs/20260610_222843/phase-4/4-3-task-164-verify-attempt-2.log` | `.codex/task-loop-runs/20260610_222843/summary.json` | `PASS` | accepted-exception |
| `4-3/task-165` | `20260611_142440` | `.codex/task-loop-logs/20260611_142440/phase-4/4-3-task-165-copy-attempt-1.log` | `.codex/task-loop-logs/20260611_142440/phase-4/4-3-task-165-verify-attempt-1.log` | `.codex/task-loop-runs/20260611_142440/summary.json` | `PASS` | accepted-exception |

## Release Gate Entry

| Task | Evidence | Disposition |
|---|---|---|
| `3-1/task-05` | `progress.json` local QA / release gate sync note only | release-gate-review |
