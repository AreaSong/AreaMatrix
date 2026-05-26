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
9. Runner 只负责 prompt 生成、进度和状态管理；自动闭环由 `./task-loop run` 调用 `codex exec`。
10. 当前 637 个任务是 `v1-mvp` live queue；大型新增需求先进入 `workflow/versions/v*/` 规划链路，通过 workflow doctor、changes、plans、drafts、queue 和 promotion preview 检查，不直接改 live queue。
11. 新 v* 版本在生成执行 / 检查 prompt 之前，必须先完成 `workflow/versions/v*/discussion/` 的 docs 讨论与中间层讨论门禁；`v-template` 只是模板验收实例，v1 继续在本目录 live 执行，完成后再归档到 workflow。

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

## 自动化执行 Runner（可选）

仓库提供 `./task-loop run`，可将 copy-ready + verify-ready 做成闭环执行：

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

Repo-local skills：

- 源事实目录：`.codex/skills-src/`
- 发现入口：`.agents/skills/`
- copy-ready / verify-ready prompt 会显式写出正确 skill 路径，并内嵌 validation-driver 的关键规则，避免 `codex exec` 误读 `/Users/as/.codex/skills-src/...`。

默认风险门禁：

```bash
RISK_GATE=mission-critical
RISK_POLICY=pause
```

默认只在 `Mission-Critical` task 前暂停；确认需要全静默执行时，显式设置 `RISK_POLICY=allow`。

`RISK_POLICY=allow` 会向 copy prompt 注入静默授权：High / Mission-Critical task 仍需记录影响、风险、验证和回滚，但不再停下来等人工确认；若验收指出直接相关的 Exact Docs / Core API / UDL / manifest 漂移，也可以在不触碰 Forbidden Touches 的前提下同步修复。

基本用法（全量执行）：

```bash
MAX_RETRIES=1 ./task-loop run
```

全静默执行：

```bash
RISK_POLICY=allow \
  MAX_RETRIES=1 \
  ./task-loop run
```

只执行某个起点和阶段，便于试跑：

```bash
MAX_RETRIES=1 \
  START_FROM=phase-1/1-1-task-01 \
  ./task-loop run --phase phase-1 --max-tasks 5
```

`MAX_RETRIES=0` 仍表示无限重试，只在明确要长期无人值守时显式使用；普通任务默认一次 repair retry 后停下。

Dry-run（预演，不改文件）：

```bash
DRY_RUN=1 \
  MAX_RETRIES=1 \
  DRY_RUN_RESULT=PASS \
  ./task-loop run --phase phase-1 --max-tasks 1
```

Python runner 会在 `.codex/task-loop-logs/<timestamp>/<phase>/` 写入每次执行和验收日志。最终 copy / verify `.log` 是 `codex exec -o` 的完成输出；`.exec.log` 是 stdout/stderr 实时诊断流，只用于确认 CLI 是否启动、是否有工具命令开始/结束、失败前最后发生了什么。`.exec.log` 文件增长本身不代表任务健康推进，重复 diff 或模型自述不会被当作真实执行进展。该目录默认本地忽略；任务通过后，Git checkpoint 只强制提交成功 attempt 对应的最终 copy / verify `.log`，`.exec.log` 等实时诊断流只留本地排障。
进度统一写入 `tasks/prompts/_shared/progress.json`，因此 `next` 和 `status` 会直接反映自动执行结果。

查看或恢复：

```bash
./dev
./dev --once
./dev status
./dev status --verbose
./dev processes
./task-loop status
./task-loop resume-failed
```

`./dev` 是 AreaMatrix Dev Console 总控入口，默认展示局势诊断首页，而不是把所有 task-loop 命令平铺在首页。首页只回答：现在安全吗、为什么、下一步按什么顺序做、v1 live queue 与 workflow 规划层当前处在哪。当前 live queue 来自 `tasks/prompts/**`；`workflow/` 是后续版本和大型变更的规划生命周期，不直接修改 live queue。首页主要入口是 `1 recommended guide`、`2 lifecycle map`、`3 live queue details`、`4 tools`、`? shortcuts`、`h help`、`q quit`；`1` 只展示行动链，不自动执行命令；危险操作只在 `live queue -> maintenance/danger`。直接按 Enter 只看完整状态，不启动任务；输入 `?` 查看全部快捷键。`./dev --once` 渲染一次首页后退出，便于截图或脚本检查。语言优先级是 `./dev --lang mixed|zh|en` > `DEV_LANG=mixed|zh|en` > `.codex/dev-console/config.json` > `mixed`；交互模式输入 `lang` 会保存本仓库本地偏好，该目录已被 `.gitignore` 忽略。`./dev` 壳层文案由 `scripts/task_loop/locales/{mixed,zh,en}.json` 管理，动作结构由 `scripts/task_loop/actions.py` 统一登记，命令、路径、环境变量、task label 和底层 runner / workflow 透传输出不翻译。颜色可用 `./dev --color never` 或 `NO_COLOR=1` 关闭；完整进程命令用 `./dev processes` 查看。旧版长输出保留在 `./dev status --verbose`。

## Workflow 与版本化变更

`workflow/` 是大功能 / 版本 / 重构 / 优化的生命周期系统；`tasks/prompts/**` 是已批准、可执行、可验收的小任务队列；`./task-loop` 只执行 tasks，不做需求决策。

- `workflow/versions/v1-mvp/` 记录当前 637-task live queue，v1 完成后再归档，不移动现有 `tasks/prompts/**`。
- `workflow/versions/v-template/` 是模板验收实例，用来证明 templates、schema、doctor、promotion preview、projection、closeout/audit 的全链路，不是真实后续版本。
- 真实新版本使用 `workflow/versions/vN/`，在 promotion apply 前仍不得绕过 v1 live gate。

版本工作流入口：

```bash
./dev workflow doctor
./dev workflow status
./dev workflow check-template
./dev workflow plan
./dev workflow queue
./dev workflow promote --version v-template preview
```

模板验收实例 changes / drafts 入口：

```bash
./dev changes doctor
./dev changes preview
./dev changes generate
./dev changes generate --feature template-docs-contract
```

`generate` 默认只把 manifest / copy-ready / verify-ready 草稿打印到终端，不落盘。显式写入时使用：

```bash
./dev changes generate --write
./dev changes generate --write --out-dir /tmp/areamatrix-template-drafts
./dev changes generate --write --force
```

默认写入位置是 `workflow/versions/v-template/drafts/`，并按 feature 分组，例如：

```text
workflow/versions/v-template/drafts/template-docs-contract/manifest.md
workflow/versions/v-template/drafts/template-docs-contract/docs-baseline.copy.md
workflow/versions/v-template/drafts/template-docs-contract/docs-baseline.verify.md
```

Promotion 预演会把 workflow 语义任务映射成未来 live runner 可识别的数字 task label，但不会写入 live queue：

```bash
./dev workflow promote --version v-template preview
./dev workflow promote --version v-template --feature template-docs-contract --preview
./dev workflow promote --version v-template --write --out-dir /tmp/areamatrix-template-promotion
```

`v-template` 是模板验收实例，`apply --write` 必须被硬门禁拦住。即使使用 promotion preview `--write`，也只写 promotion review artifact，不修改 `tasks/prompts/**`、不修改 `progress.json`、不启动 `./task-loop`。

这些文件只是 review artifact，不是正式 v1 live queue。它们不会修改 `tasks/prompts/**`、不会更新 `progress.json`，也不会启动或影响 `./task-loop`。后续若要创建真实产品版本，需要单独 `./dev workflow init --version vN`、讨论、计划和验收。

真实版本从 0 开始时使用：

```bash
./dev workflow init --version v2
./dev workflow init --version v2 --write
./dev workflow discuss --version v2 doctor
```

discussion gate 通过后，再进入 baseline / middle-layer / changes / plans /
drafts / queue / promotion preview。真实版本在 explicit approve + apply gate
通过前仍不得写入 live `tasks/prompts/**`。

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
