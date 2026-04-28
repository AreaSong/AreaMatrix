# 错误文案与恢复路径（Error Messages & Recovery）

> 把工程侧 `CoreError`（见 `docs/api/error-codes.md`）映射为用户可理解、可执行、可恢复的 UI 反馈：toast/banner/alert/sheet/fullscreen。本文定义每类错误的“呈现形态 + 文案 + 主操作/次操作 + 诊断入口”，并约束隐私（不泄露绝对路径/用户名）。
>
> 阅读时长：约 20 分钟。

---

## 目标与成功标准

### 目标

1. **用户看得懂**：不要直接展示“db error: busy”，要说人话。\n
2. **用户能做事**：每个错误都提供下一步（重试/更换路径/导出诊断/查看帮助）。\n
3. **不打断不该打断的**：低严重度用 toast，高严重度才 modal。\n
4. **隐私安全**：默认不展示包含用户名的绝对路径，必要时脱敏（`~`）。\n
5. **工程可定位**：每个错误页都有“诊断包/日志入口”，并附错误码（CoreError variant）。\n

### 成功标准（验收）

- **E1**：同一错误在不同页面出现时，文案一致。\n
- **E2**：iCloud 占位符错误能引导用户“下载/重试/换本地路径”。\n
- **E3**：DB locked 错误不会让整个 App 死掉，用户能重试或导出诊断。\n
- **E4**：Internal/崩溃路径提供“重启/导出诊断/提交 issue”入口。\n

---

## 严重程度 → UI 形态映射（统一标准）

沿用 `docs/api/error-codes.md` 的严重程度矩阵（low/medium/high/critical），并补充 UI 形态约束：

| Severity | UI 形态 | 典型时长/交互 | 适用 |
|---|---|---|---|
| low | toast | 3s 自动消失，可点击“详情” | 单个文件失败但不影响其他 |
| medium | banner | 可关闭，不阻断 | 可恢复异常、提示风险 |
| high | alert（modal） | 必须选择按钮 | 需要用户决策（Replace、Move 默认等） |
| critical | fullscreen blocking | 必须修复/换 repo | repo 无法打开、DB 损坏严重 |

---

## 通用文案规则（必须遵守）

1. **标题一句话**：先说发生了什么，不说原因。\n
2. **原因第二句**：用可能原因列表，不要堆技术栈。\n
3. **主操作只有一个**：避免“按钮太多不敢点”。\n
4. **永远提供退路**：至少一个“更换路径/返回/取消”。\n
5. **不展示敏感数据**：绝对路径脱敏为 `~`，hash 只显示前 8 位。\n

---

## CoreError → UI 规范表（总表）

> 说明：以下“示例文案”给出中英对照，工程可把 key 写入 i18n 资源。

| CoreError | Severity | 触发场景 | UI 形态 | 主操作 | 次操作 |
|---|---|---|---|---|---|
| Io | medium | 文件读写失败、磁盘满 | banner/alert | Retry | Collect diagnostics |
| Db | medium/critical | DB locked/corrupt | banner/fullscreen | Retry / Repair | Collect diagnostics |
| Config | medium | YAML 无效 | sheet | Open rules | Revert |
| Classify | low/medium | 分类失败 | toast/banner | Use inbox | Report |
| Conflict | medium | 目标路径冲突 | sheet | Auto-rename | Rename… |
| DuplicateFile | low/medium | 内容重复 | sheet | Skip | Keep both |
| FileNotFound | low | 外部删除 | toast | Remove from index | Locate… |
| RepoNotInitialized | critical | repo 不完整 | fullscreen | Re-initialize | Change repo |
| InvalidPath | medium | 路径非法 | alert | Change path | — |
| ICloudPlaceholder | medium | iCloud 未下载 | sheet | Download & retry | Switch to local |
| PermissionDenied | medium/critical | 无权限 | alert/fullscreen | Choose folder | Help |
| Internal | critical | panic/未知错误 | fullscreen | Restart | Collect diagnostics |

---

## 各错误类型详细规格

### 1) CoreError::Io（文件 IO 错误）

#### 常见子类（文案要区分）

- 磁盘空间不足（ENOSPC）\n
- 资源忙（EBUSY）\n
- 文件损坏/不可读\n

#### Banner（medium）示例

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 文件操作失败                                                                    │
│ 可能原因：磁盘空间不足，或文件正在被其他应用占用。                               │
│ [ Retry ]   [ Collect diagnostics… ]                                           │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### Alert（high）示例（磁盘满）

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 磁盘空间不足                                                                    │
│ AreaMatrix 需要至少 1GB 可用空间来完成导入与 staging。                           │
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

```
无法加载数据：数据库被占用（database is locked）。
[ Retry ] [ Collect diagnostics… ]
```

主动作：Retry（指数退避可由工程实现）\n
次动作：Collect diagnostics\n

#### 2.2 DB corrupted（critical）

UI 形态：全屏 blocking（repoError），必须修复或换 repo。

```
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

Repair（修复）最小实现策略（产品侧）：\n
- Stage 1 可先提供“Full rescan”按钮（重扫重建索引）\n

---

### 3) CoreError::Config（配置错误，classifier.yaml）

UI 形态：sheet（不阻断主界面，但阻断“规则生效”）。\n

必须包含：\n
- 错误位置（行号）\n
- `Open rules`（打开 editor）\n
- `Revert to last valid`\n

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 分类规则无效                                                                    │
│ categories[2].slug 重复（line 47）                                              │
│                                                                              │
│ [ Open rules… ]  [ Revert to last valid ]                                      │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

### 4) CoreError::ICloudPlaceholder（iCloud 占位符）

UI 形态：sheet（用户需要选择“下载/换路径”）。\n

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 文件尚未从 iCloud 下载                                                         │
│ 该文件当前是占位符（.icloud）。需要下载后才能导入/计算 hash。                   │
│                                                                              │
│ [ Download & retry ]   [ Switch to local repo… ]   [ Cancel ]                 │
└──────────────────────────────────────────────────────────────────────────────┘
```

产品策略：\n
- Download & retry 触发协调读取并显示进度\n
- Switch to local repo 跳到 first-launch 的 choosePath\n

---

### 5) CoreError::DuplicateFile / Conflict（导入冲突）

这类错误原则上应该在 ImportSheet 内解决（见 `dedup-conflict.md`），不应在导入完成后才以 toast 抛给用户。\n

若仍发生：\n
- 用 sheet 展示“本次导入已跳过 N 个冲突项”，并提供“查看详情”。\n

---

### 6) CoreError::PermissionDenied（权限）

两类：\n
- 单个文件无权限（medium）：toast + 跳过该项\n
- repo 目录无权限（critical）：全屏阻断 + 换路径\n

单文件 toast：\n
- “无法读取该文件（权限不足），已跳过。”\n

repo blocking：\n
- “无法写入资料库位置，请选择其他文件夹。”\n

---

### 7) CoreError::Internal（内部错误）

UI 形态：全屏 blocking（critical），并引导导出诊断包。\n

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 遇到内部错误                                                                    │
│ AreaMatrix 遇到了未知问题。你可以重启应用，或导出诊断包提交给维护者。            │
│                                                                              │
│ [ Restart ]   [ Collect diagnostics… ]   [ Open Issue… ]                      │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 诊断入口统一规范

所有 medium+ 错误必须提供至少一个诊断入口：\n
- `Collect diagnostics…`：导出 zip（见 `docs/development/observability.md`）\n
- `Open logs`：打开 Console 的过滤提示（或展示命令）\n

隐私说明必须出现一次：\n
> 诊断信息保存在你的本地，不会自动上传。\n

---

## 文案（中英对照，关键按钮）

| Key | 中文 | English |
|---|---|---|
| action.retry | 重试 | Retry |
| action.cancel | 取消 | Cancel |
| action.collectDiagnostics | 导出诊断包… | Collect diagnostics… |
| action.changeRepo | 更换资料库… | Change repository… |
| action.openFinder | 在 Finder 中打开 | Open in Finder |
| action.restart | 重启 | Restart |
| action.openIssue | 打开 Issue… | Open Issue… |
| action.downloadRetry | 下载并重试 | Download & retry |
| action.switchLocal | 切换到本地资料库… | Switch to local repo… |

---

## 测试用例（产品验收清单）

- [ ] Import 中遇到单个文件权限不足：跳过并 toast，不中断批量\n
- [ ] DB locked：List 内联错误可 Retry，Tree 可继续操作\n
- [ ] DB corrupted：全屏 blocking，能 Open in Finder/Collect diagnostics\n
- [ ] Config YAML 无效：sheet 显示行号，可 Revert\n
- [ ] iCloud placeholder：sheet 提供 Download & retry 与 Switch local\n
- [ ] Internal：全屏页含 Restart 与诊断入口\n

---

## Related

- [../api/error-codes.md](../api/error-codes.md)
- [../development/observability.md](../development/observability.md)
- [../development/troubleshooting.md](../development/troubleshooting.md)
- [first-launch.md](first-launch.md)
- [drag-import-flow.md](drag-import-flow.md)
- [ui-states.md](ui-states.md)
