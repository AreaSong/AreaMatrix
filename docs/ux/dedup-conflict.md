# 去重与冲突处理（Dedup & Conflict）

> 定义导入与后续同步过程中，内容重复（hash dup）、重名冲突（same name different content）、iCloud Conflicted Copy 等冲突类型的用户对话流、默认策略与可逆性。本文为 UX 契约，工程实现细节参考 storage / change-log / source-of-truth。
>
> 阅读时长：约 16 分钟。

---

## 目标与成功标准

### 目标

1. **默认安全**：默认不覆盖、不丢数据。
2. **用户可控**：用户能明确选择“保留两份/跳过/替换/仅索引”。
3. **批量不被打断**：批量导入时冲突不弹 N 次对话框，而是用汇总策略。
4. **可逆**：替换/删除必须可追溯，并在 undo 能力启用后支持撤销。
5. **冲突可见**：iCloud/外部变更产生的冲突不能静默吞掉。

### 成功标准（验收）

- **D1**：拖入重复文件 → ImportSheet 在确认前提示重复，并提供 3 个选项。
- **D2**：批量导入 100 个文件，其中 10 个重复 → 默认跳过并给摘要，用户可展开逐项处理。
- **D3**：同名不同内容冲突 → 默认“自动编号保留两份”，不覆盖。
- **D4**：用户选择 Replace → 需要二次确认 + 明确写入 change_log。
- **D5**：iCloud Conflicted Copy → UI 标记冲突并引导用户解决。

---

## 冲突类型定义

| 类型 | 判定 | 典型场景 | 风险 |
|---|---|---|---|
| 内容重复（Dedup） | SHA256 相同 | 重复拖入同一文件 | 🟢 低 |
| 重名不同内容（Name conflict） | 目标路径同名但 hash 不同 | 两份不同版本同名 | 🟡 中 |
| 路径冲突（Path conflict） | 目标目录下已存在同名（不一定同内容） | 多人同步/批量导入 | 🟡 中 |
| iCloud 冲突文件（Conflicted Copy） | 文件名匹配系统模式 | iCloud 同步冲突 | 🔴 高（用户期望强） |
| 外部变更冲突（SoT 冲突） | DB 与 FS 不一致 | 手动移动/删除/重建 DB | 🔴 高 |

---

## 导入过程冲突处理（ImportSheet 内）

### 单文件：重复（hash dup）

#### UI（ImportSheet 冲突区）

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 冲突：内容重复                                                                 │
│                                                                              │
│  资料库中已存在相同内容的文件：                                                │
│    docs/合同_2026Q1_客户A.pdf（导入于 2026-04-01）                              │
│                                                                              │
│  选择：                                                                        │
│   (●) 跳过导入（推荐）                                                         │
│   ( ) 保留两份（自动编号）                                                     │
│   ( ) 替换已有文件（危险）                                                     │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### 默认策略

- 默认选择：**跳过导入**。
- 如果用户选“保留两份”：建议命名自动加后缀（2）或时间戳。
- 如果用户选“替换”：必须触发二次确认（见后文）。

### 单文件：重名不同内容

#### UI（冲突区）

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 冲突：目标位置已有同名文件                                                     │
│                                                                              │
│  已存在：docs/报告.pdf                                                         │
│  你的文件：报告.pdf（内容不同）                                                │
│                                                                              │
│  选择：                                                                        │
│   (●) 保留两份（自动编号，推荐）                                               │
│   ( ) 重命名导入文件…                                                          │
│   ( ) 替换已有文件（危险）                                                     │
└──────────────────────────────────────────────────────────────────────────────┘
```

#### 默认策略

- 默认：**保留两份（自动编号）**。
- “重命名导入文件”会激活命名输入框。

---

## Replace（二次确认）规范

Replace 是唯一可能造成用户“丢数据”的选择（即使有回收站/版本，也会让用户焦虑）。必须二次确认：

### 二次确认对话框（ASCII）

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 确认替换？                                                                     │
│                                                                              │
│  你将用新文件替换： docs/报告.pdf                                              │
│                                                                              │
│  说明：                                                                        │
│  • 该操作会写入改动日志。                                                      │
│  • 旧文件必须进入系统 Trash 或由安全 guard 保持可恢复。                         │
│                                                                              │
│  [ Cancel ]                                          [ Replace ]            │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Replace 的后果（产品侧约束）

- 旧文件必须移到系统 Trash；Trash 不可用时禁用 Replace，不提供永久删除替代。
- change_log 必须记录 Replace/Deleted/Restored 等（见 `modules/change-log.md`）。
- AreaMatrix 不维护 `.areamatrix/versions/` 版本仓库；可逆性来自 Trash、rollback guard 和 undo token。

---

## 批量导入的冲突策略（不打断）

### 批量策略面板

在多文件 ImportSheet 中，如果检测到冲突，提供“冲突处理策略”下拉：

- 重复（hash dup）：`Skip`（默认）/ `Keep both` / `Replace`（危险）
- 重名不同内容：`Keep both (auto-number)`（默认）/ `Ask per item` / `Replace`

### “Ask per item” 行为

`Ask per item` 始终进入 ImportSheet 内的逐项队列/列表，不为每个文件连续弹 modal。是否可进入由 Core
preview 中的 included、blocked 和 actionable 状态决定，不使用固定数量阈值。

### 批量结果摘要

导入结束 toast：

- “导入完成：成功 87，跳过 10（重复），保留两份 3”

并提供 `View details…` 打开结果列表（含每项原因）。

---

## iCloud Conflicted Copy（冲突解决 UX）

### 识别与标记

当发现文件名类似：

- `xxx (Conflicted Copy of <Mac>).pdf`

在 List 行前显示一个冲突标记：`🟠 conflict`（或专用 icon），并在 Detail 的 Meta 中提示：

> 这是 iCloud 生成的冲突副本。AreaMatrix 不会自动删除任何一个版本。

### 冲突解决入口

- 主入口是 Settings → Integrations → Review conflicts。
- 冲突列表展示两个候选版本，并可打开单项 resolver。
- 当前文件详情识别到 conflict signal 时可以路由到同一 resolver，但不维护第二套解决流程。

### 冲突解决最小版

先不做内容 diff，只做“选择保留”：

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 解决 iCloud 冲突                                                               │
│                                                                              │
│  发现两个版本：                                                                │
│   • 报告.pdf                     modified: 2026-04-01 10:20                  │
│   • 报告 (Conflicted Copy...).pdf modified: 2026-04-01 10:21                 │
│                                                                              │
│  选择：                                                                        │
│   (●) 保留两份（推荐）                                                         │
│   ( ) 仅保留第一份（把另一份移到回收站）                                       │
│   ( ) 仅保留第二份（把另一份移到回收站）                                       │
│                                                                              │
│  [ Cancel ]                                                   [ Apply ]      │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 外部变更冲突（SoT 冲突）的用户呈现

当系统检测到“DB 与 FS 不一致”且无法自动修复（极少数）：
- 在顶部显示 banner：`发现资料库不一致，需要修复索引 [Repair…]`
- Repair 页提供：
  - `Full rescan`（整库重扫）
  - `Collect diagnostics`（创建 repository snapshot 或脱敏诊断材料）

实现与算法参见：`docs/architecture/source-of-truth.md`。

---

## 文案（中英对照，关键按钮）

| Key | 中文 | English |
|---|---|---|
| conflict.dup.title | 冲突：内容重复 | Conflict: Duplicate content |
| conflict.name.title | 冲突：目标位置已有同名文件 | Conflict: Same name exists |
| conflict.skip | 跳过导入（推荐） | Skip (Recommended) |
| conflict.keepBoth | 保留两份（自动编号） | Keep both (auto-number) |
| conflict.replace | 替换已有文件（危险） | Replace existing (Dangerous) |
| replace.confirm.title | 确认替换？ | Confirm replace? |
| conflict.resolve | 解决冲突… | Resolve conflict… |

---

## 测试用例（产品验收清单）

- [ ] 单文件重复：默认 Skip，可改 Keep both / Replace（有二次确认）
- [ ] 单文件重名不同内容：默认 Keep both
- [ ] 批量 100 文件含 10 dup：不弹 10 次对话框，结束后摘要正确
- [ ] iCloud Conflicted Copy：行标记冲突，Detail 可进入 Resolve
- [ ] 外部变更导致不一致：banner + Repair 入口（至少提示）

---

## Related

- [drag-import-flow.md](drag-import-flow.md)
- [ui-states.md](ui-states.md)
- [../modules/storage.md](../modules/storage.md)
- [../modules/change-log.md](../modules/change-log.md)
- [../architecture/source-of-truth.md](../architecture/source-of-truth.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [../adr/0006-icloud-support.md](../adr/0006-icloud-support.md)
