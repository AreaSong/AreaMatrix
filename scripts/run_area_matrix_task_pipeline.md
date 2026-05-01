# AreaMatrix 任务自动化执行手册

目标：用一个循环把每个 task 的 copy-ready 与 verify-ready 串起来执行，形成：

`copy -> verify -> fail retry -> pass then next task`

---

## 一、执行规则

- copy 阶段：`codex exec` + `workspace-write`，按 `copy-ready` 任务提示执行实现。
- verify 阶段：`codex exec` + `read-only`，按 `verify-ready` 提示做只读验收。
- copy / verify 都会读取工程质量规则和编码规范，验收不只看能否运行，也看代码是否可维护、可测试、可长期演进。
- 验收必须通过（日志里出现 `VERIFY_RESULT: PASS`）才会继续下一任务。
- 失败则会把功能、验证和工程质量失败摘要注入下一次 copy 提示，继续重试修复。
- 进度统一写入 `tasks/prompts/_shared/progress.json`，可直接被 `prompt_pipeline.py status/next` 读取。

默认模型：
- `MODEL=gpt-5.5`
- `MODEL_REASONING_EFFORT=xhigh`

Codex CLI：
- 脚本会优先查找 `codex`。
- 如果普通终端没有 `codex`，会自动尝试 `/Applications/Codex.app/Contents/Resources/codex`。
- 如果你安装在其他位置，可以显式设置 `CODEX_BIN=/path/to/codex`。

默认重试：
- `MAX_RETRIES=0`（`0` 表示无限重试）

默认风险门禁：
- `RISK_GATE=mission-critical`
- `RISK_POLICY=pause`

也就是说，默认只在 `Mission-Critical` task 前暂停；确认要全静默时，显式使用 `RISK_POLICY=allow`。

---

## 二、正式执行（推荐）

### 1) 全量执行

```bash
MAX_RETRIES=0 bash scripts/run_area_matrix_task_pipeline.sh
```

全静默执行（包括 Mission-Critical task）：

```bash
RISK_POLICY=allow \
MAX_RETRIES=0 \
bash scripts/run_area_matrix_task_pipeline.sh
```

### 2) 从指定任务开始

```bash
MAX_RETRIES=0 \
START_FROM=phase-1/1-1-task-01 \
bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1 --max-tasks 5
```

`START_FROM` 同时支持 `phase-1/1-1-task-01` 和 `1-1/task-01`。

### 3) 只跑某个 phase

```bash
MAX_RETRIES=0 bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1 --max-tasks 20
```

> 注意：`--phase` 可重复，形成子集，如 `--phase phase-1 --phase phase-2`。

---

## 三、Dry Run（先预演）

```bash
DRY_RUN=1 \
MAX_RETRIES=1 \
DRY_RUN_RESULT=PASS \
bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1 --max-tasks 1
```

### 参数说明

- `DRY_RUN_RESULT`：控制预演时验收结果（PASS / FAIL）
- `DRY_RUN_MAX_ATTEMPTS`：dry-run 下失败时最大重试次数，默认 10
- `DRY_RUN_COPY_PREVIEW_LINES` / `DRY_RUN_VERIFY_PREVIEW_LINES`：日志预览行数

---

## 四、日志与进度

脚本默认在 `.codex/task-loop-logs/<timestamp>/phase/...` 生成日志：

- `*-copy-attempt-<n>.log`：第 n 次 copy 执行日志
- `*-verify-attempt-<n>.log`：第 n 次 verify 日志；最后一行必须是 `VERIFY_RESULT: PASS` 或 `VERIFY_RESULT: FAIL`

verify 日志会保留简明验收报告。失败时脚本从日志尾部提取失败上下文，下一轮 copy 会按“全部全面修复”处理同一 task，不会进入下一个 task。

通过任务的进度会记录到：

```
tasks/prompts/_shared/progress.json
```

旧版 `.codex/task-loop-state.txt` 只作为兼容读取，不再作为主进度源。

查看自动执行状态：

```bash
bash scripts/run_area_matrix_task_pipeline.sh --status
```

从第一个失败任务恢复：

```bash
bash scripts/run_area_matrix_task_pipeline.sh --resume-failed
```

如果要从头开始，可以先把对应 task 进度改回 pending，或在确认不需要历史进度时清理进度文件：

```bash
rm -f tasks/prompts/_shared/progress.json
```

---

## 五、和 prompt runner 的关系

这个脚本是“自动执行器”，不是 prompt 体系本体。
你仍然需要先确保：

- `copy-ready` / `verify-ready` 已经用 `python3 tasks/prompts/_shared/prompt_pipeline.py export --all` 生成；
- 对应任务本身在文档与 manifest 上自洽；
- 阶段通过后再做后续阶段。
