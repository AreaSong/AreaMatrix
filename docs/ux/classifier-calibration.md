# 分类器调教（Classifier Calibration）

> 定义用户如何纠正分类、选择 metadata-only 或物理移动、理解当前分类来源，以及通过可视化编辑器把纠正沉淀为 `classifier.yaml` 规则。
>
> 阅读时长：约 18 分钟。

---

## 目标与成功标准

### 目标

1. **纠错成本低**：用户从 Detail 打开纠正页，选择目标分类并应用。
2. **副作用可控**：Indexed、missing、adopted 和 external 文件默认只更新 metadata；可移动的 Imported 文件由用户决定是否移动。
3. **规则单独确认**：纠正当前文件与保存未来规则是两个动作，不能由一个 Apply 隐式同时完成。
4. **解释可见**：界面展示分类来源、目标分类和 confidence，不伪造 Core 没有返回的命中值或 priority。
5. **影响可预览**：预览已有文件的潜在变化时保持只读；保存规则默认只影响未来分类。

### 成功标准（验收）

- **纠错生效**：Apply 更新分类 metadata；只有允许且启用“Move file”时才移动 repo-owned 文件。
- **规则沉淀**：“Remember this correction”生成 rule draft，用户进入 Edit rule 后显式保存。
- **解释可见**：展示 keyword、extension、AI 或 default 来源、目标分类和 confidence。
- **影响预览**：Preview impact 展示 existing files 的 current/new category 和计划动作，但不保存或应用。
- **校验恢复**：规则保存先经 Core 校验；失败不替换有效配置，并可 Reload；仅存在 last-valid backup
  时可 Revert。

---

## 入口（用户从哪里开始调教）

### 入口 1：Detail 面板（推荐，最高频）

- 当用户看到文件分类不对，在 Detail 的 Meta 区域旁显示小按钮：`分类不对？`
- 这是“就地纠错”，不打断用户心流。

### 入口 2：ImportSheet（导入前纠错）

在 `drag-import-flow.md` 的 ImportSheet 中：
- 建议分类旁的 `（为什么？）`
- 以及分类下拉直接改分类

这里的调教目标是“本次导入”与“沉淀规则”二选一。

### 入口 3：设置 → 分类规则

面向高级用户：
- `Settings → 分类规则`（见 `settings-panel.md`）。
- 主界面是可视化 Core rule editor，可编辑 category、extension、keyword、priority 和 naming template。
- 文件级入口可以打开 `classifier.yaml` 或在 Finder 中显示；应用内不提供原始 YAML 文本编辑器。

### 入口 4：命令面板（Cmd+K）

当前命令面板提供 `Open classifier rules…`，路由到 `classifier-rule-editor`。当前没有
`Calibrate classifier for current file…` 命令；单文件纠正从 Detail 进入。

---

## 核心交互 1：快速纠错（不沉淀规则）

### UI（Detail → 分类纠错弹窗）

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 纠正分类：合同_2026Q1.pdf                                                       │
│                                                                              │
│  当前：docs                                                                    │
│  改为： [ finance ▾ ]                                                          │
│                                                                              │
│  [✓] Move file to the new category folder                                     │
│  说明：不支持移动时只更新分类 metadata。                                        │
│                                                                              │
│  [ Cancel ]                                                   [ Apply ]      │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 结果反馈

Apply 后：
- 分类 metadata 和 change log 更新，列表按当前筛选刷新。
- 可用的 Imported、非 Indexed 文件在启用 Move 时移动到目标分类目录。
- Indexed、missing、adopted 和 external 文件不移动物理路径，只更新 metadata。

---

## 核心交互 2：纠错并沉淀规则（“以后都这样”）

### UI（在快速纠错弹窗里增加“记住规则”）

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 纠正分类：合同_2026Q1.pdf                                                       │
│                                                                              │
│  当前：docs                                                                    │
│  改为： [ finance ▾ ]                                                          │
│                                                                              │
│  [✓] Remember this correction as a rule                                       │
│      候选：关键词、扩展名与 priority                                            │
│                                                                              │
│  [ Edit rule... ] [ Preview impact ]                                          │
│                                                                              │
│  [ Cancel ]                                                   [ Apply ]      │
└──────────────────────────────────────────────────────────────────────────────┘
```

Apply 只纠正当前文件。启用 Remember 后，用户必须进入 Edit rule 或 Preview impact：

- Edit rule 选择 keyword/extension candidate 和 priority，校验后显式保存。
- Preview impact 只读取影响报告，不保存 rule，也不修改已有文件。

### 规则依据

| 选项 | 含义 | 风险 |
|---|---|---|
| 扩展名 | 对所有 `.pdf` 生效 | 🔴 太宽（不推荐默认） |
| 关键词 | 对含关键词的文件名生效 | 🟡 合理 |
| 仅本文件名 | 精确匹配当前文件名 | 🟢 安全但收益小 |

候选由当前文件名和路径生成；extension-only 规则和过宽影响必须经过 Core 的影响确认门禁。

---

## Preview impact（预览影响范围）

### 目的

避免“改一条规则影响一大片”，并给用户可见性。

### UI（预览 sheet）

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 预览规则影响                                                                    │
│                                                                              │
│  规则：关键词包含 “合同” → finance                                             │
│                                                                              │
│  将影响： 37 个文件                                                            │
│                                                                              │
│  [PDF] 合同_2025Q4_客户B.pdf     当前：docs   变更后：finance                   │
│  [PDF] 合同_2026Q1_客户A.pdf     当前：docs   变更后：finance                   │
│  ...                                                                          │
│                                                                              │
│  [ Back ]                                            [ Confirm rule change ] │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 规则生效时机

当前 Preview impact 是只读页面：

- 显示受影响数量、current/new category、move/metadata-only action 和状态。
- `Save rule only` 与 `Save and apply to existing files` 在该页保持禁用。
- 用户返回 Edit rule 后可以保存规则；保存只影响未来分类。
- 当前没有批量重分类、批量移动或“Apply now”合同。

---

## “为什么分到这里？”解释面板

### 触发入口

Import 预览提供 `为什么？`；Detail 纠正页显示 `Classification source`。

### UI（popover）

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ 为什么归到 docs？                                                               │
│                                                                              │
│  来源：Matched extension rule                                                 │
│  结果：docs                                                                   │
│  Confidence: 80%                                                             │
│                                                                              │
│  [ Change rules… ]                                                            │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 解释字段约定（产品侧）

当前解释字段包括：

- reason：keyword、extension、AI prediction 或 default。
- category。
- confidence；default 可以不显示百分比。

当前 Core 结果不返回具体命中值、规则 priority 或冲突决策链，UI 不得自行推断这些字段。

实现细节参见：`docs/modules/classify.md` 与 `docs/api/classifier-yaml.md`。

---

## 规则编辑与 YAML 文件边界

### Settings → 分类规则 页面（概念，细节在 settings-panel.md）

应用内提供：

- 可视化 category 列表与 detail editor。
- extension、keyword、priority、description 和 naming template 编辑。
- Validate、Preview impact、Save、条件式 Revert 和受确认保护的删除/影响操作。
- `classifier.yaml` 的 Open 与 Reveal in Finder 文件入口。

校验失败必须显示 Core 提供的受控 reason。可视化 editor 的语义错误显示 field/rule + reason，
不要求行号；只有 Core 对外部 YAML 解析失败明确提供 parse location 时才显示行号/列号。Swift 不解析
reason 字符串来推断字段、规则、位置或恢复动作。Revert 只在 last-valid backup 存在时显示并可用。

应用内不承诺 YAML 语法高亮、JSON Schema 文本编辑器或行列式源码编辑体验。

### YAML 保存策略（产品侧）

1. 用户点击 Save，Swift 先做草稿校验，再提交 Core editor request。
2. Core 执行规则校验和影响确认；失败不替换有效配置。
3. 成功后原子写入 `classifier.yaml`，提示规则已保存。
4. 保存只影响未来分类；不自动 reclassify、move、rename、delete 或 reindex 已有文件。

---

## 规则写入策略（产品侧，不涉及实现）

`classifier.yaml` 是用户拥有的配置文件，不使用 managed block 或自动追加区块：

- 初始化只在文件缺失时创建默认 YAML，不覆盖已有内容。
- 可视化编辑器通过 Core API 修改规则，并按保存合同原子替换文件。
- 用户在外部手工编辑后，下次读取重新解析；当前没有 classifier cache。
- Revert 只在存在最近有效备份时可用，并需要确认。

---

## 文案（中英对照，关键按钮）

| Key | 中文 | English |
|---|---|---|
| calibrate.title | 纠正分类 | Fix classification |
| calibrate.remember | 记住这个规则 | Remember this rule |
| calibrate.preview | 预览影响… | Preview impact… |
| calibrate.apply | 应用 | Apply |
| calibrate.editRule | 编辑规则… | Edit rule… |
| explain.why | 为什么？ | Why? |
| explain.changeRules | 修改规则… | Change rules… |
| explain.reason | 选择：%s | Decision: %s |

---

## 测试用例（产品验收清单）

- [ ] Detail 面板可打开“纠正分类”弹窗
- [ ] metadata-only 纠错不移动 Indexed、missing、adopted 或 external 文件
- [ ] 可移动 Imported 文件仅在 Move toggle 开启时改变物理路径
- [ ] Remember 生成 rule draft；Apply 当前文件不会隐式保存规则
- [ ] Preview impact 只读，不能批量应用到 existing files
- [ ] Classification source 展示 reason、category 和 confidence
- [ ] 可视化编辑器语义校验失败显示 field/rule + reason，不要求行号，也不替换有效 YAML
- [ ] 仅 Core 提供 parse location 时显示行列；仅 last-valid backup 存在时可 Revert

---

## Related

- [drag-import-flow.md](drag-import-flow.md)
- [dedup-conflict.md](dedup-conflict.md)
- [../modules/classify.md](../modules/classify.md)
- [../api/classifier-yaml.md](../api/classifier-yaml.md)
- [../api/error-codes.md](../api/error-codes.md)
- [../modules/storage.md](../modules/storage.md)

---

## 附录：默认关键词提取策略（产品侧建议）

规则 handoff 会从当前文件名和路径生成最多 5 个候选关键词或 extension：

1. 取文件名（不含扩展名）
2. 以分隔符切分：空格、下划线、短横线、中文标点
3. 过滤长度小于 2、过长、重复或包含不安全路径字符的 token
4. 候选只用于 rule draft；保存前仍需用户选择和 Core 校验

示例：

- `合同_2026Q1_客户A.pdf` → 候选：`合同`、`客户A`、`2026Q1`（数字可选）

实现细节参见 `docs/modules/classify.md` 与 Swift `ClassifierCorrectionRuleState`。
