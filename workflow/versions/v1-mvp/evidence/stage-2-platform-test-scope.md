# Stage 2 Platform Test Scope

> Stage 1 MVP 历史队列中 `4-1/task-143` 的平台测试范围归档。
>
> 阅读时长：约 2 分钟。

## 定位

本文件归档 Stage 1 MVP 历史任务 `4-1/task-143` 的 Stage 2 Experience
platform test scope notes。这里的 Stage 2 Experience 是 Stage 1 MVP 历史
任务拆解中的内部阶段材料，不代表未来 `workflow/versions/v2` 已经开始。

这些 notes 原先分散在各平台测试目录下，只用于说明 Stage 2 closeout 不应新增
对应平台的产品实现或可执行平台测试 wiring。现在统一归档在 v1 MVP evidence 下，
避免 app 目录继续承载历史阶段说明。

## 平台范围

| Platform | Historical scope note |
|---|---|
| iOS | Stage 2 Experience has no iOS product implementation requirement. Stage 4 owns iOS product code and executable platform test wiring. Stage 2 closeout must not add iOS `Sources` or product behavior. Future iOS tasks should replace or extend this note with executable tests. |
| Linux | Stage 2 Experience has no Linux product implementation requirement. Stage 4 owns Linux product code and executable platform test wiring. Stage 2 closeout must not add Linux `src` or product behavior. Future Linux tasks should replace or extend this note with executable tests. |
| Windows | Stage 2 Experience has no Windows product implementation requirement. Stage 4 owns Windows product code and executable platform test wiring. Stage 2 closeout must not add Windows `src` or product behavior. Future Windows tasks should replace or extend this note with executable tests. |

## Related

- [v1-mvp source docs archive](../source-docs/README.md)
- [Stage source docs guide](../../source-docs-guide.md)
- [Stage 2 Experience integration verify](../../../tasks/prompts/phase-4/4-1-stage2-experience/task-143-stage-2-experience-integration-verify.md)
