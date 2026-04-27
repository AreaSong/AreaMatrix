# AreaMatrix 文档导航

> 本目录是 AreaMatrix 的完整项目文档。中文为主，技术名词、API、配置 schema 保留英文。
>
> 阅读时长：本页约 3 分钟。

---

## 按角色推荐的阅读路径

### 你是产品经理 / 关心做什么

```
docs/product/prd.md
   → docs/product/user-stories.md
   → docs/roadmap/milestones.md
```

### 你是架构师 / 关心怎么搭

```
docs/architecture/overview.md
   → docs/architecture/tech-stack.md
   → docs/architecture/layered-design.md
   → docs/architecture/source-of-truth.md
   → docs/adr/  (按需翻阅决策记录)
```

### 你是核心库实现者 / 写 Rust 部分

```
docs/architecture/data-model.md
   → docs/architecture/transactional-import.md
   → docs/modules/storage.md
   → docs/modules/classify.md
   → docs/modules/readme-gen.md
   → docs/modules/tree-scan.md
   → docs/modules/change-log.md
   → docs/api/core-api.md
   → docs/api/error-codes.md
```

### 你是 macOS App 实现者 / 写 SwiftUI 部分

```
docs/architecture/overview.md
   → docs/architecture/ffi-design.md
   → docs/architecture/fs-watcher.md
   → docs/development/setup.md
   → docs/development/build.md
   → docs/api/core-api.md
```

### 你是新加入的贡献者

```
顶层 README.md
   → CONTRIBUTING.md
   → docs/development/setup.md
   → docs/development/git-workflow.md
   → docs/development/coding-standards.md
   → docs/development/testing.md
```

### 你想了解某个决策为什么是这样

```
docs/adr/README.md  (索引)
   → docs/adr/0001..0009-*.md  (具体决策)
```

---

## 全部文档清单

### 产品 / Product

| 文档 | 说明 |
|---|---|
| [product/prd.md](product/prd.md) | 产品需求文档 |
| [product/user-stories.md](product/user-stories.md) | 核心用户故事 |
| [product/glossary.md](product/glossary.md) | 中英术语表 |

### 架构 / Architecture

| 文档 | 说明 |
|---|---|
| [architecture/overview.md](architecture/overview.md) | 架构总览 |
| [architecture/tech-stack.md](architecture/tech-stack.md) | 技术栈与选型理由 |
| [architecture/layered-design.md](architecture/layered-design.md) | 分层设计（Core / FFI / Platform / UI） |
| [architecture/data-model.md](architecture/data-model.md) | SQLite schema 详解 |
| [architecture/ffi-design.md](architecture/ffi-design.md) | Rust ↔ Swift UniFFI 桥接设计 |
| [architecture/fs-watcher.md](architecture/fs-watcher.md) | 文件系统监听与 iCloud 集成 |
| [architecture/transactional-import.md](architecture/transactional-import.md) | 事务式导入流程 |
| [architecture/source-of-truth.md](architecture/source-of-truth.md) | 真相源策略 |

### 模块详细设计 / Modules

| 文档 | 说明 |
|---|---|
| [modules/classify.md](modules/classify.md) | 分类引擎 |
| [modules/storage.md](modules/storage.md) | 文件存储操作 |
| [modules/readme-gen.md](modules/readme-gen.md) | README.md 生成器 |
| [modules/tree-scan.md](modules/tree-scan.md) | 目录扫描与树构建 |
| [modules/change-log.md](modules/change-log.md) | 改动日志 |

### API / 配置规范

| 文档 | 说明 |
|---|---|
| [api/core-api.md](api/core-api.md) | Core 对外 API（UDL 接口） |
| [api/error-codes.md](api/error-codes.md) | 错误码列表 |
| [api/classifier-yaml.md](api/classifier-yaml.md) | classifier.yaml 配置规范 |

### 开发指南 / Development

| 文档 | 说明 |
|---|---|
| [development/setup.md](development/setup.md) | 开发环境搭建 |
| [development/build.md](development/build.md) | 构建与运行 |
| [development/coding-standards.md](development/coding-standards.md) | 编码规范 |
| [development/git-workflow.md](development/git-workflow.md) | Git 分支与 commit 规范 |
| [development/testing.md](development/testing.md) | 测试策略 |
| [development/release.md](development/release.md) | 发布流程 |

### 决策记录 / ADR

| 文档 | 决策主题 |
|---|---|
| [adr/README.md](adr/README.md) | ADR 索引与模板说明 |
| [adr/0001-tech-stack.md](adr/0001-tech-stack.md) | 桌面技术栈选型 |
| [adr/0002-uniffi-vs-others.md](adr/0002-uniffi-vs-others.md) | FFI 工具选择 |
| [adr/0003-source-of-truth-strategy.md](adr/0003-source-of-truth-strategy.md) | 真相源策略 |
| [adr/0004-transactional-storage.md](adr/0004-transactional-storage.md) | 事务式存储 |
| [adr/0005-fsevents-listener.md](adr/0005-fsevents-listener.md) | 文件系统监听方案 |
| [adr/0006-icloud-support.md](adr/0006-icloud-support.md) | iCloud 兼容程度 |
| [adr/0007-readme-granularity.md](adr/0007-readme-granularity.md) | README 生成粒度 |
| [adr/0008-naming-and-i18n.md](adr/0008-naming-and-i18n.md) | 命名与国际化 |
| [adr/0009-min-macos-version.md](adr/0009-min-macos-version.md) | 最低 macOS 版本 |

### 路线图 / Roadmap

| 文档 | 说明 |
|---|---|
| [roadmap/milestones.md](roadmap/milestones.md) | 四阶段里程碑 |
| [roadmap/stage-1-mvp.md](roadmap/stage-1-mvp.md) | Stage 1 MVP 任务拆解 |

---

## 写作约定

所有文档遵守以下统一规则：

1. **每篇 .md 文件**：第一级标题 → 一句话摘要 → 阅读时长估算 → 正文
2. **互连**：篇尾 "Related" 章节链接相关文档
3. **代码示例**：用对应语言标签（`rust` / `swift` / `sql` / `yaml` / `bash`）
4. **架构图**：`mermaid`，节点 ID 用 camelCase
5. **决策点**：明确"为什么这样、考虑过什么备选、何时重审"
6. **避免主观**：用"团队约定 / 当前共识"代替"我认为"
7. **术语一致**：首次出现给中英对照（依赖 [product/glossary.md](product/glossary.md)）

## 反馈

发现文档错误、信息缺失、表述不清，欢迎直接 PR 修改，或提 issue 用 `documentation` 标签。
