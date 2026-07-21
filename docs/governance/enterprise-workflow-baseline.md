---
id: AM-GOV-001
title: AreaMatrix 企业工作流治理基线
status: accepted
owner: "@AreaSong"
effective_date: 2026-07-15
last_verified: 2026-07-15
review_cycle: quarterly
upstream: ASW-EWF-001@1.0.0
---

# AreaMatrix 企业工作流治理基线

> 本文定义 AreaMatrix 对 ASW-EWF-001 的可复核项目适配、生命周期门禁和责任边界。
>
> 阅读时长：约 8 分钟。

## 定位

本文是 AreaMatrix 对 `ASW-EWF-001@1.0.0` 的项目适配源事实。上游规范定义通用企业治理要求；本文定义这些要求在本地优先桌面产品、单仓库和当前维护者结构中的唯一落点。

上游来源：

- 来源任务：`019f63ff-b316-79d2-a0cd-215090bcea1e`
- 仓库快照：[ASW-EWF-001-1.0.0.txt](upstream/ASW-EWF-001-1.0.0.txt)
- 仓库快照与上游原始文件逐字节一致，SHA-256：`ce6a779f243f54440ab9a82886a0d8d0c8a601243260fcdb829beed3f04c96f1`；该 hash 由 [`governance-register.yaml`](governance-register.yaml) 的 `upstream.sha256` 机器校验

快照用于离线复核上游版本和 hash；AreaMatrix 的采用语义、裁剪、责任和偏差仍以本文及
[`governance-register.yaml`](governance-register.yaml) 为准。

## 治理目标

- 长期事实具有唯一权威来源、所有者、状态和复审条件。
- 目标、设计、实现、验证、发布证据和运行结果能够双向追溯。
- 用户文件、DB、staging、FSEvents/iCloud、隐私和远程 AI 风险始终显式受控。
- 治理强度与影响面、敏感度、可逆性和故障后果匹配。
- 每项长期能力具备维护、弃用、迁移和安全退役路径。

## 范围与非目标

本基线覆盖产品、架构、开发、测试、安全、发布、运行、事故、成本、供应商、文档和退役治理。

本基线不把 AreaMatrix 描述成在线 SaaS，不虚构 24x7 值班、服务流量灰度、企业预算系统或当前不存在的后端。外部签名、公证、测试者、独立复核和 AreaFlow execution 只登记为外部依赖。

## G0-G8 映射

| 门禁 | AreaMatrix 权威落点 | 通过条件 |
|---|---|---|
| G0 需求登记 | `workflow/intake.md`、Issue 模板 | 来源、问题、初始 owner 和风险入口明确 |
| G1 立项审批 | `project-charter.md`、roadmap、治理登记册 | 价值、范围、成本边界、优先级和退出条件明确 |
| G2 需求就绪 | `docs/product/**`、版本 discussion | Exact Docs、非目标、验收和争议已关闭 |
| G3 设计就绪 | `docs/architecture/**`、ADR、API、安全与隐私文档 | 架构、数据、API、兼容性、NFR 和高风险边界已评审 |
| G4 开发就绪 | middle-layer、changes、plans、copy-ready/verify-ready | owner、精确路径、依赖、验证和回滚完整 |
| G5 合并就绪 | `CODE_REVIEW.md`、PR 模板、CI | review、测试、文档、扫描和独立复核要求满足 |
| G6 发布就绪 | `docs/development/release.md`、版本 evidence/residuals | 构建、灰度、回滚、签名、公证和通知证据真实 |
| G7 结果关闭 | closeout、运行指标、反馈证据 | 观察周期结束，健康与价值条件有证据 |
| G8 退役关闭 | `operations-lifecycle.md`、退役记录 | 调用方、数据、资源、权限、密钥、告警和文档关闭 |

## 变更等级

| 等级 | AreaMatrix 示例 | 最低控制 |
|---|---|---|
| L0 | 拼写、注释、无行为格式 | 基础检查 |
| L1 | 局部文档、低风险 Bug | 源事实关联、相关测试 |
| L2 | 多模块、Core API、UDL、共享配置 | 完整影响分析、集成验证、兼容与回滚 |
| L3 | 用户文件、DB、migration、staging、隐私、远程 AI | 高风险确认、安全/数据评审、独立复核、恢复证据 |
| L4 | 不可逆数据处置、正式分发、全局基础设施 | 正式风险接受、演练、变更窗口和业务连续性证据 |

L3/L4 缺少第二位合格复核者时必须保持 blocked，不允许由单人批准掩盖职责分离缺口。

## RAID 评估维度

治理登记册中的每个 risk/dependency 条目必须同时记录 `probability`（发生概率）、`impact`
（影响等级）和 `impact_scope`（受影响的具体治理或交付边界）。`probability` 与 `impact`
仅使用 `low`、`medium`、`high`；`impact_scope` 必须指向可复核的实际范围，不能用
`project`、`workflow` 等无法判断关闭条件的泛化描述。

五个基线 RAID ID 的 `type` 和 `status` 是受控合同：独立复核风险保持 `risk/open`；Apple
分发与可信测试参与者依赖保持 `dependency/blocked-external`；execution authorization 与
remote CI/branch protection 保持 `dependency/deferred`，直到各自的关闭证据成立。

## 适用性矩阵

| ASW 章节 | AreaMatrix 状态 | 项目落点或裁剪 |
|---:|---|---|
| 1 文档定位 | 满足 | 本文固定适配边界 |
| 2 引用方式 | 满足 | 固定 ID、版本、hash 和来源任务 |
| 3 规范用语 | 满足 | 必须/应该/可以沿用上游定义 |
| 4 核心原则 | 满足 | 本文、根 `AGENTS.md`、`.ai-governance/` |
| 5 总体闭环 | 适配满足 | G0-G8 映射现有 workflow/release/closeout |
| 6 治理层级 | 适配满足 | 单维护者合并角色，责任不删除 |
| 7 追溯链 | 满足 | docs -> workflow -> review/CI -> evidence |
| 8 生命周期门禁 | 满足 | G0-G8 表及机器检查 |
| 9 源事实模型 | 满足 | `docs/`、`.ai-governance/`、workflow 分层 |
| 10 推荐文档结构 | 适配满足 | 沿用现有结构，新增 `docs/governance/` 与 `docs/security/` |
| 11 文档判定 | 满足 | PR、review 和 doc-sync 规则 |
| 12 功能强制项 | 满足 | 高风险边界和专项文档 |
| 13 影响分析 | 满足 | PR 模板、review、workflow plan |
| 14 角色责任 | 适配满足 | 中央 RACI，`@AreaSong` Accountable |
| 15 RAID | 满足 | `governance-register.yaml` |
| 16 变更分类 | 满足 | L0-L4 |
| 17 Definition of Ready | 满足 | G2-G4 |
| 18 Definition of Done | 满足 | G5-G7，不以本地 PASS 替代发布证据 |
| 19 发布门禁 | 满足 | release 文档和 v1 residuals |
| 20 环境配置密钥 | 满足 | CI、secret scan、依赖与配置规则 |
| 21 质量策略 | 满足 | Rust、macOS、governance CI |
| 22 安全隐私 | 满足 | `SECURITY.md`、[威胁模型](../security/threat-model.md)、隐私文档、高风险触发 |
| 23 生产运行 | 适配满足 | 桌面运行模型，不适用在线服务值班 |
| 24 事故闭环 | 满足 | Issue/Security Advisory/residual/复盘回写 |
| 25 业务效果 | 适配满足 | 章程成功条件和发布观察 |
| 26 财务采购供应商 | 适配满足 | 成本边界、依赖政策和外部依赖登记 |
| 27 弃用退役 | 满足 | `operations-lifecycle.md` |
| 28 文档治理 | 满足 | docs 逐文件登记 + 全仓域归属与代码对应门禁 |
| 29 治理节奏 | 适配满足 | 持续 CI、版本复核、季度基线复核 |
| 30 指标体系 | 适配满足 | 文件安全、质量、性能、恢复和维护成本 |
| 31 行业扩展 | 不适用 | 当前不是金融、医疗、政务或硬件系统；远程 AI 启用时加载 AI 扩展 |
| 32 裁剪规则 | 满足 | 合并角色和文档，不删除责任与高风险控制 |
| 33 跨项目采用 | 满足 | 本次适配矩阵和偏差登记即采用证据 |
| 34 Codex 协议 | 满足 | repo-local skills 与 workflow gate |
| 35 完整性清单 | 满足 | governance check 机械验证 |
| 36 版本治理 | 满足 | 上游升级触发重新审查和迁移记录 |
| 37 最终判定 | 满足 | 完成条件由源事实、验证和外部依赖共同证明 |

## 源事实和适配器

- 产品、架构、API、UX、开发规范：`docs/**`。
- 企业治理适配：`docs/governance/**`。
- 威胁模型与数据分级：`docs/security/**`。
- AI 协作和风险规则：`.ai-governance/**`。
- 版本规划和执行追溯：`workflow/**`。
- 评审、CI、PR 模板和 Codex skills 只是适配器，不得成为唯一源事实。

## 裁剪记录

按上游第 32 节允许的方式，AreaMatrix 记录以下结构裁剪；裁剪只合并载体，不删除责任与事实：

- RFC 并入 ADR 轻量决策记录：候选方案讨论走版本 discussion 与 `decisions.yaml`，已生效决策落 `docs/adr/`，不维护独立 RFC 目录。
- 数据字典并入 [数据模型](../architecture/data-model.md)：表、字段语义与迁移权威保持单一位置，不另建 `docs/data/`。
- 文档元数据采用中央登记：owner、状态与复审条件由 `governance-register.yaml` 的 `documents` 与 `document_domains` 承载，内嵌 front-matter 随实质修改渐进补充。

## 偏差与升级

当前无已接受的 ASW 治理豁免。外部依赖不属于豁免，必须保留真实 blocked/deferred 状态。

上游版本、hash、强制门禁、责任或引用方式变化时，必须重新执行适用性审查，更新本文和登记册，并在对应 workflow discussion 中记录兼容性与迁移动作。

## Related

- [项目章程](project-charter.md)
- [治理登记册](governance-register.yaml)
- [运行与能力生命周期](operations-lifecycle.md)
- [AI 治理源事实](../../.ai-governance/README.md)
