# AreaMatrix Prompt 任务库

> 目标：以 `docs/` 为 SSOT，把 AreaMatrix 从文档态推进到可执行实现态。

共享规则：[./_shared/audit-rules.md](./_shared/audit-rules.md)  
任务切片规则：[./_shared/task-slicing-rules.md](./_shared/task-slicing-rules.md)  
工程质量规则：[./_shared/engineering-quality-rules.md](./_shared/engineering-quality-rules.md)
依赖图：[./_shared/dependency-graph.md](./_shared/dependency-graph.md)  
Manifest：[./_shared/manifests/](./_shared/manifests/)
执行模式说明：[./_shared/copy-ready/README.md](./_shared/copy-ready/README.md)  
验收模式说明：[./_shared/verify-ready/README.md](./_shared/verify-ready/README.md)

## 执行基线

1. 任务文件定义目标、范围、核对清单和完成标准。
2. Manifest 定义精确文档、现有代码、预期新增路径、禁止触碰路径、风险等级和验证命令。
3. 已存在 capability specs 的 task 必须绑定 UX 页面或 Core 能力，并交叉读取 capability specs 与对应 control map。
4. AreaMatrix 当前是 greenfield build：`Expected New Paths` 可以是尚不存在但允许创建的路径。
5. 执行任务前先运行 `doctor`，再用 `render --mode copy` 生成可复制执行 prompt。
6. 执行与验收都必须应用 `engineering-quality-rules.md` 和 `docs/development/coding-standards.md`。
7. 任务完成后用 `render --mode verify` 或 `verify` 生成只读验收 prompt。
8. 需要批量复制时，用 `export --phase` 或 `export --all` 把 copy-ready / verify-ready prompt 导出为静态文件。
9. Runner 只负责 prompt 生成、进度和状态管理；自动闭环由 `scripts/run_area_matrix_task_pipeline.sh` 调用 `codex exec`。

## Runner

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
python3 tasks/prompts/_shared/prompt_pipeline.py audit --pages
python3 tasks/prompts/_shared/prompt_pipeline.py plan --phase phase-0
python3 tasks/prompts/_shared/prompt_pipeline.py plan --all
python3 tasks/prompts/_shared/prompt_pipeline.py next
python3 tasks/prompts/_shared/prompt_pipeline.py render --task 0-1/task-01
python3 tasks/prompts/_shared/prompt_pipeline.py render --task 0-1/task-01 --mode verify
python3 tasks/prompts/_shared/prompt_pipeline.py verify --task 0-1/task-01
python3 tasks/prompts/_shared/prompt_pipeline.py verify --phase phase-0
python3 tasks/prompts/_shared/prompt_pipeline.py export --phase phase-0
python3 tasks/prompts/_shared/prompt_pipeline.py export --all
python3 tasks/prompts/_shared/prompt_pipeline.py mark --task 0-1/task-01 --status completed
python3 tasks/prompts/_shared/prompt_pipeline.py status
```

## Prompt 模式

| 模式 | 命令 | 用途 |
|---|---|---|
| copy-ready | `render --task <label>` | 开始执行任务，可以修改文件 |
| verify-ready | `render --task <label> --mode verify` | 验收任务是否完成，禁止修改文件 |
| verify-ready | `verify --task <label>` | 上一条的简写 |
| export | `export --phase <phase>` | 导出某个 phase 的 copy-ready / verify-ready 静态文件 |
| export | `export --all` | 导出 Phase 0-4 全套静态 prompt 文件 |
| phase-verify | `verify --phase <phase>` | 阶段验收，任一 task 不通过则阶段不通过 |
| page-audit | `audit --pages` | 审计每个页面的 control map 期望能力与 prompt 覆盖能力是否一致 |

## 静态 Prompt 文件

`render` / `verify` 会把 prompt 输出到终端；`export` 会把同一份内容写入文件，方便直接复制给 Codex。

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py export --all
```

导出位置：

```text
tasks/prompts/_shared/copy-ready/phase-0..phase-4/*.md
tasks/prompts/_shared/verify-ready/phase-0..phase-4/*.md
```

文件命名规则：

```text
1-1/task-01 -> 1-1-task-01.md
4-3/task-165 -> 4-3-task-165.md
```

后续 task、manifest 或共享规则变化后，重新运行 `export --all` 刷新静态 prompt 文件。

## 进度记录

Runner 默认不自动执行任务，也不会自动判断完成。需要人工记录进度时使用：

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py mark --task 0-1/task-01 --status in_progress
python3 tasks/prompts/_shared/prompt_pipeline.py mark --task 0-1/task-01 --status completed
```

进度写入本地文件 `tasks/prompts/_shared/progress.json`，默认不提交。`next` 和 `status` 会读取这个文件来判断下一个可执行任务。

## 自动化执行脚本（可选）

仓库提供 `scripts/run_area_matrix_task_pipeline.sh`，可将 copy-ready + verify-ready 做成闭环执行：

1. 读取 copy-ready 并调用 `codex exec` 执行。
2. 再读取 verify-ready 进行只读验收。
3. 验收失败时，自动把失败摘要注入到下一次 copy prompt，然后重试。
4. 验收失败摘要会保留功能、验证和工程质量阻塞点，下一轮按“全部全面修复”处理。
5. 只有验收通过才进入下一任务。

默认模型与推理强度：

```bash
MODEL=gpt-5.5
MODEL_REASONING_EFFORT=xhigh
```

Codex CLI 查找顺序：

1. 当前 shell 的 `codex`
2. Codex.app 内置 CLI：`/Applications/Codex.app/Contents/Resources/codex`
3. 显式环境变量：`CODEX_BIN=/path/to/codex`

默认风险门禁：

```bash
RISK_GATE=mission-critical
RISK_POLICY=pause
```

默认只在 `Mission-Critical` task 前暂停；确认需要全静默执行时，显式设置 `RISK_POLICY=allow`。

基本用法（全量执行）：

```bash
MAX_RETRIES=0 bash scripts/run_area_matrix_task_pipeline.sh
```

全静默执行：

```bash
RISK_POLICY=allow \
  MAX_RETRIES=0 \
  bash scripts/run_area_matrix_task_pipeline.sh
```

只执行某个起点和阶段，便于试跑：

```bash
MAX_RETRIES=0 \
  START_FROM=phase-1/1-1-task-01 \
  bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1 --max-tasks 5
```

Dry-run（预演，不改文件）：

```bash
DRY_RUN=1 \
  MAX_RETRIES=1 \
  DRY_RUN_RESULT=PASS \
  bash scripts/run_area_matrix_task_pipeline.sh --phase phase-1 --max-tasks 1
```

脚本会在 `.codex/task-loop-logs/<timestamp>/<phase>/` 写入每次执行和验收日志。
进度统一写入 `tasks/prompts/_shared/progress.json`，因此 `next` 和 `status` 会直接反映自动执行结果。

查看或恢复：

```bash
bash scripts/run_area_matrix_task_pipeline.sh --status
bash scripts/run_area_matrix_task_pipeline.sh --resume-failed
```

## Phase 概览

| Phase | 目标 |
|---|---|
| Phase 0 | 治理、prompt runner、工程骨架、CI、Rust crate、UDL、Xcode 空壳 |
| Phase 1 | Stage 1 MVP Core 原子任务：每个 C1 拆为 contract / implementation / failure / validation / integration verify |
| Phase 2 | Stage 1 MVP macOS 页面功能任务：S1 多能力页面拆为 S1+C1 page-feature，并保留 page / 闭环 integration verify |
| Phase 3 | Stage 1 稳定、测试、发布准备 |
| Phase 4 | Stage 2-4 全量精细化任务：C2/C3/C4 每个能力拆 5 步，S2/S3/S4 多能力页面拆为 S+C page-feature，并保留 page / stage integration verify |

## 推荐执行顺序

1. 先执行 Phase 0，确保工程骨架和验证脚本存在。
2. 再执行 Phase 1，跑通 Rust core 与 UniFFI。
3. 再执行 Phase 2，完成 macOS 端到端闭环。
4. 再执行 Phase 3，做稳定性和发布准备。
5. Phase 4 按 `4-1`、`4-2`、`4-3` 串行推进：每段先完成 C2/C3/C4 Core 五步任务，再执行 S2/S3/S4 page-feature task 和 page integration verify，最后跑阶段 integration verify。
