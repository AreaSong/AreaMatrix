---
id: AM-CHARTER-001
title: AreaMatrix 项目章程
status: accepted
owner: "@AreaSong"
effective_date: 2026-07-15
last_verified: 2026-07-15
review_cycle: quarterly
---

# AreaMatrix 项目章程

## 使命

AreaMatrix 是 Rust Core、UniFFI 和 SwiftUI macOS 应用组成的本地优先资料管理工具。它帮助个人和小团队在保留普通文件夹、原始文件和外部工具兼容性的前提下，安全地导入、组织、搜索、理解和恢复资料。

## 成功条件

- 用户原文件和已有 `README.md` 不被应用静默移动、删除、覆盖或重命名。
- 成功导入在文件系统和 DB 同时可见，失败导入不留下最终目录半成品。
- 产品行为、Core API、UDL、Swift bridge、测试和用户文档保持一致。
- 适用的质量、安全、兼容、恢复和发布门禁具有可复核证据。
- 每项长期能力具有 owner、运行要求、反馈路径和退役条件。

具体产品能力和性能数字仍以 `docs/product/`、`docs/architecture/`、`docs/development/performance.md` 为准，本文不重复维护。

## 范围

- macOS 14+ 原生桌面应用和平台无关 Rust Core。
- 本地资料库、SQLite 元数据、事务式导入、搜索组织、外部变化、恢复和可选 AI。
- 源事实、开发、测试、发布、支持和退役治理。

## 非目标

- 当前不承诺 SaaS 后端、多人实时协作、企业 IAM、24x7 在线服务或无限规模。
- 当前不把未签名本地构建、同机冒烟或非公证预览称为正式分发。
- 当前不允许远程 AI 在未明示同意和数据最小化控制下接收用户数据。

## 责任和决策

`@AreaSong` 是项目、产品、技术、数据、安全协调和发布准备的最终责任者。角色合并不取消复核要求；L3/L4 变更在缺少独立合格复核时保持 blocked。

产品行为以 docs 为准，架构选择以 ADR/架构文档为准，执行状态以 workflow/task/evidence 为准。会议或聊天结论必须回写对应源事实后才生效。

## 成本边界

- 优先标准库和现有依赖；新增依赖必须可锁定、许可证兼容、可替换并有回滚。
- 当前不建立虚构预算数字。实际 Apple 账号、签名、公证、CI runner、外部服务和测试者成本在发生前由 `@AreaSong` 审批并登记。
- 远程 AI、同步服务或商业供应商接入前必须补充成本随规模增长模型和退出方案。

## 退出条件

当产品不再维护时，必须停止新增使用，提供数据和普通文件夹可继续访问路径，清理构建/分发凭据、自动化、告警、文档和所有权，并按 `operations-lifecycle.md` 完成退役证据。

