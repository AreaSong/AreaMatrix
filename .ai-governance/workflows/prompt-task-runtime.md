# Prompt Task Runtime

> AreaMatrix 使用 prompt 任务库把文档驱动开发拆成可串行执行的单元。

## 运行模式

| 模式 | 适用场景 | 规则 |
|---|---|---|
| Quick | 小范围文档或脚本修正 | 读相关文档，直接改，跑最小验证 |
| Change | 跨文件、跨层、需要新增结构 | 先计划，确认边界后执行 |
| Mission-Critical | 用户文件、DB、staging、FSEvents/iCloud、隐私、Core API 破坏性变化 | 先说明影响、风险、验证、回滚，再等待确认 |

## Prompt 任务流程

1. 运行 `doctor` 确认任务库健康。
2. 运行 `plan` 查看阶段顺序和依赖。
3. 运行 `render --task <label>` 生成可复制执行的 prompt。
4. 按 prompt 阅读文档、工程质量规则、编码规范、实现代码、运行验证。
5. 运行 `verify --task <label>` 生成只读验收 prompt。
6. 验收必须同时覆盖功能完成度、验证证据和工程质量；任一不达标都不能 mark completed。
7. 验收通过后，用 `mark --task <label> --status completed` 记录本地进度。
8. 阶段结束时运行 `verify --phase <phase>` 做阶段验收。

## 自动任务循环

任务量较大时，可以用 `scripts/run_area_matrix_task_pipeline.sh` 串联 copy-ready 与 verify-ready：

- 执行阶段使用 `codex exec` + `workspace-write`。
- 验收阶段使用 `codex exec` + `read-only`。
- 验收失败时，脚本把失败摘要注入下一轮执行，继续修复同一个 task。
- 失败摘要必须保留功能、验证和工程质量阻塞点；下一轮按“全部全面修复”处理。
- 只有验收输出 `VERIFY_RESULT: PASS` 后才进入下一个 task。
- 自动进度统一写入 `tasks/prompts/_shared/progress.json`。
- 默认 `RISK_GATE=mission-critical` 且 `RISK_POLICY=pause`；确认要全静默时必须显式设置 `RISK_POLICY=allow`。
- `RISK_POLICY=allow` 会向 copy prompt 注入用户已授权静默执行的上下文；High / Mission-Critical task 仍需记录风险、验证和回滚，但不再停下来等人工确认。
- 需要关机、额度不足或临时收尾时，使用 `--request-drain` 请求 live runner 跑完当前 task、完成 verify 与 Git checkpoint 后停止；它不得跳过当前 task 的 repair retry、验收或 checkpoint，也不得进入下一个 task。

日常操作优先使用根目录 `./dev.sh` 进入交互控制台；它封装 status、runner/codex 进程快照、后台继续、stale/failed 恢复、优雅收尾和健康检查，避免操作员记忆长命令。
控制台启动/继续前必须阻止重复 live runner；默认 Git checkpoint 为本地 `commit`，任务数为无限，前台/后台由操作员当次选择。

## 任务边界

- `Exact Docs`：必须阅读且必须存在的文档。
- `Existing Code`：执行前已存在且必须阅读的代码。
- `Expected New Paths`：任务允许新增或修改的目标路径。
- `Forbidden Touches`：除非重新确认，否则不得触碰的路径。
- `Risk Level`：Low / Medium / High / Mission-Critical。
- `Validation`：任务完成后必须尝试的检查。
- `Engineering Quality`：由 `tasks/prompts/_shared/engineering-quality-rules.md` 和 `docs/development/coding-standards.md` 共同定义的质量门禁。

## 验收规则

- 执行 prompt 可以改文件，验收 prompt 禁止改文件。
- 单任务验收必须逐项检查 task 核对清单和完成标准。
- 阶段验收中任一 task 不通过，则阶段不通过。
- 无法证明通过的项目默认不通过。
- 代码结构、错误处理、注释、测试或真实闭环不达标时，默认不通过。
- `mark` 只记录人工进度，不能替代验收结论。
