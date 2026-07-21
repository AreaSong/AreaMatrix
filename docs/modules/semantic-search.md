# 语义搜索（semantic_search）

> 记录 semantic search surface 的查询、索引构建、隐私门禁与 local/remote 路由边界。
>
> 阅读时长：约 5 分钟。

---

## 模块布局

`core/src/semantic_search/` 当前包含：

```text
semantic_search/
├── call_log.rs
├── executor.rs
├── fallback.rs
├── implementation.rs
├── matches.rs
├── privacy.rs
├── store/
│   ├── db.rs
│   └── types.rs
└── store.rs
```

入口与合同类型位于 `core/src/semantic_search.rs`；`core/src/lib.rs` re-export 公开函数供 UniFFI / UDL 暴露。

测试：

- `core/tests/semantic_search_contract_api.rs`
- `core/tests/semantic_search_implementation.rs`
- `core/tests/semantic_search_validation.rs`
- `core/tests/semantic_search_failure_recovery.rs`

## 路由与索引

| 路由 | 说明 |
|---|---|
| `Local` | 本地 embedding 与 semantic index（当前主要实现路径） |
| `Remote` | 远程 embedding；须通过 AI 设置、provider 配置、隐私规则与 call-log 门禁，并由 `AREAMATRIX_AI_SEMANTIC_REMOTE_RUNTIME` 外部 runtime 执行 |

`SemanticIndexStatus`：`Ready` / `NotReady` / `Building` / `Paused` / `Canceled` / `Failed` / `Partial`。

`build_embedding_index` 需要 `SemanticIndexScope.confirmed = true`；只读用户文件生成 embedding metadata，不写用户文件内容。

**Remote 接线**：当 provider preference 或 scope 请求 remote 时，implementation 在 privacy / call-log 门禁通过后调用外部 runtime；缺少 runtime、provider 或 runtime 失败时返回对应 fallback（含 `ProviderUnavailable`、`RateLimited`、`Timeout`），不静默发网。

## 查询与 Fallback

`semantic_search` 返回分页的 semantic 组与 normal search 组（dedupe 渲染）。Fallback 原因包括：

`AiDisabled`、`FeatureDisabled`、`ProviderUnavailable`、`PrivacyRule`、`SemanticIndexNotReady`、`CallLogUnavailable`、`NoEligibleInput`、`NormalSearchUnavailable`、`RateLimited`、`Timeout`。

索引未就绪或门禁失败时仍可通过 normal search 组展示结果。

## 隐私与 call-log

- **Privacy gate**：`privacy.rs` 从 AI settings 的 rules JSON 解析 folder / category / keyword / extension / tag 规则；可按 `Local`、`Remote` 或 `LocalAndRemote` 阻断输入。
- **Call-log**：`call_log.rs` 在 search / build 成功或 fallback 时写入 AI call log 行；持久化失败返回 `CallLogUnavailable` fallback。
- **数据最小化**：fallback message 与 match reason 不含 provider raw output 或完整文件内容。
- **Remote 发网条件**：master AI 开启、semantic search capability 启用、privacy 通过、remote provider 配置有效、call-log 可写——全部满足才走 remote；否则 fail closed 到 fallback。

输入字段类别：`FileName`、`RepoRelativePath`、`Category`、`NoteSummary`、`AiSummary`、`ExtractedTextExcerpt`。

## 安全边界

- **用户文件只读**：索引构建与搜索不修改、不删除、不移动用户源文件。
- **自动生成**：embedding / index metadata 存于 AreaMatrix 拥有的 DB 与 store，不写 `README.md`。
- **隐私优先**：匹配 `privacy_rule_id` 时跳过或 redact 字段，并在结果页暴露 rule id 供 UI 解释。
- **Core 平台无关**：local embedding 与 store 不依赖 macOS API；remote HTTP 通过可注入 provider runtime。
- **查询校验**：空 query、超长 query（>512 字符）、非法 filter/pagination 返回 `Config`。

## 公开 API

- `semantic_search(repo, query, filter, pagination)`
- `build_embedding_index(repo, scope)`

详见 [Core API](../api/core-api.md) ai/search 章节。

## 验证重点

- AI 关闭 / feature 关闭时的 fallback 与 normal 组仍可用。
- Privacy rule 阻断 remote 与 local 的分别适用。
- Index NotReady 时 `Build semantic index` 路由与 fallback_reason。
- Call-log 失败不导致无审计的 silent success。
- Remote preference 但 provider / runtime 不可用时的 `ProviderUnavailable`；runtime 429 / `rate_limited` → `RateLimited`；超时 → `Timeout`。
- semantic / normal dedupe 与 `low_confidence` 标记。
- build 需 confirmed；privacy_policy_ref 校验。

## Related

- [../api/core-api.md](../api/core-api.md)
- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [classify.md](classify.md)
- [storage.md](storage.md)
