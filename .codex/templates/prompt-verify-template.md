# Verify-ready Prompt Template

> 通常不手写本文件；优先使用 runner 生成：
>
> ```bash
> python3 tasks/prompts/_shared/prompt_pipeline.py verify --task <task-label>
> python3 tasks/prompts/_shared/prompt_pipeline.py verify --phase <phase>
> ```

## 验收原则

- 禁止修改文件。
- 必须读取 task、共享规则、依赖图、phase manifest。
- 必须逐个读取 `Exact Docs` 和当前存在的 `Existing Code`。
- 必须检查 `Expected New Paths` 是否真实落地。
- 必须检查 `Forbidden Touches` 是否被违规触碰。
- 无法证明通过则判定不通过。

## 输出格式

一、验收结论

二、验收范围

三、完成度摘要

四、逐项验收结果

五、阻塞项

六、验证情况

七、最终判定说明

