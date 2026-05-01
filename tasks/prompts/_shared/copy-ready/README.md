# Copy-ready Prompts

AreaMatrix 的执行 prompt 可以由 runner 动态生成，也可以导出为本目录下的静态文件。

## 动态生成单任务执行 prompt

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py render --task 0-2/task-01
```

## 导出静态执行 prompt

```bash
python3 tasks/prompts/_shared/prompt_pipeline.py export --phase phase-1
python3 tasks/prompts/_shared/prompt_pipeline.py export --all
```

导出后文件按 phase 存放：

```text
tasks/prompts/_shared/copy-ready/phase-1/1-1-task-01.md
```

执行时直接打开对应文件，复制整段 copy-ready prompt 给 Codex。

## 执行模式规则

- 可以修改文件。
- 必须读取 task、共享规则、依赖图、phase manifest。
- 必须读取工程质量规则和 `docs/development/coding-standards.md`。
- 必须逐个读取 `Exact Docs`。
- 必须读取当前存在的 `Existing Code`。
- 只能新增或修改 `Expected New Paths`。
- 不得触碰 `Forbidden Touches`。
- 必须按企业级可维护代码交付，禁止占位、硬编码通过态、mock-only 闭环或一次性脚本化实现。
- 完成后必须运行 `Validation`，并说明无法运行的项。
