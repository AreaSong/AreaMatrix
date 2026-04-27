# 术语表

> AreaMatrix 项目中使用的术语中英对照与定义。所有文档遇到首次出现的术语应链接到此处。
>
> 阅读时长：约 3 分钟。

---

## 产品术语

| 中文 | English | 定义 |
|---|---|---|
| 资料库 | Repository / Repo | 用户在文件系统中的 AreaMatrix 根目录，默认 `~/AreaMatrix/` |
| 分类 / 分类目录 | Category / Category folder | 资料库下的一级目录（docs / code / ...），每个对应一种文件类型 |
| 内部 slug | Internal slug | 分类的英文标识符，用于代码/数据库（如 `docs`） |
| 显示名 | Display name | 分类在 UI 上的本地化名称（如「文档」） |
| 收件箱 | Inbox | 默认兜底分类，对应英文 slug `inbox` |
| 拖入 / 导入 | Import / Drop | 把外部文件加入资料库的动作 |
| 存储模式 | Storage mode | 拖入时的处理方式：Move / Copy / Index |
| 移动 | Move | 把原文件移入资料库（原位置消失） |
| 复制 | Copy | 复制原文件入库（原位置保留） |
| 仅索引 | Index | 不复制，只在 DB 记录元数据，原文件原位 |
| 伴生笔记 | Companion note | 每个文件可以有一份 `<filename>.md` 笔记，用户手动维护 |
| 改动日志 | Change log | 记录文件在资料库中所有事件的时间线 |
| 树状视图 | Tree view | 侧边栏的资料库目录树展示 |
| 详情面板 | Detail pane | 主窗口底部展示选中文件元数据/改动/笔记的区域 |

---

## 架构术语

| 中文 | English | 定义 |
|---|---|---|
| 核心库 | Core (library) | Rust 实现的平台无关业务逻辑，编译为 staticlib |
| 平台层 | Platform layer | 各平台的原生集成（macOS 上是 Swift / AppKit / FSEvents） |
| UI 层 | UI layer | 各平台原生 UI 实现（macOS 上是 SwiftUI） |
| 桥接 | Bridge / FFI | Rust ↔ 平台语言的跨语言调用层 |
| FFI | Foreign Function Interface | 跨语言函数调用接口 |
| UDL | UniFFI Definition Language | UniFFI 用于描述跨语言接口的 IDL |
| 真相源 | Source of Truth (SoT) | 数据冲突时以哪一方为准的策略 |
| 事务式导入 | Transactional import | 通过 staging 区实现的原子文件导入流程 |
| Staging 区 | Staging area | `.areamatrix/staging/`，文件落位前的临时区 |
| InFlight 过滤 | InFlight filter | 应用自身操作产生的 FSEvents 不应被当作外部变化处理 |
| 去抖 | Debounce | 在 200ms 窗口内合并同 path 的 FSEvents |
| 占位符 | Placeholder file | iCloud 未下载文件的本地占位（`.icloud` 后缀） |
| 协调读取 | Coordinated read | 通过 NSFileCoordinator 触发 iCloud 占位符下载 |

---

## 数据术语

| 中文 | English | 定义 |
|---|---|---|
| 文件条目 | File entry | SQLite `files` 表的一行 |
| 改动条目 | Change entry | SQLite `change_log` 表的一行 |
| 软删除 | Soft delete | 标记 `deleted_at` 而不物理删除 DB 行 |
| 哈希去重 | Hash-based dedup | 通过 SHA256 比对文件内容判断是否重复 |
| 元数据 | Metadata | 不包含文件内容本身的描述信息 |
| 事件 ID | Event ID (FSEventStreamEventId) | FSEvents 流中的事件单调递增 ID |

---

## 流程术语

| 中文 | English | 定义 |
|---|---|---|
| 分类引擎 | Classifier | 根据规则决定文件分类的组件 |
| 规则匹配 | Rule matching | 基于扩展名 + 关键词的两层匹配 |
| AI 兜底 | AI fallback | 规则未命中时调用 AI 模型分类（Stage 3） |
| 重命名建议 | Naming suggestion | Classifier 给出的目标文件名 |
| 冲突重命名 | Conflict rename | 目标文件已存在时自动追加序号 |
| 整库扫描 | Full rescan | 应用启动或用户主动触发的资料库全量重扫 |

---

## 角色术语

| 中文 | English | 定义 |
|---|---|---|
| 用户 | User | AreaMatrix 的最终使用者 |
| 维护者 | Maintainer | 项目的核心开发者，有合并 PR 的权限 |
| 贡献者 | Contributor | 提交过 PR 或 issue 的外部参与者 |
| 评审者 | Reviewer | 进行 code review 的人（通常是维护者） |
| 商业用户 | Commercial user | 使用 AreaMatrix 进行商业目的、需单独授权的用户 |

---

## 缩写表

| 缩写 | 全称 | 定义 |
|---|---|---|
| ADR | Architecture Decision Record | 架构决策记录 |
| API | Application Programming Interface | 应用编程接口 |
| CI | Continuous Integration | 持续集成 |
| FFI | Foreign Function Interface | 跨语言调用接口 |
| MVP | Minimum Viable Product | 最小可行产品 |
| ORM | Object-Relational Mapping | 对象关系映射 |
| PR | Pull Request | 合并请求 |
| SoT | Source of Truth | 真相源 |
| UDL | UniFFI Definition Language | UniFFI 接口描述语言 |
| WAL | Write-Ahead Logging | SQLite 的预写日志模式 |

---

## Related

- [prd.md](prd.md)
- [user-stories.md](user-stories.md)
- [../architecture/overview.md](../architecture/overview.md)
