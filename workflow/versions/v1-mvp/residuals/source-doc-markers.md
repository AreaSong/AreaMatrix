# v1-mvp Source Doc Markers

历史 source docs 与产品文档状态词索引：说明哪些“未完成 / blocked / pending”是产品结构或历史语境，不是当前任务。

阅读时长：约 3 分钟。

---

## Product behavior markers

| 来源 | 说明 |
|---|---|
| [docs/product/prd.md](../../../../docs/product/prd.md) | “上次有 N 个文件未完成导入”是崩溃恢复产品提示文案。 |
| [docs/product/user-stories.md](../../../../docs/product/user-stories.md) | “未完成导入”“同步中”等是验收标准中的产品行为，不代表 task state。 |
| [docs/api/core-api.md](../../../../docs/api/core-api.md) | `Pending` / `Blocked` / `Failed` 是 API 状态枚举或 UI 状态，不代表仓库任务状态。 |

## Historical source docs

| 来源 | 说明 |
|---|---|
| [../source-docs/](../source-docs/) | v1 MVP 历史内部 Stage 1/2/3/4 source docs archive，不代表未来 `v2` / `v3` / `v4` 已启动。 |
| [../execution/README.md](../execution/README.md) | 历史 copy-ready / verify-ready 里的 `TODO`、`blocked`、`open` 等词属于历史 prompt 语境。 |

## 清理原则

- `docs/` 保留稳定产品结构，不放当前项目执行状态。
- 当前 release / closeout 状态写入 `workflow/versions/<version>/evidence/`、`closeout/` 和本 residual ledger。
- 不为消除关键词而改写产品状态枚举或用户可见文案。

## Related

- [global residual ledger](../../../residuals/)
- [release-evidence.md](release-evidence.md)
