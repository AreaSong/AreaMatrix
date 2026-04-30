# Prompt 任务切片规则

> 本规则用于全阶段细拆任务，防止“大任务看似完成，实际链路没有闭环”。

## 基本约束

- 一个任务最多覆盖 1 个主用户动作，或 1 个 Core 能力闭环。
- 每个任务必须绑定至少一个 UX 页面或一个 Core 能力。
- `atomic` 执行任务只能绑定 1 个 `S*` 页面或 1 个 `C*` 能力；如果同时需要多个页面/能力，必须拆分。
- `integration` / `verify` 任务可以读取多个页面和能力，但只能做集成 wiring、验收补齐或证据整理，不能新增未绑定功能。
- 禁止把多个用户闭环塞进一个任务，例如“首次启动 + 导入 + 详情 + 设置”不能同 task 完成。
- 禁止为了让 UI 先跑起来而把真实 Core 合同藏成 mock。
- 如果任务只允许 mock/preview，完成标准必须明确写“不能作为最终闭环通过”。

## 任务类型

| 类型 | 用途 | 粒度 |
|---|---|---|
| atomic | 实际执行入口 | 1 个页面、1 个 Core 能力合同、或 1 个工程骨架动作 |
| integration | 集成 wiring / 阶段验收入口 | 可读取多个页面/能力，但不得扩大功能范围 |
| verify | 只读验收入口 | 禁止修改文件，按 task + manifest + 实际文件交叉验收 |

## 文档读取顺序

执行任何已存在 capability specs 的 task 时，除了共享规则和 manifest，还必须按顺序读取：

1. 绑定的 UX 页面规格：`docs/ux/page-specs/**/S*.md`。
2. 绑定的 Core 能力规格：`docs/core/capability-specs/**/C*.md`。
3. 对应阶段的 control map：`docs/architecture/*control-map.md`。
4. Manifest 中列出的 API、architecture、module 文档。

## 验收要求

- Core task 验收：检查能力规格、API 文档、实际 Rust/UDL/test 三者一致。
- UI task 验收：检查页面规格、能力规格、control map、Swift 实现和 CoreBridge 调用一致。
- 真实闭环 task 中，如果 UI 仍使用 mock、fixture、硬编码状态或静态示例数据，验收必须判定不通过。
- 如果 Core 能力无页面消费且 control map 未声明为内部能力，验收必须判定该任务越界。

## 推荐粒度

- Repo 能力：路径校验、空库初始化、非空目录接管、配置读写分开。
- Import 能力：copy、move、index、duplicate、name conflict 分开。
- Query 能力：列表、详情、日志、笔记、Tree 分开。
- Sync 能力：created、renamed、removed 分开。
- UI 任务：首次启动、主窗口、单文件导入、批量/文件夹导入、冲突、详情/日志/笔记、设置/错误恢复分开。
- AI 能力：配置、本地模型、远程 provider、建议生成、采纳写入、日志、隐私规则、fallback 分开。
- 多端能力：repo connect、平台能力、watcher、导入、冲突、缺失恢复、rescan 分开。
