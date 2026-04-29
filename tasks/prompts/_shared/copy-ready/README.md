# Copy-ready Prompts

AreaMatrix 的执行 prompt 由 runner 动态生成，不在这里逐个落静态文件。

## 生成单任务执行 prompt

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py render --task 0-2/task-01
```

## 执行模式规则

- 可以修改文件。
- 必须读取 task、共享规则、依赖图、phase manifest。
- 必须逐个读取 `Exact Docs`。
- 必须读取当前存在的 `Existing Code`。
- 只能新增或修改 `Expected New Paths`。
- 不得触碰 `Forbidden Touches`。
- 完成后必须运行 `Validation`，并说明无法运行的项。

