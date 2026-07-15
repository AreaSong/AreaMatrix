# Core API Candidate Gaps Snapshot

> 归档自长期 Core API 文档的历史候选接口表。本文只用于追溯旧页面编排意图，不是当前 API 合同、待执行任务或未来版本承诺。

## 历史候选

| 候选 | 历史意图 | 当时的组合方式 |
|---|---|---|
| `preview_import(repo_path, source_path, options) -> ImportPreview` | 在导入前统一返回分类、目标、重复、同名冲突和 iCloud 状态 | `predict_category` 提供分类；平台层负责其余预检和确认 |
| Core 导入队列、进度与取消 | 为多文件和文件夹导入提供统一逐项状态 | Swift 队列编排多次导入调用 |
| 文件详情聚合 DTO | 一次返回元数据、日志和笔记 | `get_file`、`list_changes`、`read_note` 组合 |
| 已初始化资料库元数据摘要 | 展示 schema 与最近打开状态 | Core 路径校验加平台层只读 metadata inspector |

错误映射元数据后来已通过 `map_core_error` 进入稳定 UDL，因此不再属于候选缺口。

## 归档规则

- 候选名称不得被 README、用户指南或正式 Core API 当作可用能力。
- 如需重新提出，应进入新的 workflow discussion，重新定义产品价值、API、文件与 DB 风险、跨平台边界和验证。
- 本快照不授权修改 UDL、数据库、导入、reindex、iCloud 或用户文件行为。

## Related

- [归档索引](../../README.md)
- [长期 Core API](../../../../../../docs/api/core-api.md)
- [长期产品能力](../../../../../../docs/product/capabilities.md)
