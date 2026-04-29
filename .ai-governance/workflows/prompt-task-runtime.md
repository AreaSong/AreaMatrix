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
4. 按 prompt 阅读文档、实现代码、运行验证。
5. 运行 `verify --task <label>` 生成只读验收 prompt。
6. 验收通过后，用 `mark --task <label> --status completed` 记录本地进度。
7. 阶段结束时运行 `verify --phase <phase>` 做阶段验收。

## 任务边界

- `Exact Docs`：必须阅读且必须存在的文档。
- `Existing Code`：执行前已存在且必须阅读的代码。
- `Expected New Paths`：任务允许新增或修改的目标路径。
- `Forbidden Touches`：除非重新确认，否则不得触碰的路径。
- `Risk Level`：Low / Medium / High / Mission-Critical。
- `Validation`：任务完成后必须尝试的检查。

## 验收规则

- 执行 prompt 可以改文件，验收 prompt 禁止改文件。
- 单任务验收必须逐项检查 task 核对清单和完成标准。
- 阶段验收中任一 task 不通过，则阶段不通过。
- 无法证明通过的项目默认不通过。
- `mark` 只记录人工进度，不能替代验收结论。
