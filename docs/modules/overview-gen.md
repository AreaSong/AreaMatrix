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

node 文件默认最多列出 200 个文件；最近变更使用固定时间窗口和条数上限，避免概览无限增长。

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
- 已有用户内容但无 managed block 时保留用户内容并附加管理块。
- 目标不是普通文件或内容无法安全处理时返回错误。
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

locale 控制 generated overview 和树相关显示文本。当前支持配置值由 `RepoConfig` 决定；它不是整个 macOS UI 的运行时语言开关。

## 性能

概览生成是同步 Core 工作：

- 查询有条数上限。
- 同一次 node 刷新会合并 root 输出。
- 当前没有后台 debounce 或异步 flush queue。
- 高频调用的节流由上层事件合并或业务批次负责。

## 验证重点

- 默认只写 `.areamatrix/generated/`。
- `README.md` 保持不变。
- managed block 外用户内容保持不变。
- 多目标写失败时所有目标恢复。
- 外部跨分类移动刷新来源和目标概览。
- overview 失败不推进 FSEvent cursor。

## Related

- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [storage.md](storage.md)
- [change-log.md](change-log.md)
