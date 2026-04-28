# 搜索（Search UX）

> 定义 Stage 2 搜索能力的产品行为：搜索入口、作用域（文件名/笔记/元数据）、过滤与排序、历史与保存搜索、以及高级查询语法。本文先锁定 UX 概念与交互，工程实现可从轻到重逐步落地。
>
> 阅读时长：约 16 分钟。

---

## 目标与成功标准

### 目标

1. **比 Finder 更“知道我想找什么”**：默认按“最近导入/最近修改”对齐资料管理任务。\n
2. **范围明确**：用户知道自己是在搜“当前分类”还是“全库”。\n
3. **可组合**：关键词 + 过滤 + 排序能覆盖 80% 场景。\n
4. **可复用**：常用查询可以保存为“智能列表”。\n
5. **不做承诺过早**：Stage 2 只做文件名+笔记+部分元数据；全文/OCR 属于 Stage 3。\n

### 成功标准（验收）

- **Q1**：⌘F 聚焦搜索框，输入即出结果（debounce）。\n
- **Q2**：用户可一键切换“当前分类/全库”。\n
- **Q3**：支持基本过滤：category/type/date/tag（tag Stage 2）。\n
- **Q4**：支持保存搜索并在侧边栏显示“智能列表”。\n
- **Q5**：高级查询语法可选（不强迫），错误时有提示。\n

---

## 入口与布局

### 入口

- Toolbar 右侧提供 Search field\n
- 快捷键：`⌘F`\n
- Cmd+K 命令面板（Stage 2）：`Search…`\n

### 搜索框（ASCII）

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ Toolbar: [Repo ▾]  [ 🔍 Search in: All ▾  query… ]   [Filters]               │
└──────────────────────────────────────────────────────────────────────────────┘
```

“Search in: All/Current” 下拉必须可见，避免用户误解范围。\n

---

## 搜索作用域（Scope）

| Scope | 含义 | 默认 |
|---|---|---|
| Current node | 当前 Tree 选中节点范围 | 当用户已在某分类且开始输入时默认 |
| All repo | 全库 | 当用户从空态或快捷键进入时默认 |

切换 scope 不清空 query（只刷新结果）。\n

---

## 搜索对象与字段（Stage 2）

### 必须支持

- 文件名（name）\n
- 相对路径（path）\n
- 伴生笔记（note content）\n
- 分类（category）\n

### 可选支持（元数据）

- 导入时间（imported_at）\n
- 修改时间（modified_at）\n
- 文件类型（extension/type）\n
- 大小（size）\n
- hash 前缀（debug）\n

### 明确不支持（Stage 3 才支持）

- PDF/图片 OCR\n
- 文件内容全文\n
- 语义相似检索\n

---

## 结果列表呈现

### 基本呈现

搜索结果仍使用 List 表格，但顶部显示“搜索模式”banner：\n

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 搜索：\"合同\"  范围：全库  结果：42  [Clear]                                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

结果行高亮命中片段（文件名/路径），笔记命中显示摘要（1-2 行）。\n

### 排序默认值

默认排序建议：`imported_at desc`，并提供下拉：\n
- relevance（若有）\n
- newest imported\n
- newest modified\n
- name A→Z\n

---

## Filters（过滤器）

Filters 按钮打开 popover：\n

```
Category: [All ▾]
Type:     [All ▾]
Date:     [Any ▾]  (Last 7 days / Last 30 days / Custom…)
Tags:     [Any ▾]  (Stage 2)
[ Reset filters ]
```

过滤器变化应立即生效，不需要“Apply”。\n

---

## 保存搜索（Saved Search / Smart List）

### 目标

把常用查询固定到侧边栏（类似 Finder 的 Smart Folder）。\n

### 入口

在搜索 banner 上提供：`Save…`\n

### Save 对话框（ASCII）

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 保存搜索                                                                       │
│                                                                              │
│ 名称： [ 最近合同 __________________________________ ]                        │
│ 规则： query=\"合同\" scope=All date=Last30Days category=finance               │
│                                                                              │
│ [ Cancel ]                                                   [ Save ]        │
└──────────────────────────────────────────────────────────────────────────────┘
```

保存后侧边栏出现 “Smart Lists” 分组：\n
- 最近合同\n
- 本周发票\n

（Smart Lists 的详细交互在 `deep-features.md` 扩展。）\n

---

## 高级查询语法（可选）

### 设计原则

- **不强迫用户学习**：UI 有 filters 与 scope，语法是 power-user bonus。\n
- **语法可提示**：输入 `kind:` 时弹补全。\n

### 建议语法（示例）

| 语法 | 示例 | 含义 |
|---|---|---|
| `kind:` | `kind:pdf` | 文件类型 |
| `cat:` | `cat:finance` | 分类 |
| `after:` | `after:2026-04-01` | 导入/修改时间下界（工程决定） |
| `before:` | `before:2026-04-30` | 时间上界 |
| `tag:` | `tag:urgent` | 标签（Stage 2） |
| `note:` | `note:\"invoice\"` | 只在笔记中搜 |

### 错误提示

输入无法解析时：\n
- 不要清空结果\n
- banner 提示：`无法解析：after:2026-13-01（月份应为 01-12）`\n

---

## 空结果（No results）规范

必须给“下一步”：\n
- `Clear filters`\n
- `Search in All`（若当前 scope=Current）\n
- `Create note`（若用户搜索笔记内容，Stage 2 可选）\n

```
没有结果
尝试：清除过滤器 / 切换到全库 / 检查拼写
[ Clear filters ] [ Search in All ]
```

---

## 文案（中英对照，关键按钮）

| Key | 中文 | English |
|---|---|---|
| search.scope.all | 全库 | All |
| search.scope.current | 当前分类 | Current |
| search.clear | 清除 | Clear |
| search.save | 保存… | Save… |
| search.noResults | 没有结果 | No results |
| search.resetFilters | 清除过滤器 | Reset filters |

---

## 测试用例（产品验收清单）

- [ ] ⌘F 聚焦搜索框，输入 debounce 更新结果\n
- [ ] scope 切换 All/Current 生效\n
- [ ] Filters popover 可设置 category/type/date\n
- [ ] 保存搜索后侧边栏出现 Smart List\n
- [ ] 高级语法补全与错误提示\n

---

## Related

- [ui-states.md](ui-states.md)
- [deep-features.md](deep-features.md)
- [../modules/tree-scan.md](../modules/tree-scan.md)
- [../architecture/data-model.md](../architecture/data-model.md)
