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
`en-*` 是只读兼容别名，普通读取不得隐式写回。已知显式/alias policy 的树和分类显示依次查询 exact raw、
resolved concrete、`en`、slug；`system` 从当前 concrete locale 开始；未知非空值只读浏览依次查询 exact raw、
`en`、slug，但新的概览生成返回 `Config`，直到用户在 Repository 设置中明确选择支持值。

Core 不读取进程级界面语言。init、import、repo-owned rename、repair 和 external sync 调用都显式携带
concrete `zh-Hans` 或 `en` 的 operation snapshot；同一事务、rollback、continuation 或 replay 必须复用。
new attempt 才重新捕获。切换任一语言设置都不主动重写已有概览，只影响之后开始的 operation；运行中的
应用自有进度文案可以响应界面语言变化，但概览内容保持冻结 locale。资料库内容语言不得翻译用户文件名、
路径或正文。

设置保存本身不调用 overview 入口。之后正常发生且本来就会刷新 overview 的 operation 可以按新快照替换
派生输出。持久化 Markdown 不使用 macOS `autoupdatingCurrent` region；日期、数字、文件大小和货币使用
内容 locale 对应的固定格式，时间统一使用 UTC，并记录 format contract version，保证同一 operation 的
replay 在不同设备上产生相同文本。

全库 overview regeneration 是独立的显式 operation。它只覆盖 `.areamatrix/generated/root.md`、全部
`.areamatrix/generated/nodes/*.md` 与已启用且 marker 合法的根 `AREAMATRIX.md` managed block；不处理
AI summary、classifier、note、tag、`README.md` 或 managed block 外文本。普通 operation 可以让不同
overview 暂时保留不同历史 locale，只有该显式入口负责统一。

Repository 页通过 durable provenance 报告五种状态：没有任何现有目标时为 `NotGenerated`；全部活动目标
与当前 concrete locale 和 format version 一致且目标集合完整时为 `Synchronized`；存在单一可信状态但语言、
格式、缺失目标或失效目标要求收敛时为 `NeedsRegeneration`，并返回 `locale_mismatch`、`format_mismatch`、
`missing_targets`、`obsolete_targets` 原因；存在多个已知历史 locale/format 时为 `Mixed`；任一现有目标没有
可验证 provenance，或当前 bytes 与 provenance hash 不符时为 `Unknown`。状态计算不解析 Markdown 自然语言，
也不按当前 policy 猜测 legacy 输出。普通增量 overview 更新在 `Unknown` 状态下 fail closed；显式全库
regeneration 才能在 preflight、journal 与 verified backup 保护下替换异常 bytes。

preflight 生成新的 `operation_id` 和签名 plan token，并冻结 Repository revision、完整目标集合、concrete
locale、format contract version 与 target-set hash。start 在第一次 staging 写入前持久化 operation/context 和
全部 journal items。生成过程不长时间锁住资料库；commit 前重新比较 revision，变化时保持全旧并要求新 attempt。

preflight 向 UI 返回 concrete target locale、create/replace/delete 数量、managed-root 是否参与和目标 hash；
确认文案明确排除 AI、`README.md` 与用户正文。同一资料库的所有窗口观察同一 operation，只有发起窗口持有
确认、取消或恢复交互权。

取消只允许发生在 commit 之前，并删除 AreaMatrix-owned staging 后保持全旧。短 commit 开始后不可取消。
普通错误按逆序恢复旧字节和旧 provenance；进程崩溃可能让物理文件暂时处于中间状态。下次打开先验证
staged plan，完整时继续提交；否则验证 backup 并回滚。两者均无法验证时保持 recovery-required 并阻断普通
写入，不猜测成功。最终稳定状态只能是全旧或全新，这一合同不宣称多个独立
文件具有文件系统级瞬时原子交换能力。

staging、backup 和 journal 全部属于 `.areamatrix/`。相对路径白名单、旧/新 hash 和 managed block 校验必须
在 preflight 与 commit 各执行一次；任何 `README.md`、绝对路径、`..`、symlink/non-regular target 或非法
marker 都 fail closed。成功后写入 durable overview provenance，清理 staging/backup，但保留 operation
审计；回滚恢复原字节与原 provenance。
完整目标集合包含 classifier 中所有当前 category（包括空分类）。`nodes/` 下不再对应当前 category 的普通
`.md` 文件作为 obsolete AreaMatrix-owned output 纳入删除计划；删除也必须保存旧字节与 provenance，并在
取消、失败或 rollback 时恢复。symlink、目录、特殊文件、非 `.md` 文件或任何越界目标都会阻断操作。

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
- interface/content locale 变化不改变稳定 category order、file sort、selection、expanded state、scroll、focus、
  route、sheet 或 draft identity；follow-interface 只重投影 clean presentation，不增加 repository revision。
- pre-commit Repository revision drift 零写入失败；Retry 获得新的 operation ID。
- commit 崩溃注入后 reopen 必须恢复为全旧或全新，且恢复前阻断普通 mutation。
- cancellation 在 commit 前保持全旧，commit 开始后返回不可取消状态。

## Related

- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [storage.md](storage.md)
- [change-log.md](change-log.md)
