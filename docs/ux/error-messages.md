# 错误文案与恢复路径（Error Messages & Recovery）

> 把工程侧 `CoreError`（见 `docs/api/error-codes.md`）映射为用户可理解、可执行、可恢复的 UI 反馈：toast、banner、alert、sheet 或 blocking page。本文定义每类错误的呈现、动作和诊断入口，并约束敏感上下文展示。
>
> 阅读时长：约 20 分钟。

---

## 目标与成功标准

### 目标

1. **用户看得懂**：不要直接展示“db error: busy”，要说人话。
2. **用户能做事**：每个错误都提供下一步（重试/更换路径/导出诊断/查看帮助）。
3. **不打断不该打断的**：低严重度用 toast，高严重度才 modal。
4. **隐私安全**：默认不展示包含用户名的绝对路径，必要时脱敏（`~`）。
5. **工程可定位**：需要诊断的错误页提供当前可用的 snapshot、脱敏报告或路径入口，并附错误码
   （CoreError variant）。

### 成功标准（验收）

- **E1**：同一错误在不同页面出现时，文案一致。
- **E2**：iCloud 占位符错误能引导用户“下载/重试/换本地路径”。
- **E3**：DB locked 错误不会让整个 App 死掉，用户能重试或导出诊断。
- **E4**：Internal 默认提供 Leave flow、Collect diagnostics 和 Open Issue；只有存在真实 restart
  动作时才显示 Restart。

---

## 严重程度 → UI 形态映射（统一标准）

沿用 `docs/api/error-codes.md` 的严重程度矩阵（low/medium/high/critical），并补充 UI 形态约束：

| Severity | UI 形态 | 典型时长/交互 | 适用 |
|---|---|---|---|
| low | toast | 3s 自动消失，可点击“详情” | 单个文件失败但不影响其他 |
| medium | banner | 可关闭，不阻断 | 可恢复异常、提示风险 |
| high | alert（modal） | 必须选择按钮 | 需要用户决策（Replace、Move 默认等） |
| critical | blocking page/modal | 必须离开当前失败流程或进入恢复 | repo 无法打开、DB 损坏、内部不变量失败 |

---

## 通用文案规则（必须遵守）

1. **标题一句话**：先说发生了什么，不说原因。
2. **原因第二句**：用可能原因列表，不要堆技术栈。
3. **主操作只有一个**：避免“按钮太多不敢点”。
4. **永远提供退路**：至少一个“更换路径/返回/取消”。
5. **不展示敏感数据**：绝对路径脱敏为 `~`，hash 只显示前 8 位。
6. **平台本地化**：Core 只提供稳定 code、field、arguments、recovery action IDs 和技术详情；Swift 在每次
   渲染时按当前界面语言解析，不把翻译后的句子存进 model、session、日志或 recovery state。
7. **未知错误可恢复展示**：未知 code 显示本地化通用标题与说明，原始 technical details 只放在展开区域，
   不能把技术文本直接提升为标题或据此选择按钮。

---

## CoreError → UI 规范表（总表）

> 说明：以下“示例文案”给出中英对照，工程可把 key 写入 i18n 资源。

| CoreError | Severity | 触发场景 | UI 形态 | 主操作 | 次操作 |
|---|---|---|---|---|---|
| Io | medium | 文件读写失败、磁盘满 | banner/alert | Retry | Collect diagnostics |
| Db | medium/critical | DB locked/corrupt | banner/blocking page | Retry / Repair | Collect diagnostics |
| Config | medium | 配置无效 | sheet | Open rules | Revert（仅 last-valid backup 存在时） |
| Validation | low | 输入或编辑草稿无效 | inline/toast | Fix input | — |
| Classify | low | 分类失败 | toast/banner | Use inbox | Report |
| Conflict | medium | 目标路径冲突 | sheet | Auto-rename | Rename… |
| RevisionConflict | medium | Repository/AI content revision 已过期 | sheet/banner | Review changes | Reload latest |
| DuplicateFile | low | 内容重复 | sheet | Skip | Keep both |
| FileNotFound | low | 外部删除 | inline error/toast | Retry / Locate… | Remove from index |
| ExpiredAction | low | Undo/Redo token 已不可用 | toast | Refresh history | — |
| RepoNotInitialized | high | repo 不完整 | blocking page | Re-initialize | Change repo |
| InvalidPath | low | 路径非法 | inline/toast | Change path | — |
| ICloudPlaceholder | medium | iCloud 未下载 | sheet | Download & retry | Switch to local |
| StagingRecoveryRequired | high | 导入暂存必须先恢复 | blocking recovery | Open recovery | Cancel |
| PermissionDenied | high | 无权限 | alert/blocking page | Choose folder | Help |
| Internal | critical | 未预期内部失败 | current-page blocking recovery | Collect diagnostics | Leave flow / Open Issue |

---

## 各错误类型详细规格

### 1) CoreError::Io（文件 IO 错误）

#### 常见子类（文案要区分）

- 磁盘空间不足（ENOSPC）
- 资源忙（EBUSY）
- 文件损坏/不可读

#### Banner（medium）示例

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 文件操作失败                                                                    │
│ 可能原因：磁盘空间不足，或文件正在被其他应用占用。                               │
│ [ Retry ]   [ Collect diagnostics… ]                                           │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### Alert（high）示例（磁盘满）

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 磁盘空间不足                                                                    │
│ 当前资料库位置没有足够空间完成这次操作。                                         │
│                                                                              │
│ [ Choose another folder… ]                                 [ OK ]            │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### 中英文案 key（示例）

| Key | 中文 | English |
|---|---|---|
| err.io.title | 文件操作失败 | File operation failed |
| err.io.hint | 可能原因：磁盘空间不足，或文件正在被其他应用占用。 | Possible causes: low disk space, or the file is in use. |
| err.io.retry | 重试 | Retry |

---

### 2) CoreError::Db（数据库错误）

#### 2.1 DB locked（medium）

UI 形态：List/Detail 内联错误卡 + Retry，不阻断 Tree。

```text
无法加载数据：数据库被占用（database is locked）。
[ Retry ] [ Collect diagnostics… ]
```

主动作：Retry（指数退避可由工程实现）
次动作：Collect diagnostics

#### 2.2 DB corrupted（critical）

UI 形态：全屏 blocking（repoError），必须修复或换 repo。

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 资料库索引损坏                                                                  │
│ 你的文件仍在资料库目录中，但索引数据库无法读取。                                 │
│                                                                              │
│ 你可以：                                                                      │
│ [ Repair index… ]   [ Open repo in Finder ]   [ Collect diagnostics… ]        │
│                                                                              │
│ 说明：Repair 会尝试重建索引，不会删除你的资料库文件。                           │
└──────────────────────────────────────────────────────────────────────────────┘
```

Repair（修复）最小实现策略（产品侧）：
- 当前可先提供“Full rescan”按钮（重扫重建索引）

---

### 3) CoreError::Config（配置错误，classifier.yaml）

UI 形态：sheet（不阻断主界面，但阻断“规则生效”）。

必须包含：
- 经过控制的 reason；Swift 不解析 reason 来决定动作或位置
- `Open rules`（打开 editor）
- 仅当 last-valid backup 存在时显示 `Revert to last valid`

位置和语义呈现规则：

- 只有 Core 明确提供 parse location 时，才显示行号/列号；UI 不从 reason 正则提取或猜测位置。
- YAML 文件解析错误可以显示 Core 提供的 line/column。
- 可视化 editor 的语义校验错误显示 field/rule + reason，不要求行号，也不得伪造源码位置。

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 分类规则无效                                                                    │
│ 规则“Receipts”的字段 slug 重复。                                                │
│                                                                              │
│ [ Open rules… ]  [ Revert to last valid ]  （仅有有效备份时）                  │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

### 4) CoreError::ICloudPlaceholder（iCloud 占位符）

UI 形态：sheet（用户需要选择“下载/换路径”）。

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 文件尚未从 iCloud 下载                                                         │
│ 该文件当前是占位符（.icloud）。需要下载后才能导入/计算 hash。                   │
│                                                                              │
│ [ Download & retry ]   [ Switch to local repo… ]   [ Cancel ]                 │
└──────────────────────────────────────────────────────────────────────────────┘
```

产品策略：
- 只有用户点击 Download & retry 后，macOS 平台层才请求下载并显示进度
- Core、watcher 和普通 Retry 都不得隐式触发 iCloud 下载
- Switch to local repo 跳到 first-launch 的 choosePath

---

### 5) CoreError::DuplicateFile / Conflict（导入冲突）

这类错误原则上应该在 ImportSheet 内解决（见 `dedup-conflict.md`），不应在导入完成后才以 toast 抛给用户。

若仍发生：
- 用 sheet 展示“本次导入已跳过 N 个冲突项”，并提供“查看详情”。

Repository config 的 `repo_config_revision_conflict` 不使用路径冲突文案。UI 保留本地 dirty fields，展示
expected/current revision 的受控摘要，并提供 Reload latest 或 Review changes；只有用户 review 后显式再次
Save 才能基于新 revision 写入。AI summary 的 content revision conflict 同样保留草稿，禁止自动 retry、
字符串匹配或静默 merge。
Repository 的 Review 视图按 dirty field 显示原保存值、最新持久化值和本地草稿；Review 只更新可见基线，
不立即写入，也不提供 force overwrite。Classifier 使用同一原则，但冻结 editing locale，只比较该语言和
受影响规则字段，另一语言 map 保持只读。

---

### 6) CoreError::PermissionDenied（权限）

两类：
- 单个文件无权限（medium）：toast + 跳过该项
- repo 目录无权限（critical）：全屏阻断 + 换路径

单文件 toast：
- “无法读取该文件（权限不足），已跳过。”

repo blocking：
- “无法写入资料库位置，请选择其他文件夹。”

---

### 7) CoreError::Validation / ExpiredAction / StagingRecoveryRequired

- `Validation`：在对应输入控件附近显示原因；修正输入后才允许重新提交。
- `ExpiredAction`：提示操作已过期并刷新 Undo History；不得猜测性执行反向文件操作。
- `StagingRecoveryRequired`：留在 import/startup recovery 上下文，展示 residue 路径的受控摘要；
  不自动删除 staging 文件，也不跳过恢复继续导入。

### 8) CoreError::Internal（内部错误）

UI 形态：当前页面或流程的 blocking recovery（critical）。资料库打开失败可以使用全屏页面；
sheet 内部失败应留在 sheet 上下文，不能假设存在统一全局重启页。

默认动作是 Leave flow、Collect diagnostics 和 Open Issue。Restart 不是默认兜底；只有当前页面接入真实、
可执行且经过验证的 restart 动作时才显示该按钮，不能用关闭 sheet、重载 view 或占位 callback 冒充重启。

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 遇到内部错误                                                                    │
│ AreaMatrix 遇到了未知问题。请保留当前状态并收集诊断材料。                        │
│                                                                              │
│ [ Leave flow ]   [ Collect diagnostics… ]   [ Open Issue… ]                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 诊断入口统一规范

支持 diagnostics 的 medium+ 错误至少提供一个真实入口：

- repository diagnostics：创建 `.areamatrix/diagnostics/index-*.db`，并按存在性复制 WAL/SHM。
  该 snapshot 不含用户文件正文，但包含路径、文件名、标签、笔记和其他 metadata；不能称为全文脱敏。
- About diagnostics：在 Application Support 下创建按专用合同脱敏的文本目录。
- `Open logs`：只打开已存在的 `.areamatrix/logs/`；当前不保证应用会创建或写入该目录。

当前没有统一 zip diagnostics bundle、自动 OSLog 收集或自动上传。
repository diagnostics 分享前必须由用户审阅 snapshot 及其 companion files。

隐私说明必须出现一次：
> 诊断信息保存在你的本地，不会自动上传。

---

## 文案（中英对照，关键按钮）

| Key | 中文 | English |
|---|---|---|
| action.retry | 重试 | Retry |
| action.cancel | 取消 | Cancel |
| action.collectDiagnostics | 收集诊断材料… | Collect diagnostics… |
| action.changeRepo | 更换资料库… | Change repository… |
| action.openFinder | 在 Finder 中打开 | Open in Finder |
| action.leaveFlow | 离开当前流程 | Leave flow |
| action.openIssue | 打开 Issue… | Open Issue… |
| action.downloadRetry | 下载并重试 | Download & retry |
| action.switchLocal | 切换到本地资料库… | Switch to local repo… |

---

## 测试用例（产品验收清单）

- [ ] Import 中遇到单个文件权限不足：跳过并 toast，不中断批量
- [ ] DB locked：List 内联错误可 Retry，Tree 可继续操作
- [ ] DB corrupted：全屏 blocking，能 Open in Finder/Collect diagnostics
- [ ] Config 始终显示受控 reason；仅 Core 提供 parse location 时显示行列
- [ ] 可视化规则语义错误显示 field/rule + reason，不要求行号
- [ ] Config 仅在 last-valid backup 存在时可 Revert；Swift 不解析 reason 决定动作
- [ ] iCloud placeholder：sheet 提供 Download & retry 与 Switch local
- [ ] Validation：输入位置显示原因，不提交无效草稿
- [ ] ExpiredAction：刷新 Undo History，不猜测性执行
- [ ] StagingRecoveryRequired：进入恢复上下文，不自动删除 residue
- [ ] Internal：当前失败页面含 Leave flow、Collect diagnostics 和 Open Issue；Restart 仅在真实动作存在时显示

---

## Related

- [../api/error-codes.md](../api/error-codes.md)
- [../development/observability.md](../development/observability.md)
- [../development/troubleshooting.md](../development/troubleshooting.md)
- [first-launch.md](first-launch.md)
- [drag-import-flow.md](drag-import-flow.md)
- [ui-states.md](ui-states.md)
