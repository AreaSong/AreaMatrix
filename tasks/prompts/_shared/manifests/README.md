# Prompt Manifests

Manifest 是任务执行的精确边界。每个 task label 必须在所属 phase manifest 中有同名章节。

## Schema

每个任务章节固定包含：

- `Exact Docs`：必须存在并阅读的文档。
- `Existing Code`：执行前已存在且必须阅读的代码；没有则写 `None`。
- `Expected New Paths`：允许新增或修改的路径。
- `Forbidden Touches`：未经重新确认不得触碰的路径。
- `Risk Level`：`Low`、`Medium`、`High` 或 `Mission-Critical`。
- `Validation`：任务完成后必须尝试的验证命令。

## Greenfield 说明

`Expected New Paths` 可以是当前尚不存在的路径。Runner 只校验它是否落在允许根目录内，不要求当前存在。

