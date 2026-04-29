# AreaMatrix Prompt 执行规则

> 每个任务文件引用本规则。AreaMatrix 当前支持 greenfield build，因此 manifest 既可以列已存在文件，也可以列预期新增路径。

## 核心原则

- 文档是唯一真相源（SSOT），优先读取 `docs/` 中的任务相关文档。
- 先读 task 文件，再读对应 phase manifest 中同 label 章节。
- `Exact Docs` 中的文档必须逐个读取，且必须存在。
- `Existing Code` 只列执行前已存在且需要阅读的代码；如果为 `None`，说明当前任务是新增实现。
- `Expected New Paths` 是任务允许新增或修改的路径；不得扩展到无关目录。
- `Forbidden Touches` 是禁止触碰边界；确需修改时必须暂停并重新确认。
- 高风险任务必须先说明影响、风险、验证与回滚，再等待确认。
- 所有已存在 capability specs 的任务必须遵循 [task-slicing-rules.md](task-slicing-rules.md)，并把 UX 页面、Core 能力规格与对应 control map 交叉验收。

## 四种处理

| 情况 | 条件 | 操作 |
|---|---|---|
| A | 文档有 + 代码有 + 不一致 | 改代码对齐文档 |
| B | 文档有 + 代码没有 | 按文档实现 |
| C | 文档有 + 代码有 + 一致 | 标注已一致，跳过 |
| D | 代码有 + 文档没有 | 不直接删除，先确认是否为未来任务或无主代码 |

## Greenfield 约定

- 任务可以创建 `Expected New Paths` 中列出的路径。
- 目录不存在不是失败；只有 `Exact Docs` 缺失才是 prompt 体系失败。
- 工程骨架任务可以创建空目录和最小可验证文件，但不得提前实现后续产品功能。
- 真实闭环任务不得以 mock、fixture、硬编码状态或静态示例数据通过最终验收。

## AreaMatrix 高风险边界

- 用户原文件删除、移动、覆盖、重命名。
- 非空目录接管、reindex、FSEvents 回流、iCloud 占位符下载。
- DB schema、migration、rollback、数据修复。
- staging recovery、事务式导入、重复 hash 与冲突处理。
- 自动概览写入，尤其是 `README.md` 和 `AREAMATRIX.md`。
- Core API / UDL / Swift bridge 的破坏性变化。
- 远程 AI 调用或用户数据离开本机。

## 任务结束输出

每个任务完成后汇报：

1. 改了什么。
2. 为什么这样改。
3. 跑了哪些验证。
4. 哪些风险或未验证项仍存在。

## 验收模式

- 验收 prompt 由 `python3 tasks/prompts/_shared/prompt_pipeline.py verify --task <label>` 生成。
- 阶段验收 prompt 由 `python3 tasks/prompts/_shared/prompt_pipeline.py verify --phase <phase>` 生成。
- 验收模式只读，不允许修改文件，不允许边验边修。
- 验收时必须回到 task、manifest、实际文件三者交叉检查。
- 无法用文件、测试、日志或命令输出证明通过的项目，一律判定不通过。
- UI 占位、接口空壳、未打通链路、缺失验证都不能视为完成。
- 如果 UX 页面引用的 Core 能力未实现或只接 mock，真实闭环验收必须不通过。
- 如果 Core 能力没有任何 UX 消费，也未在 control map 中标记为内部能力，对应 task 默认越界。
- 验收输出必须包含结论、范围、完成度摘要、逐项结果、阻塞项、验证情况和最终判定。
- 阶段验收中任一 task 不通过，则该阶段不通过。

## 进度记录

- `mark` 命令只记录人工判断，不代表自动验收通过。
- 只有完成 copy-ready 执行并通过 verify-ready 验收后，才建议标记 `completed`。
- 进度文件是本地运行状态，不能替代 task 文件、manifest 或验收证据。
