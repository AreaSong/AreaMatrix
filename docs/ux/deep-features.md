# 深层功能（Undo / Tags / Batch / Shortcuts / Command Palette / Smart Lists）

> 定义 Stage 2 的“效率层”能力：撤销系统、标签、批量操作、快捷键体系、命令面板（Cmd+K）、智能列表。本文用 wireframe 级规格锁定交互与边界，工程可分批落地。
>
> 阅读时长：约 22 分钟。

---

## 目标与成功标准

### 目标

1. **可逆（Undo）可预期**：用户知道哪些操作能撤销、撤销多久、撤销后会发生什么。\n
2. **标签不替代分类**：标签是 cross-cutting（横切）维度，用于跨分类组织。\n
3. **批量操作安全**：批量操作要可预览影响、可取消、可回滚。\n
4. **键盘效率**：常见操作都有快捷键，且可发现（菜单提示）。\n
5. **命令面板统一入口**：高级操作都能 Cmd+K 搜到。\n

### 成功标准（验收）

- **DF1**：删除/移动/重命名/改分类能撤销（Stage 2）。\n
- **DF2**：多选 50 个文件 → 批量改分类/加标签/删除。\n
- **DF3**：Cmd+K 能执行：Import、Change category、Add tag、Open logs。\n
- **DF4**：保存搜索生成 Smart List，点击后进入“搜索模式”。\n

---

## 1) 撤销系统（Undo）

### 1.1 撤销范围（可逆性矩阵）

| 操作 | Stage 2 是否必须支持撤销 | 说明 |
|---|---|---|
| Import（Copy） | 🟡 可选 | 可撤销=删除导入文件（走回收站） |
| Import（Move） | 🔴 必须 | 撤销需要把文件移动回原位置（若可） |
| Rename | 🔴 必须 | 直接反向 rename |
| Move to category | 🔴 必须 | 反向移动 |
| Delete（Trash） | 🔴 必须 | Restore（从回收站恢复） |
| Edit note | 🟡 可选 | 可用版本文件/备份（或依赖编辑器） |
| Rule change | 🟡 可选 | revert classifier.yaml 上次有效 |

### 1.2 Undo UI 形态

#### toast + Undo（推荐）

每个可撤销操作完成后 toast：\n
- “已移动到 finance  [Undo]”\n

#### Undo 历史面板（可选）

菜单 View → Undo History（或侧栏一页）：\n
- 最近 20 条操作\n
- 可逐条撤销/重做\n

### 1.3 Undo 约束

- 只保证“最近 N 分钟或最近 N 条”（产品可配置，默认 50 条）\n
- 外部变更（FSEvents）造成的操作不提供 Undo（但会记录 change_log）\n

---

## 2) 标签系统（Tags）

### 2.1 标签模型（产品侧）

- 标签是字符串（slug + displayName 可选）\n
- 一文件可多个标签\n
- 标签可用于过滤与 Smart List\n

### 2.2 标签 UI 入口

#### Detail → Meta 区域

```
Tags:  [ urgent ] [ clientA ]  [+ Add…]
```

点击 `+ Add…` 弹 popover：\n
- 输入框 + 自动补全已有标签\n
- 回车创建新标签\n

#### List 多选批量加标签

多选时 Detail multi view 提供：`Add tag…`\n

### 2.3 标签与分类的关系（必须讲清楚）

提示文案：\n
> 分类决定“放哪儿”，标签决定“怎么横向组织”。\n

---

## 3) 批量操作（Batch actions）

### 3.1 触发入口

- List 多选（Shift/⌘）→ Detail 进入 multi summary（见 `ui-states.md` 附录）\n

### 3.2 批量动作清单

| 动作 | 默认策略 | 风险提示 |
|---|---|---|
| Change category… | 预览后执行 | 🟡 |
| Add tag… | 立即执行 | 🟢 |
| Delete… | 默认 Trash | 🔴（需确认） |

### 3.3 批量预览（Change category）

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 批量改分类                                                                     │
│                                                                              │
│  已选择 50 个文件                                                               │
│  改为： [ finance ▾ ]                                                          │
│                                                                              │
│  预览：将移动 50 个文件到 finance/                                             │
│                                                                              │
│  [ Cancel ]                                                   [ Apply ]      │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 3.4 批量删除确认

必须包含：\n
- 将移到回收站\n
- 可撤销（若支持 undo）\n
- 可选“仅从索引移除”（Index-only 文件更适用）\n

---

## 4) 快捷键体系（Shortcuts）

### 4.1 原则

- 与 macOS 常见习惯一致（⌘F 搜索、⌘, 设置）\n
- 菜单中显示快捷键，提升可发现性\n

### 4.2 建议清单（核心 20 个）

| 快捷键 | 动作 |
|---|---|
| ⌘, | 打开 Settings |
| ⌘F | 搜索 |
| ⌘I | Import… |
| ⌘K | 命令面板 |
| ⌘L | 聚焦 List |
| ⌘1/⌘2/⌘3 | Detail Tab（Meta/Log/Note） |
| Delete | 删除（Trash） |
| ⌘Z | Undo |
| ⇧⌘Z | Redo |
| ⌘O | 在 Finder 打开当前文件/目录 |
| ⌘R | Rescan（谨慎，Stage 2） |

---

## 5) 命令面板（Command Palette, Cmd+K）

### 5.1 目标

把“记不住菜单在哪”的操作集中到一个可搜索入口。\n

### 5.2 UI（ASCII）

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  Command…  [ search… ______________________________ ]                         │
│                                                                              │
│  Import files…                                                               │
│  Change repository…                                                          │
│  Change category…                                                            │
│  Add tag…                                                                    │
│  Open logs                                                                    │
│  Collect diagnostics…                                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 5.3 命令分类（建议）

- Repository\n
- Import\n
- Organize\n
- Diagnostics\n
- View\n

---

## 6) 智能列表（Smart Lists）

### 6.1 与 Saved Search 的关系

Saved Search 是“搜索规则”，Smart List 是“侧边栏的一个固定入口”。\n

### 6.2 侧边栏分组

```
Smart Lists
  最近合同
  本周发票
```

点击 Smart List：\n
- Tree 进入“搜索模式”节点\n
- List 显示结果\n
- banner 显示规则 + Clear\n

### 6.3 管理

右键 Smart List：\n
- Rename\n
- Duplicate\n
- Delete\n

---

## 文案（中英对照，关键按钮）

| Key | 中文 | English |
|---|---|---|
| undo.action | 撤销 | Undo |
| redo.action | 重做 | Redo |
| tags.add | 添加标签… | Add tag… |
| batch.changeCategory | 批量改分类… | Change category… |
| commandPalette.title | 命令… | Command… |
| smartList.title | 智能列表 | Smart Lists |

---

## 测试用例（产品验收清单）

- [ ] 移动/重命名/删除后 toast 提供 Undo\n
- [ ] 多选 50 项可批量改分类/加标签/删除\n
- [ ] Cmd+K 可执行 Import/Change repo/Open logs\n
- [ ] 保存搜索生成 Smart List，点击进入搜索模式\n

---

## Related

- [ui-states.md](ui-states.md)
- [search.md](search.md)
- [settings-panel.md](settings-panel.md)
- [../modules/change-log.md](../modules/change-log.md)
