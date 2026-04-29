# Core 能力规格

> 本目录把 UX 页面需要的行为切成 Core 能力合同。它不是页面规格，也不替代 `docs/api/`、`docs/modules/` 或 `docs/architecture/`；它负责把这些来源切成可执行、可验收的小闭环。

## 定位

- UX 页面规格回答“用户看见什么、如何操作、状态如何变化”。
- Core 能力规格回答“后端/Core 必须提供什么行为、输入输出和副作用”。
- MVP control map 负责把页面、能力、API、DB、文件系统、错误态和 prompt 任务绑定起来。

## 编写规则

每个能力文件必须包含：

1. 服务的 UX 页面。
2. Core API。
3. 输入。
4. 输出。
5. DB 变化。
6. 文件系统变化。
7. 错误码。
8. 验收标准。
9. 延后范围。

## 使用方式

- 实现 Core 任务时，先读对应 `C1-*` 文件，再读它引用的 `docs/api/`、`docs/modules/`、`docs/architecture/` 文档。
- 实现 macOS UI 任务时，先读页面规格，再读 control map 中绑定的 `C1-*` 文件。
- 如果页面需要 Core 但没有能力规格，先补能力规格，不直接补 UI mock。
- 如果 Core 能力没有任何页面消费，也没有被 control map 标记为内部能力，不进入 Stage 1 MVP 提前实现。

## 阶段索引

| 阶段 | Core 能力索引 | 页面规格 | Control Map |
|---|---|---|---|
| Stage 1 MVP | [stage-1-mvp.md](stage-1-mvp.md) | [../ux/page-specs/stage-1-mvp.md](../../ux/page-specs/stage-1-mvp.md) | [mvp-control-map.md](../../architecture/mvp-control-map.md) |
| Stage 2 Experience | [stage-2-experience.md](stage-2-experience.md) | [../ux/page-specs/stage-2-experience.md](../../ux/page-specs/stage-2-experience.md) | [stage-2-control-map.md](../../architecture/stage-2-control-map.md) |
| Stage 3 AI | [stage-3-ai.md](stage-3-ai.md) | [../ux/page-specs/stage-3-ai.md](../../ux/page-specs/stage-3-ai.md) | [stage-3-control-map.md](../../architecture/stage-3-control-map.md) |
| Stage 4 Multiplatform | [stage-4-multiplatform.md](stage-4-multiplatform.md) | [../ux/page-specs/stage-4-multiplatform.md](../../ux/page-specs/stage-4-multiplatform.md) | [stage-4-control-map.md](../../architecture/stage-4-control-map.md) |

## Related

- [stage-1-mvp.md](stage-1-mvp.md)
- [stage-2-experience.md](stage-2-experience.md)
- [stage-3-ai.md](stage-3-ai.md)
- [stage-4-multiplatform.md](stage-4-multiplatform.md)
- [../architecture/mvp-control-map.md](../../architecture/mvp-control-map.md)
- [../api/core-api.md](../../api/core-api.md)
