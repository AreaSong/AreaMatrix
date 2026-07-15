---
id: AM-OPS-001
title: AreaMatrix 运行与能力生命周期
status: accepted
owner: "@AreaSong"
effective_date: 2026-07-15
last_verified: 2026-07-15
review_cycle: quarterly
---

# AreaMatrix 运行与能力生命周期

## 桌面运行模型

AreaMatrix 不以在线服务可用率作为当前 SLO。运行健康由以下可验证信号组成：

- 文件安全不变量：已知破坏性违反为零容忍。
- 发布关键路径：创建/接管资料库、导入、浏览、搜索、外部变化和恢复冒烟通过。
- 性能：遵循 `docs/development/performance.md` 和版本 performance evidence。
- 恢复：遵循事务式导入、DB 备份、staging recovery 和错误恢复矩阵。
- 安全响应：遵循 `SECURITY.md` 的私密报告渠道和响应时限。
- 支持反馈：Bug、可信预览反馈和 release residual 具有 owner、状态和关闭证据。

不收集远程遥测来伪造上述指标。需要远程指标时必须先更新隐私源事实、取得用户明示同意并完成安全评审。

## 发布和观察

发布顺序固定为本地工程验证、内部 QA、可信测试者预览、签名/公证候选和正式分发。每一级都必须记录构建、兼容性、停止条件、回滚条件和观察结果。

未签名、未公证、同机启动或 ad-hoc 产物不能替代正式分发证据。v1 现有 release residual 保持其真实状态。

## 事故闭环

1. 识别影响并优先保护用户文件和数据一致性。
2. 停止扩散，必要时禁用入口、回滚或降级。
3. 记录时间线、影响、根因和促成因素。
4. 将改进写回 docs、代码、测试、CI、Runbook 或 residual。
5. 使用新证据证明控制有效后关闭。

安全事件使用 GitHub Security Advisory；公开 issue 不记录利用细节、敏感路径或用户数据。

## 能力状态

长期能力使用 `planned`、`active`、`deprecated`、`retiring`、`archived`。状态变化必须登记 owner、触发原因、用户影响、迁移、数据处置和验证。

## 退役门禁

G8 完成必须证明：

- 用户、调用方和依赖已识别并完成迁移或通知。
- 写入口已关闭，存量数据按产品与隐私规则处置。
- 代码、API、UDL、配置、功能开关和兼容层已移除或明确保留期限。
- 权限、密钥、自动化、CI、告警、资源、成本和所有权已关闭。
- 架构、用户文档、发布记录和治理登记册已同步。

删除 `.areamatrix/` 不得导致用户原文件丢失；退役 AreaMatrix 不能以删除用户资料库内容作为清理方式。
