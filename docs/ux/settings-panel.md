# 设置面板（Settings Panel）

> 定义 AreaMatrix 的设置面板信息架构（IA）与每一项设置的默认值、影响范围、风险提示、可恢复策略。面向工程实现的 wireframe 级规格，不含视觉稿。
>
> 阅读时长：约 18 分钟。

---

## 目标与成功标准

### 目标

1. **关键设置可发现**：资料库路径、默认存储模式、规则配置、诊断导出必须一眼找到。\n
2. **默认即最佳实践**：新用户不必改设置也能稳定使用。\n
3. **设置可解释**：每个开关都能说明“会改变什么”，并提供“恢复默认”。\n
4. **安全边界明确**：危险设置（Move 默认、Replace 默认）必须二次确认。\n
5. **与工程一致**：设置项命名与 `docs/` 里的概念一致（见 glossary）。\n

### 成功标准（验收）

- **S1**：用户能在 10 秒内找到“更换资料库路径”。\n
- **S2**：用户能找到“导出诊断包/查看日志”。\n
- **S3**：开启 Index-only 默认时会弹风险提示。\n
- **S4**：编辑 classifier.yaml 失败会显示行号，并可恢复上次有效版本。\n

---

## 信息架构（6 个一级 Tab）

| TabId | 名称 | 目标用户 | 主要内容 |
|---|---|---|---|
| general | 通用 | 所有人 | 默认存储模式、概览输出、语言、外观、快捷键提示 |
| repository | 资料库 | 所有人 | repoPath、更换/迁移、打开 Finder、容量信息 |
| classifier | 分类规则 | 高级用户 | 规则开关、YAML 编辑、校验、示例、导入导出 |
| integrations | 集成 | 少数 | iCloud 相关提示、Spotlight 排除建议（提示而非执行） |
| advanced | 高级 | 高级用户 | 性能/缓存/调试信号（仅 Debug）、危险开关 |
| about | 关于 | 所有人 | 版本、许可证、诊断、反馈链接 |

---

## 设置窗口布局（ASCII）

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ Settings                                                                      │
├───────────────┬──────────────────────────────────────────────────────────────┤
│ 通用          │ [General settings…]                                           │
│ 资料库         │                                                              │
│ 分类规则       │                                                              │
│ 集成           │                                                              │
│ 高级           │                                                              │
│ 关于           │                                                              │
└───────────────┴──────────────────────────────────────────────────────────────┘
```

---

## Tab：通用（general）

### 1) 默认存储模式（Default storage mode）

| Setting | 默认值 | 影响范围 |
|---|---|---|
| defaultStorageMode | Copy | ImportSheet 默认选项（仍允许每次更改） |

#### UI（ASCII）

```
默认存储模式：
 (●) Copy（推荐）  ( ) Move  ( ) Index-only
 说明：导入时仍可在 ImportSheet 临时更改。
```

#### 风险提示（Move / Index-only）

- 选择 Move 作为默认值：弹确认\n
  - “Move 会让源文件从原位置消失，适合整理 Downloads。确定吗？”\n
- 选择 Index-only：弹确认\n
  - “Index-only 不复制文件，源文件移动/删除会导致条目缺失。”\n

### 2) 概览输出（Overview output）

| Setting | 默认值 | 说明 |
|---|---|---|
| overviewOutput | GeneratedOnly | 默认只写 `.areamatrix/generated/`；可选维护根目录 `AREAMATRIX.md` |

#### UI（ASCII）

```
资料库概览：
 (●) 仅保存在 .areamatrix/generated/
 ( ) 同时在根目录生成 AREAMATRIX.md

说明：AreaMatrix 永远不会覆盖已有 README.md。
```

选择 `AREAMATRIX.md` 时若文件已存在：

- 如果包含 AreaMatrix 标记块：只维护标记块
- 如果不包含标记块：弹确认，说明会在文件末尾追加 AreaMatrix 托管段
- 永不把 `README.md` 作为自动输出目标

### 3) 忽略规则（Ignore rules）

| Setting | 默认值 | 说明 |
|---|---|---|
| ignoreRules | `.areamatrix/ignore.yaml` | 首次扫描、reindex、tree-scan 与 FSEvents 共用 |

UI 提供 `Open ignore.yaml`，用系统默认编辑器打开。`README.md` 不在默认忽略列表；`AREAMATRIX.md` 与 `.areamatrix/generated/` 始终由 Core 过滤。

### 4) 语言（Locale）

| Setting | 默认值 | 说明 |
|---|---|---|
| uiLocale | system | 跟随系统，支持 zh-CN / en |

### 5) 外观（Appearance）

| Setting | 默认值 |
|---|---|
| appearance | system |

（深色模式打磨属于 Stage 2，但设置项可以先有。）\n

---

## Tab：资料库（repository）

### 1) 当前资料库路径（repoPath）

展示只读路径 + 快捷操作：\n
- `Open in Finder`\n
- `Copy path`\n

```
当前资料库：
 ~/AreaMatrix/
 [ Open in Finder ] [ Copy path ]
```

### 2) 更换资料库（Change repo）

按钮：`Change repository…`\n
- 点击后走类似 first-launch 的 choosePath/validatePath\n
- 若选择一个已存在 repo：提示“将打开现有资料库”\n

### 3) 资料库健康（Health）

只读展示：\n
- DB schema version\n
- 文件条目数 / change_log 条目数\n
- staging 残留数（若>0显示 warning）\n
- 最近一次 rescan 时间\n

按钮：\n
- `Run integrity check`（耗时操作，显示进度）\n
- `Collect diagnostics…`\n

---

## Tab：分类规则（classifier）

### 1) 规则引擎开关（Stage 1 必须）

| Setting | 默认值 | 说明 |
|---|---|---|
| enableKeywordRules | true | 关键词匹配 |
| enableExtensionRules | true | 扩展名匹配 |
| fallbackToInbox | true | 兜底 inbox |

### 2) YAML 编辑器

必须提供：\n
- `Open classifier.yaml`（Finder）\n
- 内置 editor（推荐）\n
- `Validate` / `Save` / `Revert`（回到上次有效）\n
- `Export` / `Import`（分享规则）\n

#### 校验失败 UI（要求行号）

```
校验失败：categories[2].slug 重复（line 47）
[ Fix in editor ]  [ Revert to last valid ]
```

### 3) 示例模板

提供下拉：\n
- “研究者（论文/数据）”\n
- “设计师（素材/客户）”\n
- “开发者（代码/文档）”\n

对应内容引用 `docs/api/classifier-yaml.md` 的示例段落。\n

---

## Tab：集成（integrations）

### iCloud

这里只做提示与状态显示，不做复杂同步设置：\n

- 当前 repo 是否在 iCloud 路径\n
- iCloud 登录状态（若可检测）\n
- 占位符策略说明（按需下载）\n

按钮：\n
- `Open iCloud help`（跳到 `docs/adr/0006-icloud-support.md` 或应用内帮助）\n

---

## Tab：高级（advanced）

### 1) 性能与缓存

| Setting | 默认值 | 说明 |
|---|---|---|
| enableTreeCache | true | tree-scan 缓存 |
| listPageSize | 200 | 列表分页大小 |

### 2) 危险选项（需要二次确认）

- `Allow replace during import`（默认 false）\n
  - 开启后 ImportSheet 才显示 Replace 选项（参见 `dedup-conflict.md`）。\n

### 3) Debug 信号（仅 Debug build）

链接到 `docs/development/observability.md` 的 debug signals。\n

---

## Tab：关于（about）

必须包含：\n
- App version / Core version / schema version\n
- License：PolyForm Noncommercial\n
- 链接：GitHub / Issue / Discussions\n
- `Collect diagnostics…`\n
- `Open logs in Console`（提示命令或引导）\n

---

## “恢复默认”与“设置导出”规范

### 恢复默认

每个 tab 底部提供：\n
- `Reset this tab`（仅重置本 tab）\n
- `Reset all settings`（全局，需二次确认）\n

### 导出/导入

仅针对两类：\n
- classifier.yaml\n
- settings（可选，Stage 2）\n

导出格式：JSON 或 plist（工程决定），UX 只要求“可分享”。\n

---

## 文案（中英对照，关键按钮）

| Key | 中文 | English |
|---|---|---|
| settings.title | 设置 | Settings |
| settings.repo.change | 更换资料库… | Change repository… |
| settings.repo.openFinder | 在 Finder 中打开 | Open in Finder |
| settings.diagnostics.collect | 导出诊断包… | Collect diagnostics… |
| settings.classifier.validate | 校验 | Validate |
| settings.classifier.revert | 恢复上次有效版本 | Revert to last valid |
| settings.reset.all | 重置全部设置 | Reset all settings |

---

## 测试用例（产品验收清单）

- [ ] 通用：默认存储模式可改，Move/Index-only 有确认\n
- [ ] 资料库：能 Open in Finder、能 Change repository\n
- [ ] 分类规则：Validate/Safe/Revert 正常，错误带行号\n
- [ ] 高级：Replace 默认关闭，开启需要确认\n
- [ ] 关于：诊断包按钮存在且可用\n

---

## Related

- [first-launch.md](first-launch.md)
- [drag-import-flow.md](drag-import-flow.md)
- [classifier-calibration.md](classifier-calibration.md)
- [dedup-conflict.md](dedup-conflict.md)
- [../api/classifier-yaml.md](../api/classifier-yaml.md)
- [../development/observability.md](../development/observability.md)
- [../development/troubleshooting.md](../development/troubleshooting.md)
