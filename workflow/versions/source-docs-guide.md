# Stage Source Docs Guide

> 本文件说明阶段 source docs 的位置、读法和写法约定。阶段 page specs、Core capability specs 和 control maps 不属于 `docs/` 当前层。
>
> 阅读时长：约 5 分钟。

## 定位

`workflow/versions/v*/source-docs/` 保存阶段事实：某个版本/阶段的页面拆解、能力拆解、control map、历史验收边界和执行索引。

`docs/` 只保存长期源事实：产品、架构、API、功能域 UX、模块设计、开发规范、测试与发布规则。若阶段材料沉淀为长期事实，应同步回 `docs/` 对应功能域文档，而不是把 `stage-*`、`S*`、`C*` 文件迁回 `docs/`。

## 目录约定

```text
workflow/versions/v1-mvp/source-docs/
  architecture/mvp-control-map.md
  core/capability-specs/stage-1-mvp.md
  core/capability-specs/stage-1-mvp/C1-*.md
  ux/page-specs/stage-1-mvp.md
  ux/page-specs/stage-1-mvp/S1-*.md

workflow/versions/v2/source-docs/
  architecture/stage-2-control-map.md
  core/capability-specs/stage-2-experience.md
  core/capability-specs/stage-2-experience/C2-*.md
  ux/page-specs/stage-2-experience.md
  ux/page-specs/stage-2-experience/S2-*.md

workflow/versions/v3/source-docs/
  architecture/stage-3-control-map.md
  core/capability-specs/stage-3-ai.md
  core/capability-specs/stage-3-ai/C3-*.md
  ux/page-specs/stage-3-ai.md
  ux/page-specs/stage-3-ai/S3-*.md

workflow/versions/v4/source-docs/
  architecture/stage-4-control-map.md
  core/capability-specs/stage-4-multiplatform.md
  core/capability-specs/stage-4-multiplatform/C4-*.md
  ux/page-specs/stage-4-multiplatform.md
  ux/page-specs/stage-4-multiplatform/S4-*.md
```

## 阶段索引

| 阶段 | Core 能力索引 | 页面规格 | Control Map |
|---|---|---|---|
| Stage 1 MVP archive | [Core ability index](v1-mvp/source-docs/core/capability-specs/stage-1-mvp.md) | [Page specs](v1-mvp/source-docs/ux/page-specs/stage-1-mvp.md) | [Control map](v1-mvp/source-docs/architecture/mvp-control-map.md) |
| Stage 2 Experience | [Core ability index](v2/source-docs/core/capability-specs/stage-2-experience.md) | [Page specs](v2/source-docs/ux/page-specs/stage-2-experience.md) | [Control map](v2/source-docs/architecture/stage-2-control-map.md) |
| Stage 3 AI | [Core ability index](v3/source-docs/core/capability-specs/stage-3-ai.md) | [Page specs](v3/source-docs/ux/page-specs/stage-3-ai.md) | [Control map](v3/source-docs/architecture/stage-3-control-map.md) |
| Stage 4 Multiplatform | [Core ability index](v4/source-docs/core/capability-specs/stage-4-multiplatform.md) | [Page specs](v4/source-docs/ux/page-specs/stage-4-multiplatform.md) | [Control map](v4/source-docs/architecture/stage-4-control-map.md) |

## 读取顺序

1. 先读 `docs/` 中对应的长期事实，例如产品、功能域 UX、Core API、模块或架构文档。
2. 再读当前版本的阶段索引：page specs、Core capability specs 和 control map。
3. 执行任务时，以 manifest 的 Exact Docs 和 task 文件为边界；阶段 source docs 只定义本阶段切片，不替代长期源事实。
4. 若阶段文档与 `docs/` 冲突，先修正长期事实或明确阶段文档过期，再同步阶段文档。

## Page Specs 写法

页面规格回答“用户看见什么、如何操作、状态如何变化”。单页文件使用稳定页面 ID，例如 `S1-17`、`S2-01`、`S3-09`、`S4-X-04`。

单页规格应包含：

1. 开发位置。
2. 页面背景。
3. 整体风格。
4. 内容结构。
5. 状态展开。
6. 交互含义。
7. 可访问性。
8. 数据与依赖。
9. 验收清单。
10. 来源。

### 来源标注规则

来源分三类：

- 直接来源：现有 UX 文档已有页面、布局或明确交互。
- 组合来源：多个文档共同决定页面。
- 推导来源：路线图或任务只定义能力，页面由阶段规格补齐。

推导内容必须遵守 AreaMatrix 不变量：接管已有目录不移动、不重命名、不删除、不覆盖用户文件；自动生成内容默认只写入 `.areamatrix/generated/`；AI 默认关闭；远程 AI 必须由用户显式配置并启用。

## Core Capability Specs 写法

Core 能力规格回答“Core 必须提供什么行为、输入输出和副作用”。每个 `C*` 文件应包含：

1. 服务的 UX 页面。
2. Core API。
3. 输入。
4. 输出。
5. DB 变化。
6. 文件系统变化。
7. 错误码。
8. 验收标准。
9. 延后范围。

已提升为长期合同的 API 必须同步到 `docs/api/core-api.md`，再同步 `core/area_matrix.udl`、Rust 实现和 Swift bridge。

## Control Map 写法

Control map 负责把页面、Core 能力、API、DB、文件系统、错误态和 prompt 任务绑定起来。它是阶段执行地图，不是长期架构源事实。

需要长期保留的架构规则应同步到 `docs/architecture/`；需要长期保留的 UX 规则应同步到 `docs/ux/`；需要长期保留的 Core 合同应同步到 `docs/api/core-api.md` 或 `docs/modules/`。

## Related

- [Workflow versions](README.md)
- [Workflow overview](../README.md)
- [Docs navigation](../../docs/README.md)
- [Prompt task library](../../tasks/prompts/README.md)
