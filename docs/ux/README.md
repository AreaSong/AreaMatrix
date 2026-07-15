# UX 文档索引

> `docs/ux/` 目录保存 AreaMatrix 长期维护的交互、文案、状态和恢复语义。
>
> 阅读时长：约 4 分钟。

---

## 推荐阅读顺序（按用户旅程）

```
docs/ux/first-launch.md
  → docs/ux/drag-import-flow.md
  → docs/ux/ui-states.md
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
| [brand-assets.md](brand-assets.md) | Logo、颜色、留白、最小尺寸与品牌交付规范 |
| [first-launch.md](first-launch.md) | 首次启动向导 |
| [drag-import-flow.md](drag-import-flow.md) | 拖拽导入与 ImportSheet |
| [ui-states.md](ui-states.md) | Tree/List/Detail 三件套状态机 |
| [classifier-calibration.md](classifier-calibration.md) | 分类器调教（纠错与沉淀规则） |
| [dedup-conflict.md](dedup-conflict.md) | 去重与冲突处理 |
| [settings-panel.md](settings-panel.md) | 设置面板信息架构 |
| [error-messages.md](error-messages.md) | CoreError → UI 反馈与恢复路径 |
| [search.md](search.md) | 搜索 UX |
| [deep-features.md](deep-features.md) | Undo/Tags/Batch/Shortcuts/Cmd+K/SmartLists |
| [competitive-analysis.md](competitive-analysis.md) | 竞品深度对比与差异化 |

---

## 与工程文档的关系

UX 文档只定义“用户看见什么、点什么、如何恢复”。工程实现细节请回到：

历史 UI 核查时，应优先使用 [workflow source docs guide](../../workflow/versions/source-docs-guide.md) 中的归档索引、页面跳转图和单页规格读法；功能域 UX 文档用于追溯来源与校验长期事实。若归档规格中的内容需要长期保留，应同步回本目录的功能域 UX 文档，而不是把归档页面规格文件迁回 `docs/`。

- `docs/modules/`：storage/classify/overview-gen/tree-scan/change-log
- `docs/api/`：core-api/error-codes/classifier-yaml/uniffi-recipes
- `docs/architecture/`：adopt-existing-folders/transactional-import/source-of-truth/fs-watcher/concurrency/migration
- `docs/development/`：observability/troubleshooting/performance

---

## Related

- [../README.md](../README.md)
- [../product/prd.md](../product/prd.md)
- [../product/glossary.md](../product/glossary.md)
