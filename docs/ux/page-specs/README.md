# 逐页 UI 开发规格索引（Page Specs）

> 本目录把 `docs/ux/` 中按功能域组织的 UX 文档，整理为按阶段、逐页面的开发规格。目标读者是后续 macOS / 多端 UI 开发者。
>
> 阅读时长：约 6 分钟。

---

## 定位

`docs/ux/page-specs/` 是开发落地视角的 UI 规格层：

- 上游事实源：`docs/ux/`、`docs/product/`、`docs/roadmap/`、`tasks/prompts/`。
- 下游用途：实现 SwiftUI / 多端原生 UI 时，逐页对照开发与验收。
- 不包含：SwiftUI 代码、像素级视觉稿、平台实现细节、数据库或 Core 算法。

若本目录与功能域 UX 文档冲突，以功能域 UX 文档和架构文档为准；本目录应随后修正。

---

## 文档清单

| 文档 | 范围 | 用途 |
|---|---|---|
| [stage-1-mvp.md](stage-1-mvp.md) | macOS MVP | 阶段索引；单页文件在 `stage-1-mvp/` |
| [stage-2-experience.md](stage-2-experience.md) | 体验完善 | 阶段索引；单页文件在 `stage-2-experience/` |
| [stage-3-ai.md](stage-3-ai.md) | 智能化 | 阶段索引；单页文件在 `stage-3-ai/` |
| [stage-4-multiplatform.md](stage-4-multiplatform.md) | 多端 | 阶段索引；单页文件在 `stage-4-multiplatform/` |

目录结构：

```text
docs/ux/page-specs/
  stage-1-mvp.md
  stage-1-mvp/
    S1-01-welcome.md
    S1-02-choose-path.md
    ...
  stage-2-experience.md
  stage-2-experience/
    S2-01-search-results.md
    ...
```

推荐阅读顺序：

```text
stage-1-mvp.md
  -> stage-2-experience.md
  -> stage-3-ai.md
  -> stage-4-multiplatform.md
```

---

## 页面 ID 命名

页面 ID 使用稳定编号，便于任务、Issue、测试用例和截图对齐：

| 前缀 | 阶段 | 示例 |
|---|---|---|
| `S1-` | Stage 1 MVP | `S1-01 welcome` |
| `S2-` | Stage 2 体验完善 | `S2-01 search-results` |
| `S3-` | Stage 3 智能化 | `S3-01 ai-settings` |
| `S4-` | Stage 4 多端 | `S4-IOS-01 connect-repo` |

页面 ID 一旦被实现或进入测试用例，不应随意重命名；需要重命名时，在文档中保留旧 ID 的迁移说明。

---

## 单页规格模板

每个页面使用同一组字段。单页文件要达到“可以直接交给 IDE / agent 开发”的粒度，不只写摘要。字段允许合并，但不能删除关键语义：

```markdown
# Sx-00 page-id - 页面名称

> 所属阶段：Stage X
> 页面 ID：Sx-00
> 页面类型：...
> 页面文件：`Sx-00-page-id.md`
> 上级索引：...

## 开发位置

- 目标平台
- 建议目录
- 建议组件
- 实现说明

## 页面背景

说明这是什么页面、是否是完整窗口 / sheet / popover / 主窗口局部区域，从哪里进入，完成、取消、失败后去哪里。

## 整体风格

说明平台风格、信息密度、安全感、哪些视觉表达不要做。

## 内容结构

逐块写清楚页面上出现什么：标题、说明文案、字段、示例数据、表格列、输入框、按钮、提示文案。

## 状态展开

逐项写正常态、加载态、空态、错误态、禁用态、危险态。需要时写出具体文案。

## 交互含义

写清点击、选择、拖拽、键盘、跳转、自动刷新，以及哪些操作不会立即写文件。

## 可访问性

写清键盘、VoiceOver、颜色不可作为唯一状态表达。

## 数据与依赖

写清需要 Core API、平台能力、状态 store、mock 数据边界。

## 验收清单

写成开发完成后可逐条验证的 checklist。

## 来源

对应事实源；若为推导，标注“依据现有文档推导”。
```

---

## 来源标注规则

来源分三类：

1. **直接来源**：现有 UX 文档已有页面、ASCII 布局或明确交互。
2. **组合来源**：多个文档共同决定页面，例如主窗口 + change_log + note API。
3. **推导来源**：路线图或任务只定义能力，页面由本文合理补齐。

页面来源写法：

```text
来源：docs/ux/first-launch.md#逐页规格（直接）
来源：docs/ux/ui-states.md + docs/api/core-api.md（组合）
来源：docs/roadmap/milestones.md，依据现有文档推导
```

推导内容必须遵守 AreaMatrix 不变量：

- 接管已有目录不移动、不重命名、不删除、不覆盖用户文件。
- 自动生成内容默认只写入 `.areamatrix/generated/`。
- 不覆盖用户已有 `README.md`。
- 删除、Replace、AI 远程调用、非空目录接管、iCloud 冲突必须显式确认或清楚提示。
- AI 能力默认关闭；远程 AI 必须由用户显式配置并启用。

---

## 开发使用方式

建议开发任务引用页面 ID，而不是引用宽泛功能名：

```text
实现 S1-08 main-empty、S1-17 import-single-sheet、S1-24 replace-confirm。
```

如果要把任务交给 IDE / agent，推荐只提供三类上下文：

1. 阶段索引，例如 [stage-1-mvp.md](stage-1-mvp.md)，用于理解阶段范围。
2. 单页规格，例如 [S1-17-import-single-sheet.md](stage-1-mvp/S1-17-import-single-sheet.md)，作为本次实现边界。
3. 单页 `来源` 字段指向的功能域文档，用于查证事实源。

不要一次性投喂所有页面文件；逐页或按强相关小组投喂更容易保持实现边界。

开发完成后，至少按对应页面的“验收”条目做人工或自动检查。若实现中发现 Core API 或平台能力与页面规格不一致，先回到对应功能域文档或架构文档更新事实源，再同步本目录。

---

## Related

- [../README.md](../README.md)
- [../first-launch.md](../first-launch.md)
- [../drag-import-flow.md](../drag-import-flow.md)
- [../ui-states.md](../ui-states.md)
- [../dedup-conflict.md](../dedup-conflict.md)
- [../settings-panel.md](../settings-panel.md)
- [../search.md](../search.md)
- [../../roadmap/milestones.md](../../roadmap/milestones.md)
