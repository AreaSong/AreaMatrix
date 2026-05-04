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
- 每次执行会持有 `.codex/task-loop-lock/` 运行锁，避免两个 runner 同时写 progress/logs。
- 每次执行会写 `.codex/task-loop-runs/<run_id>/summary.json`，作为可上传、可续工的运行摘要。
- 每次执行结束会更新 `.codex/task-loop-runs/index.json`，用于快速查看最近 run 的状态。
- 需要优雅收尾时，可用 `./task-loop drain` 请求 live runner 完成当前 task、Git checkpoint / push 和 summary 后停止，不进入下一个 task。
- progress / stale / lock status / summary 逻辑集中在 `scripts/task_loop/state.py`；Python runner 负责 CLI、调度与 `codex exec`。
- Git checkpoint 逻辑集中在 `scripts/task_loop/git.py`；默认每个 PASS task 自动本地 commit。

默认模型：
- `MODEL=gpt-5.5`
- `MODEL_REASONING_EFFORT=xhigh`

Codex CLI：
- runner 会优先查找 `codex`。
- 如果普通终端没有 `codex`，会自动尝试 `/Applications/Codex.app/Contents/Resources/codex`。
- 如果你安装在其他位置，可以显式设置 `CODEX_BIN=/path/to/codex`。

Repo-local skills：
- copy-ready / verify-ready prompt 会写明 `.codex/skills-src/` 与 `.agents/skills/` 的正确路径。
- 验收 prompt 会内嵌 validation-driver 的关键规则，避免 `codex exec` 自己猜 `/Users/as/.codex/skills-src/...`。

默认 Git checkpoint：
- `GIT_CHECKPOINT=commit`
- `GIT_BRANCH_POLICY=auto`
- `GIT_PUSH_REMOTE=origin`
- `GIT_PUSH_SET_UPSTREAM=1`

正式执行前工作区必须干净。若当前在 `main`，runner 会自动创建 `codex/areamatrix-task-loop-<run_id>` 分支；dry-run 永远不会真实 commit 或 push。

默认重试：
- `MAX_RETRIES=0`（`0` 表示无限重试）

默认风险门禁：
- `RISK_GATE=mission-critical`
- `RISK_POLICY=pause`

也就是说，默认只在 `Mission-Critical` task 前暂停；确认要全静默时，显式使用 `RISK_POLICY=allow`。

`RISK_POLICY=allow` 会向 copy prompt 注入用户已授权的静默执行上下文。High / Mission-Critical task 仍需在日志里说明影响、风险、验证和回滚，但不再停下来等人工确认；若验收指出直接相关的 Exact Docs / Core API / UDL / manifest 漂移，也可以在不触碰 Forbidden Touches 的前提下同步修复。

---

## 二、正式执行（推荐）

日常不需要记忆下面这些长命令时，优先使用根目录控制台：

```bash
./dev
```

控制台默认显示彩色首页：顶部是进度、下一任务、runner / `codex exec` 折叠摘要、stale / drain、最近 run 和 verify；下方是快捷键操作区。
启动或继续任务时，控制台会先阻止重复 live runner，再选择前台/后台、Git checkpoint 模式和任务数量上限；默认 Git 为本地 `commit`，任务数量为无限。
优化或排查控制台时，优先用 `./dev preview` 预览命令，或用 `./dev dry-run` 跑临时目录演练；这两者都不会写真实 progress。

颜色默认强制开启；需要关闭时使用：

```bash
./dev --color never
NO_COLOR=1 ./dev
```

需要在脚本或截图中渲染一次首页后退出：

```bash
./dev --once
```

完整进程命令不在首页展开；需要查看时使用：

```bash
./dev processes
```

日常观看进度时使用：

```bash
./dev status
```

`./dev status` 支持同样的颜色开关，例如 `./dev status --once --color always`。需要旧版长报告、完整进程列表、最近 run 和 verify 摘要时使用：

```bash
./dev status --verbose
```

### 1) 全量执行

```bash
MAX_RETRIES=0 ./task-loop run
```

全静默执行（包括 Mission-Critical task）：

```bash
RISK_POLICY=allow \
MAX_RETRIES=0 \
./task-loop run
```

如果只想临时关闭 Git checkpoint：

```bash
GIT_CHECKPOINT=off \
RISK_POLICY=allow \
MAX_RETRIES=0 \
./task-loop run
```

如果要每个 PASS task commit 后立即上传：

```bash
GIT_CHECKPOINT=push \
RISK_POLICY=allow \
MAX_RETRIES=0 \
./task-loop run
```

### 2) 从指定任务开始

```bash
MAX_RETRIES=0 \
START_FROM=phase-1/1-1-task-01 \
./task-loop run --phase phase-1 --max-tasks 5
```

`START_FROM` 同时支持 `phase-1/1-1-task-01` 和 `1-1/task-01`。

### 3) 只跑某个 phase

```bash
MAX_RETRIES=0 ./task-loop run --phase phase-1 --max-tasks 20
```

> 注意：`--phase` 可重复，形成子集，如 `--phase phase-1 --phase phase-2`。

---

## 三、Dry Run（先预演）

完整 runner 自检：

```bash
./task-loop check
```

该命令使用临时 progress/log/summary/lock 目录验证 dry-run、stale、resume、lock 和 summary index，不会修改真实任务进度。

```bash
DRY_RUN=1 \
MAX_RETRIES=1 \
DRY_RUN_RESULT=PASS \
./task-loop run --phase phase-1 --max-tasks 1
```

### 参数说明

- `DRY_RUN_RESULT`：控制预演时验收结果（PASS / FAIL）
- `DRY_RUN_MAX_ATTEMPTS`：dry-run 下失败时最大重试次数，默认 10
- `DRY_RUN_COPY_PREVIEW_LINES` / `DRY_RUN_VERIFY_PREVIEW_LINES`：日志预览行数

---

## 四、日志与进度

runner 默认在 `.codex/task-loop-logs/<timestamp>/phase/...` 生成日志：

- `*-copy-attempt-<n>.log`：第 n 次 copy 执行日志
- `*-verify-attempt-<n>.log`：第 n 次 verify 日志；最后一行必须是 `VERIFY_RESULT: PASS` 或 `VERIFY_RESULT: FAIL`

verify 日志会保留简明验收报告。失败时脚本从日志尾部提取失败上下文，下一轮 copy 会按“全部全面修复”处理同一 task，不会进入下一个 task。

运行摘要：

```
.codex/task-loop-runs/<run_id>/summary.json
.codex/task-loop-runs/index.json
```

`summary.json` 记录单次运行的参数、任务 attempts、copy/verify log 和最终状态。`index.json` 记录最近运行列表，便于上传或恢复上下文。

Git checkpoint 证据会写入 progress 和 summary：

- `git_checkpoint_status`
- `git_branch`
- `git_commit`
- `git_push_status`
- `git_remote`
- `git_changed_files`

因为最终 commit hash 不能写入定义它自己的同一个 commit，runner 会在 task completion commit 后创建一个小的 evidence commit 来记录该 hash。成功 run 结束时还会提交最终 summary/index 状态。

通过任务的进度会记录到：

```
tasks/prompts/_shared/progress.json
```

旧版 `.codex/task-loop-state.txt` 只作为兼容读取，不再作为主进度源。

查看自动执行状态：

```bash
./task-loop status
```

状态输出会同时显示：

- 当前运行锁是否存在、锁里的 pid 是否仍存活；
- 最新日志目录；
- progress 里的 completed / failed / blocked / in_progress 计数；
- 是否存在 stale in_progress，也就是没有活锁且 verify 未 PASS 的中断残留。
- 是否存在 drain request，也就是已请求当前 runner 在当前 task 完成并 checkpoint 后停止。

优雅收尾当前 live runner：

```bash
./task-loop drain
```

该命令要求当前存在 live runner；它不会启动新任务循环。runner 收到请求后会继续完成当前 task，如果 verify 失败仍会按现有规则 repair retry；只有当前 task `VERIFY_RESULT: PASS`、progress 写入、Git checkpoint / push 和 summary 收口完成后，才以 `drained` 状态退出并保留下一个 pending task 给下次继续。

跑到指定 task 后停止：

```bash
./task-loop run --stop-after 2-1/task-18
```

`--stop-after` 只在目标 task `PASS` 且 Git checkpoint / push 完成后停止，不会跳过验收。
`--start-from` / `--stop-after` 会在 live Git preflight 前校验：目标必须落在当前 `--phase` 选择内，并且 copy-ready 与 verify-ready prompt 都存在。

从第一个失败任务恢复：

```bash
./task-loop resume-failed
```

从第一个 stale in_progress 任务恢复：

```bash
./task-loop resume-stale
```

只清理 stale in_progress，不动 completed / failed / blocked：

```bash
./task-loop clear-stale
```

如果要从头开始，使用内置重置命令。它会先备份当前 progress，再写入空进度；不会删除历史日志：

```bash
./task-loop reset-progress
```

---

## 五、和 prompt runner 的关系

这个 Python runner 是“自动执行器”，不是 prompt 体系本体。
你仍然需要先确保：

- `copy-ready` / `verify-ready` 已经用 `python3 tasks/prompts/_shared/prompt_pipeline.py export --all` 生成；
- 对应任务本身在文档与 manifest 上自洽；
- 阶段通过后再做后续阶段。

---

## 六、后续版本变更追踪

当前 637 个任务仍是 v1-mvp 队列，继续由 `tasks/prompts/**` 与 `tasks/prompts/_shared/progress.json` 驱动，不移动、不重置。

后续新增功能先记录到：

```
workflow/versions/v2/changes/*.yaml
```

第一版只做 tracking + doctor + preview：

```bash
./dev changes doctor
./dev changes preview
```

它会校验 feature id、依赖、精确 docs、同步目标、风险边界和预期 task split，并预览将来的任务顺序；不会生成 copy-ready / verify-ready 文件，也不会接入 live task-loop。
