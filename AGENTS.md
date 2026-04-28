# AreaMatrix Agent Guide

## 定位

- 本仓库是 AreaMatrix：Rust 核心库 + SwiftUI macOS 原生应用 + UniFFI 桥接的桌面资料管理工具。
- 当前仓库以文档为主，开发从 `tasks/prompts/` 的可执行 prompt 任务开始推进。
- 对话、说明、提交说明、任务汇报默认使用中文；代码标识符、类型名、文件名中的技术标识保持英文。

## 入口顺序

1. 先读本文件。
2. 再按目标路径读取最近的局部 `AGENTS.md`。当前首轮不创建空的 `core/AGENTS.md` 或 `apps/macos/AGENTS.md`；这些文件由后续工程骨架任务在对应目录出现时补充。
3. 再读与任务匹配的 `docs/` 文档、`.ai-governance/` 规则和 `tasks/prompts/` 任务文件。

## 源事实

- 产品、架构、API、开发规范的权威来源是 `docs/`。
- AI 协作规则的统一源事实是 `.ai-governance/`。
- Codex 专用运行材料放在 `.codex/`，不是业务语义的权威来源。
- Prompt 任务库在 `tasks/prompts/`，任务执行时以 task 文件和 manifest 的组合为边界。
- 对外 Core API 变化必须先对齐 `docs/api/core-api.md`，再更新 `core/area_matrix.udl`。

## 工作方式

- 先读文档和上下文，再改代码。
- 小改动可直接执行；跨层、跨模块、涉及架构或高风险边界的任务先计划。
- 文档已定义而代码没有时，按文档实现；代码与文档冲突时，优先改代码对齐文档，除非能证明文档本身过期。
- 不创建无意义临时文件、备份文件或低价值报告。
- 不扩大改动面；后续工程目录出现后，按最近的局部规则约束该目录。

## AreaMatrix 高风险边界

命中以下任一项时，必须先说明影响、风险、验证和回滚思路，再等待明确确认：

- 可能删除、移动、覆盖、重命名用户原文件的行为。
- 非空目录接管、reindex、FSEvents 回流、iCloud 占位符下载。
- DB schema、migration、rollback、数据修复。
- staging recovery、事务式导入、重复 hash 与冲突处理。
- 自动概览写入位置，尤其是 `AREAMATRIX.md` 与用户已有 `README.md`。
- Core API / UDL / Swift bridge 的破坏性变化。
- 隐私、AI 远程调用、用户数据离开本机。

## 关键不变量

- 接管已有目录时不移动、不重命名、不删除、不覆盖任何已有用户文件。
- 自动生成内容默认只写入 `.areamatrix/generated/`。
- 应用不得覆盖用户已有 `README.md`。
- 成功导入必须同时在文件系统和 DB 可见；失败导入不得留下最终目录半成品。
- 删除 `.areamatrix/` 不得导致用户文件本身丢失。
- Core 层不依赖 macOS 专属 API；平台能力留在 Swift 平台层。

## 验证要求

- Prompt 体系变更：运行 `python3 tasks/prompts/_shared/prompt_pipeline.py doctor`，并按需要运行 `plan`、`render`、`status`。
- Rust core 变更：运行 `cargo fmt --all -- --check`、`cargo clippy --all-targets --all-features -- -D warnings`、`cargo test --workspace`。
- macOS app 变更：运行相关 `xcodebuild`、SwiftFormat、SwiftLint 检查。
- 无法运行的检查必须在汇报中明确说明原因。

