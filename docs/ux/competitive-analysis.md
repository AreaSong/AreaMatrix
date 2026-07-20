# 竞品深度对比（Competitive Analysis）

> 基于竞品公开资料记录 AreaMatrix 的定位取舍；本文是产品研究，不是竞品内部事实或 AreaMatrix 功能合同。
>
> 阅读时长：约 18 分钟。

---

## 目标与成功标准

### 目标

1. **明确我们要赢在哪里**：不是“都做”，而是“做对一组核心任务”。
2. **明确我们不做什么**：避免做成复杂的 DEVONthink 或纯规则的 Hazel。
3. **把差异化落到 UX**：不是一句“更现代”，而是具体交互与默认策略。

### 成功标准（验收）

- **CA1**：能用 3 句话解释“为什么用 AreaMatrix 而不是 Finder/Hazel”。
- **CA2**：能列出 5 个“我们不追”的能力（避免 scope creep）。
- **CA3**：每个差异点都映射到稳定能力文档和对应 UX 合同。

## 研究边界与来源

本页最近复核日期为 2026-07-18。竞品能力只引用官方公开页面的产品定位，不推断内部实现、性能、
市场份额或用户满意度；AreaMatrix 的当前能力始终以 `docs/product/`、`docs/ux/` 和 `docs/api/` 为准。

- [Apple macOS User Guide: Finder](https://support.apple.com/guide/mac-help/welcome/mac)
- [Hazel](https://www.noodlesoft.com/)
- [DEVONthink](https://www.devontechnologies.com/apps/devonthink)
- [Eagle](https://en.eagle.cool/)
- [Obsidian](https://obsidian.md/)

---

## 我们的定位（再确认）

> 面向普通文件夹的本地资料管理：导入辅助、可解释分类、结构化检索和受支持操作的改动记录。

更具体：
- 以 **资料库（普通文件夹）** 为中心（local-first）
- 以 **拖拽导入 + 分类/命名预览** 降低整理成本
- 以 **改动时间线 + AreaMatrix generated overview** 提供可追溯
- 以 **树状导航 + 详情面板** 提供可视化管理

---

## 竞品对比维度（8 维）

| 维度 | 我们关心的问题 |
|---|---|
| A. 资料形态 | 数据是否锁定在 app 内？弃用后是否可读？ |
| B. 导入体验 | 归档动作是否“零意志力”？ |
| C. 自动化能力 | 规则/智能/可解释性如何？ |
| D. 搜索能力 | 名称/全文/OCR/语义，体验与成本 |
| E. 可追溯性 | 有没有时间线、版本、操作历史？ |
| F. 可视化管理 | 树/列表/详情，能否批量与多选？ |
| G. 隐私与离线 | 默认是否本地？AI 是否可选？ |
| H. 学习成本 | 上手曲线与复杂度 |

---

## 总览表（高层）

| 产品 | 强项 | 弱项 | 适合谁 |
|---|---|---|---|
| Finder | macOS 原生文件浏览与普通文件夹互操作 | 不提供 AreaMatrix 的分类、metadata 和 change-log 合同 | 系统文件管理 |
| Hazel | 文件夹规则与自动化动作 | 产品重点不是 AreaMatrix 式资料库浏览和详情状态 | 规则自动整理 |
| DEVONthink | 专业资料管理、搜索与 OCR 能力 | 能力面和学习成本高于 AreaMatrix 的轻量定位 | 专业知识管理 |
| Eagle | 视觉素材采集、预览和组织 | 产品重点不同于混合文档资料库 | 设计素材管理 |
| Obsidian | 本地 Markdown、链接与插件生态 | 主对象是笔记和知识网络，不是文件导入事务 | 笔记与知识网络 |
| AreaMatrix | 普通文件夹、事务式导入、结构化检索和文件安全边界 | 不提供 OCR、任意脚本自动化或知识图谱 | 个人/小团队资料归档 |

---

## 逐个竞品分析

### 1) Finder

#### Finder 的“默认路径”

- 以文件系统为中心（与我们一致）
- 强在“任何 app 都能打开、任何工具都能操作”
- 不提供 AreaMatrix 定义的导入分类、metadata DB 和逐项 change-log 合同。

#### 我们要补上的

- `drag-import-flow.md`：拖拽导入 → 自动分类/命名
- `ui-states.md`：树/列表/详情 + 多选 + 批量
- `modules/change-log.md`：时间线
- `modules/overview-gen.md`：AreaMatrix 专属概览

#### 我们不做的

- 不替代 Finder 的全部能力（标签颜色、智能文件夹生态等），只做“资料库内”的管理。

---

### 2) Hazel

#### Hazel 的核心

- 面向“规则驱动的后台自动化”：监控文件夹 → 按规则移动/重命名/执行脚本。
- 强在“可编排动作”与“长期无人值守”。

#### 与 AreaMatrix 的产品边界差异

- Hazel 的官方定位是文件夹规则自动化；AreaMatrix 同时维护资料库树、列表、详情和 Core metadata。
- AreaMatrix 的 change log 只覆盖受支持的 Core/外部同步动作，不宣称记录其他应用的所有历史。

#### AreaMatrix 的差异化

- 我们把规则（classifier.yaml）用于“导入时决策”，并提供“纠错→沉淀规则”。
- 规则不是目的，是“降低意志力”的手段。
- 参见：`classifier-calibration.md`。

#### 我们不做的

- 不做 Hazel 那种“任意脚本动作编排”（后续扩展版本再考虑插件）。

---

### 3) DEVONthink

#### DEVONthink 的核心

- 强自动分类、强全文检索（含 OCR）、强组织与引用。
- 代价：复杂、学习成本高、UI 偏传统。

#### 我们要学的

- 分类的“可解释性”（为什么分到这里）
- 资料管理的“可追溯”（时间线、版本）

#### 我们要避免的

- 不做“一个系统内的第二套文件系统”。
- 不把用户数据锁进专有数据库（我们坚持 repo 是普通文件夹）。

#### 差异化落点

- 规则透明、可调教，并保持轻量界面。
- 搜索覆盖文件名、笔记、已索引元数据、标签和保存查询。
- AI 是显式启用的正式能力；OCR 不属于当前正式产品。

参见：[搜索 UX](search.md)、[产品能力](../product/capabilities.md)和[能力方向](../product/capability-direction.md)。

---

### 4) Eagle

#### Eagle 的核心

- 面向“视觉素材”：快速预览、标签、分组、设计师工作流。

#### 我们的不同

- 我们是“资料混合”（文档/代码/合同/票据/截图）
- 视觉预览不是当前核心能力；是否提供 Quick Look 以正式能力文档为准。

#### 可借鉴点

- 强多选与批量操作
- 标签作为横切维度（见 `deep-features.md`）

---

### 5) Obsidian

#### Obsidian 的核心

- Markdown 笔记与链接网络，强生态。

#### 我们的不同

- 我们以“文件条目”与“资料库结构”作为主对象，而不是笔记。
- 我们的 note 是“伴生笔记”（companion note），用于为文件补充说明。

#### 可借鉴点

- local-first
- 文档化与可链接的知识组织（AreaMatrix 概览 / Note）

---

## 结论：我们的 5 个差异化承诺（可写进 README）

1. **Repo 就是普通文件夹**：弃用也能用 Finder 继续管理。
2. **拖拽即归档**：导入时自动分类/命名，不需要用户思考。
3. **受支持动作可追溯**：Core change log + AreaMatrix generated overview；不宣称记录任意文件系统动作。
4. **纠错会沉淀**：分类不对？两次点击纠正，并可选择沉淀为规则。
5. **本地优先，智能可选**：AI 需要显式启用；OCR 不属于当前产品能力。

---

## 我们明确“不做”的清单（防 scope creep）

1. 不做企业级协作与权限系统；协作和多端客户端进入能力方向评估。
2. 不做任意脚本自动化编排（Hazel 类能力）
3. 不默认开启 AI；OCR 不属于当前产品能力
4. 不做跨云盘多家 SDK 集成；当前平台集成以 macOS 和 iCloud 能力为边界。
5. 不做复杂的知识网络（双链/图谱）

---

## Related

- [../product/prd.md](../product/prd.md)
- [drag-import-flow.md](drag-import-flow.md)
- [classifier-calibration.md](classifier-calibration.md)
- [ui-states.md](ui-states.md)
- [search.md](search.md)
- [deep-features.md](deep-features.md)
