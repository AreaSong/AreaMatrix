# C3-08 semantic-search

## 服务的 UX 页面

- S3-08 semantic-search-results

## Core API

- 计划新增：`semantic_search(repo_path, query, filter, pagination) -> SearchResultPage`
- 计划新增：`build_embedding_index(repo_path, scope)`

## 输入

- 自然语言 query、filter、embedding index scope。

## 输出

- 语义搜索结果、score、matched reason、fallback 状态。
- 普通搜索引用数据或 fallback hint，供 S3-08 以 `Semantic matches` / `Normal search matches` 分组展示；Core 不生成不可解释的单一混合分数。

## DB 变化

- 写 embedding index metadata。
- 记录 AI call log。

## 文件系统变化

- 读取索引范围内文件内容；受隐私规则限制。

## 错误码

- `Config`
- `Db`
- `PermissionDenied`
- `Internal`

## 验收标准

- 普通搜索失败不依赖语义搜索。
- 隐私规则阻止的文件不进入 embedding。
- provider 失败时能回退到普通搜索。
- S3-08 能基于 Core 输出展示语义组和普通搜索组，并对同一文件做可解释 dedupe。

## 延后范围

- OCR embedding 和跨设备 embedding sync 属于 Stage 4+。
