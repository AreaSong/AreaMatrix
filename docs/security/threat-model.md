---
id: AM-SEC-001
title: AreaMatrix 威胁模型
status: accepted
owner: "@AreaSong"
effective_date: 2026-07-20
last_verified: 2026-07-20
review_cycle: quarterly
---

# AreaMatrix 威胁模型

> 本文定义 AreaMatrix 桌面产品的信任边界、威胁主体、数据分类和控制映射，是安全事实的权威来源。
>
> 阅读时长：约 5 分钟。

## 适用范围

AreaMatrix 是本地优先桌面应用：Rust Core 平台无关，macOS 层持有平台能力。本文覆盖用户文件、`.areamatrix/` 元数据、FFI 边界、平台服务和可选远程 AI 的安全语义；漏洞报告与响应流程以仓库根 `SECURITY.md` 为准，用户数据处理承诺以 [隐私与数据处理](../product/privacy.md) 为准。

## 信任边界

| 边界 | 两侧 | 主要暴露 |
|---|---|---|
| 用户文件系统 | 应用 与 资料库目录、外部工具 | 误删除、覆盖、并发外部修改、符号链接与特殊路径 |
| `.areamatrix/` 元数据 | 应用 与 SQLite `index.db`、staging、generated | DB 损坏、锁竞争、半成品状态、恢复失败 |
| UniFFI FFI | SwiftUI/平台层 与 Rust Core | 契约漂移、错误映射丢失、跨语言内存与并发问题 |
| 平台事件回流 | FSEvents、iCloud 与 应用状态 | 事件风暴、占位符未下载、冲突副本、循环回写 |
| 网络出口 | 应用 与 远程 AI provider | 用户数据外泄、响应注入、供应商失陷或不可用 |
| 凭据存储 | macOS Keychain 与 平台层 | 凭据泄漏、越权读取、日志或错误信息带出 secret |
| 外部输入 | 导入文件、拖拽内容、`classifier.yaml` 与 解析器 | 恶意文件名、超长路径、格式炸弹、规则注入 |

信任方向固定：Core 不读 Keychain、不发起网络请求；远程调用由平台层按 Core 给出的非 secret plan 执行，回传前完成净化。

## 威胁主体与场景

- 用户误操作：误删资料库、外部工具并发改写、在导入中途退出。
- 恶意或畸形输入：不可信来源的文件名、路径、内容和分类规则，试图触发越界写入或解析故障。
- 失陷的远程 AI provider：返回注入性响应、记录外发内容、超范围收集。
- 本机其他进程：占用或损坏 SQLite、篡改 `.areamatrix/`、竞争文件锁。
- 供应链：依赖包引入恶意代码或许可证风险。
- 好奇的本机用户之外，当前不设想网络攻击者直接攻击本机进程；应用不监听端口、不提供远程服务。

## 数据分类

| 类别 | 敏感度 | 存放与出口 |
|---|---|---|
| 用户原文件内容 | 最高 | 仅本机资料库；除用户明示同意的 AI 请求外不得离开本机 |
| 派生元数据与索引 | 高 | `.areamatrix/` 内 SQLite；删除 `.areamatrix/` 不得影响原文件 |
| AI 外发载荷 | 高 | 按隐私规则最小化、净化后经受限 URLSession 发送 |
| 凭据与 API key | 最高 | 仅 macOS Keychain；不进代码、配置、日志、测试样例 |
| 诊断与日志 | 中 | 本机；不携带文件内容、完整路径外的敏感信息和 secret |

## 控制映射

| 威胁 | 控制 | 权威来源 |
|---|---|---|
| 用户文件被破坏 | 不移动、不重命名、不删除、不覆盖原文件；生成物只写 `.areamatrix/generated/` | [项目章程](../governance/project-charter.md)、根 `AGENTS.md` |
| 导入半成品 | 事务式导入：成功双可见、失败无残留 | [事务式导入](../architecture/transactional-import.md) |
| DB 损坏与恢复 | 备份、staging recovery、错误恢复矩阵 | [错误恢复矩阵](../development/error-recovery-matrix.md)、[恢复说明](../development/recovery.md) |
| 数据外泄 | 明示同意、最小化、净化；Core 无网络与 Keychain 能力 | [隐私与数据处理](../product/privacy.md)、[macOS 前端架构](../architecture/macos-frontend-architecture.md) |
| 凭据泄漏 | Keychain 唯一存放；gitleaks 与 secret scan 门禁 | [Secret Scan Runbook](../development/secret-scan-runbook.md) |
| 契约漂移 | Core API 文档与 UDL 同步、bindings verify、错误码映射测试 | [Core API](../api/core-api.md)、[FFI 设计](../architecture/ffi-design.md) |
| 事件回流风暴 | watcher 状态机、iCloud 占位符与冲突处理边界 | [文件监听与 iCloud](../architecture/fs-watcher.md) |
| 供应链风险 | 依赖政策：锁定、许可证、替换与回滚 | [依赖政策](../development/dependency-policy.md) |
| 漏洞披露 | GitHub Security Advisory 私密报告与响应时限 | 仓库根 `SECURITY.md` |

## 复审触发

出现以下任一变化时，必须更新本文并按 L3 高风险流程评审：

- 新增远程服务、网络出口或遥测。
- 新增用户文件写路径、删除路径或不可逆操作。
- 新增外部输入解析器或导入格式。
- 凭据存放位置、隐私承诺或数据分类变化。

## Related

- [企业工作流治理基线](../governance/enterprise-workflow-baseline.md)
- [治理登记册](../governance/governance-register.yaml)
- [隐私与数据处理](../product/privacy.md)
- [运行与能力生命周期](../governance/operations-lifecycle.md)
