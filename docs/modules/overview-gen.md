# 概览生成模块

> 记录 AreaMatrix 当前 generated overview 的输出、触发、原子写入和用户文件边界。
>
> 阅读时长：约 6 分钟。

---

## 输出

默认输出：

```text
<repo>/.areamatrix/generated/
├── root.md
└── nodes/
    └── <category>.md
```

当资料库配置为 `RootAreaMatrixFile` 时，同时维护：

```text
<repo>/AREAMATRIX.md
```

AreaMatrix 不生成或覆盖 `README.md`。

`.areamatrix/generated/**` 是 AreaMatrix-owned 全文件输出；刷新时会替换完整文件，用户直接修改这些文件的
内容可能在下一次生成时被覆盖。只有可选根 `AREAMATRIX.md` 使用 managed block，并保留标记块外的用户内容。

## 当前模块结构

```text
core/src/overview/
├── mod.rs
└── atomic_write.rs
```

- `mod.rs`：查询 overview 数据、格式化 Markdown、维护 managed block、校验 node slug。
- `atomic_write.rs`：`WritePlan`、写前快照和多文件失败回滚。

当前没有独立 `markers.rs`、`template.rs`、`format.rs`、`i18n.rs`，也没有 Tokio debounce 服务。

## 入口

主要入口：

- `write_generated_root`：资料库初始化时创建 generated root。
- `write_root_areamatrix_file`：用户选择 root output 时创建根 `AREAMATRIX.md`。
- `regenerate_after_import`：成功导入后按 entry category 更新。
- `regenerate_for_node`：更新一个分类，同时更新 generated root 和可选根文件。

`regenerate_for_node` 是当前统一刷新入口。调用方必须传入经过校验的 category slug。

## 数据来源

概览从 SQLite 读取：

- 当前分类的 active files。
- 当前分类最近 change log。
- 各分类的文件数、总大小和最近导入时间。
- 根级最近 change log。
- 当前资料库 locale 和 overview output 配置。

node 文件默认最多列出 200 个文件。node 最近变更窗口为 30 天，root 最近变更窗口为 7 天，两者最多列出
20 条，避免概览无限增长。

文件和节点 Markdown 链接对 UTF-8 bytes 执行 percent-encoding，保留 `/` 作为路径分隔符；空格、Unicode、
emoji 和其他非 unreserved bytes 使用大写十六进制 `%XX` 表示。

## 写入计划

一次 `regenerate_for_node` 生成以下 `WritePlan`：

1. `.areamatrix/generated/nodes/<category>.md`
2. `.areamatrix/generated/root.md`
3. 可选的根 `AREAMATRIX.md`

`write_plans_with_rollback` 在写入前捕获每个目标：

- 原文件字节。
- 文件缺失状态。
- 非普通文件状态。

任一原子替换失败时，按逆序恢复已捕获目标。缺失目标会被删除，已有普通文件恢复原字节；非普通文件不会被强制覆盖。

## AREAMATRIX.md managed block

根文件使用明确标记：

```markdown
<!-- AREAMATRIX:BEGIN auto-generated content; do NOT edit between markers -->
...
<!-- AREAMATRIX:END -->
```

规则：

- 文件缺失时创建完整 AreaMatrix 入口。
- 已有合法 managed block 时只替换标记内内容。
- 用户在设置中显式确认启用 `RootAreaMatrixFile` 后，已有用户内容但无合法 managed block 时会保留原内容并
  附加管理块；不完整的 marker 不会被当作可替换的合法 block。
- 目标不是普通文件、不可读或不能以 UTF-8 处理时返回错误。
- `README.md` 始终不参与该流程。

## 触发点

当前已连接的触发包括：

- 资料库初始化。
- 单文件导入成功。
- repo-owned 文件重命名成功。
- 外部 created、renamed、removed、modified 批次。

外部跨分类移动会同时刷新来源分类和目标分类，避免旧分类概览保留已移动文件。

未连接到 `regenerate_for_node` 的业务操作不能在文档中宣称会自动刷新概览；新增触发必须同时补实现和测试。

## 失败语义

- 导入或 repo-owned rename 的 overview 失败进入对应业务回滚路径。
- 外部同步的 DB batch 先提交；overview 失败时 cursor 不推进，重放会修复生成物。
- 原子写失败不得留下多份概览彼此不一致。
- 概览错误不能通过覆盖用户文档进行恢复。

## locale

`RepoConfig.locale` 是资料库内容 policy。`system` 表示跟随当前已解析界面语言；`zh-CN` / `zh-SG` 和
`en-*` 是只读兼容别名，普通读取不得隐式写回。未知非空值允许浏览，树和分类显示依次查 exact raw
locale、`en`、slug，但新的概览生成返回 `Config`，直到用户在 Repository 设置中明确选择支持值。

Core 不读取进程级界面语言。init、import、repo-owned rename、repair 和 external sync 调用都显式携带
concrete `zh-Hans` 或 `en` 的 operation snapshot；同一事务、rollback、continuation 或 replay 必须复用。
new attempt 才重新捕获。切换任一语言设置都不主动重写已有概览，只影响之后开始的 operation；运行中的
应用自有进度文案可以响应界面语言变化，但概览内容保持冻结 locale。资料库内容语言不得翻译用户文件名、
路径或正文。

设置保存本身不调用 overview 入口。之后正常发生且本来就会刷新 overview 的 operation 可以按新快照替换
派生输出。持久化 Markdown 不使用 macOS `autoupdatingCurrent` region；日期、数字、文件大小和货币使用
内容 locale 对应的固定格式，保证同一 operation 的 replay 在不同设备上产生相同文本。

## 性能

概览生成是同步 Core 工作：

- 查询有条数上限。
- 同一次 node 刷新会合并 root 输出。
- 当前没有后台 debounce 或异步 flush queue。
- 高频调用的节流由上层事件合并或业务批次负责。

## 验证重点

- 默认只写 `.areamatrix/generated/`。
- generated 文件允许完整替换，根 `AREAMATRIX.md` 只替换合法 managed block。
- `README.md` 保持不变。
- managed block 外用户内容保持不变。
- 多目标写失败时所有目标恢复。
- 外部跨分类移动刷新来源和目标概览。
- overview 失败不推进 FSEvent cursor。
- operation replay 使用原 content locale，不产生同批混合语言概览。
- unknown repository locale 允许 exact raw/en/slug 浏览回退，但阻断生成。

## Related

- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [storage.md](storage.md)
- [change-log.md](change-log.md)
