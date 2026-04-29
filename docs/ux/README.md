# UX 文档索引（Wireframe Specs）

> `docs/ux/` 目录提供 AreaMatrix 的产品/UX 规格文档（wireframe 级），用于把工程文档之外的“用户交互与文案”补齐到可直接实现的程度。
>
> 阅读时长：约 4 分钟。

---

## 推荐阅读顺序（按用户旅程）

```
docs/ux/first-launch.md
  → docs/ux/drag-import-flow.md
  → docs/ux/ui-states.md
  → docs/ux/page-specs/README.md
  → docs/ux/classifier-calibration.md
  → docs/ux/dedup-conflict.md
  → docs/ux/settings-panel.md
  → docs/ux/error-messages.md
  → docs/ux/search.md
  → docs/ux/deep-features.md
  → docs/ux/competitive-analysis.md
```

---

## 文档清单

| 文档 | 说明 |
|---|---|
| [first-launch.md](first-launch.md) | 首次启动向导 |
| [drag-import-flow.md](drag-import-flow.md) | 拖拽导入与 ImportSheet |
| [ui-states.md](ui-states.md) | Tree/List/Detail 三件套状态机 |
| [page-specs/README.md](page-specs/README.md) | 按阶段、逐页面的 UI 开发规格索引 |
| [page-specs/stage-1-mvp.md](page-specs/stage-1-mvp.md) | Stage 1 页面索引；单页规格在 `page-specs/stage-1-mvp/` |
| [page-specs/stage-2-experience.md](page-specs/stage-2-experience.md) | Stage 2 页面索引；单页规格在 `page-specs/stage-2-experience/` |
| [page-specs/stage-3-ai.md](page-specs/stage-3-ai.md) | Stage 3 页面索引；单页规格在 `page-specs/stage-3-ai/` |
| [page-specs/stage-4-multiplatform.md](page-specs/stage-4-multiplatform.md) | Stage 4 页面索引；单页规格在 `page-specs/stage-4-multiplatform/` |
| [classifier-calibration.md](classifier-calibration.md) | 分类器调教（纠错与沉淀规则） |
| [dedup-conflict.md](dedup-conflict.md) | 去重与冲突处理 |
| [settings-panel.md](settings-panel.md) | 设置面板信息架构 |
| [error-messages.md](error-messages.md) | CoreError → UI 反馈与恢复路径 |
| [search.md](search.md) | 搜索 UX（Stage 2） |
| [deep-features.md](deep-features.md) | Undo/Tags/Batch/Shortcuts/Cmd+K/SmartLists |
| [competitive-analysis.md](competitive-analysis.md) | 竞品深度对比与差异化 |

---

## 与工程文档的关系

UX 文档只定义“用户看见什么、点什么、如何恢复”。工程实现细节请回到：

- `docs/modules/`：storage/classify/overview-gen/tree-scan/change-log
- `docs/api/`：core-api/error-codes/classifier-yaml/uniffi-recipes
- `docs/architecture/`：adopt-existing-folders/transactional-import/source-of-truth/fs-watcher/concurrency/migration
- `docs/development/`：observability/troubleshooting/performance

---

## Related

- [../README.md](../README.md)
- [../product/prd.md](../product/prd.md)
- [../product/glossary.md](../product/glossary.md)
