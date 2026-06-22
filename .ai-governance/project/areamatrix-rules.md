# AreaMatrix Project Rules

> AreaMatrix 项目专用规则：文档为源事实，本地优先，用户文件安全优先。

## 项目结构目标

```text
AreaMatrix/
├── core/              # Rust 核心库
├── apps/              # 平台原生应用，macOS 为当前主目标
├── docs/              # 产品、架构、API、开发与路线图源事实
├── assets/            # 品牌资产与非源事实视觉原型
├── scripts/           # 构建、检查与 task-loop 支撑脚本
├── workflow/          # 版本讨论、计划、预览、promotion gate 与版本内执行层
├── tasks/             # 轻量任务进度、完成归档、候选池和模板
├── .ai-governance/    # AI 治理源事实
├── .codex/            # Codex skills 源、模板、引用和本地运行材料
├── .agents/skills/    # repo-local skills 的发现投影
├── .github/           # GitHub issue、PR 与 CI 配置
├── dev                # 本地检查入口
└── task-loop          # prompt task-loop 入口
```

`.codex/skills-src/`、`.agents/skills/`、`workflow/`、`dev`
和 `task-loop` 是固定工具入口，目录收紧时不得为了视觉简洁而移动或重命名。
v1 历史 prompt 执行队列位于 `workflow/versions/v1-mvp/execution/`。
轻量独立任务使用 `tasks/active/<number>.<slug>/` 和
`tasks/done/YYYY/<number>.<slug>/`，供未来 `./dev tasks` 按数字索引进度；
`tasks/backlog/` 是候选池，不算当前进度，不进入 live runner。
`.build/`、`build/`、`core/target/`、`apps/*/.build`、`apps/**/bin`、
`apps/**/obj`、`apps/macos/DerivedData/` 等本地生成物应通过 ignore / editor
exclude 隐藏，不纳入源码目录语义。

## 文档源事实

- 产品范围：`docs/product/`
- 架构与目录：`docs/architecture/`
- Core API：`docs/api/core-api.md`
- 开发规范：`docs/development/`
- MVP 拆解：`workflow/versions/v1-mvp/source-docs/roadmap/stage-1-mvp.md`
- 长期路线图：`docs/roadmap/milestones.md`

## 资产与原型边界

- `assets/brand/` 是品牌资产入口；`assets/brand/final/` 是权威可引用版本。
- `assets/prototypes/` 只保存 landing、workspace 等视觉原型和辅助脚本；它不定义产品、架构、API、UX 或任务执行源事实。
- 若视觉原型中的内容需要成为长期产品事实，必须先同步到 `docs/` 的对应产品、架构、API 或 UX 文档。

## 高风险项目边界

- 任何用户文件删除、移动、覆盖、重命名都属于高风险。
- 非空目录接管必须先索引，不得改变原文件布局。
- DB migration 必须有升级、回滚或恢复说明。
- staging recovery 必须保证失败不污染最终目录。
- FSEvents 与 iCloud 处理必须考虑重复事件、延迟、占位符和外部改动。
- 自动概览默认写入 `.areamatrix/generated/`，不得默认覆盖 `README.md`。
- 远程 AI 调用、用户数据离开本机、日志或错误上报暴露敏感路径 / 内容时，必须说明隐私影响、明示同意、数据最小化和回滚 / 关闭路径。

## 安全重点

- 用户原文件、`.areamatrix/` 元数据、DB、staging 临时区、索引、日志、配置和 AI 请求 / 响应内容是默认保护资产。
- 文件系统与 DB、一阶段 staging 与最终目录、FSEvents / iCloud 外部事件、本机与远程 AI / 网络服务之间都是默认信任边界。
- 命中高风险边界的设计或 review 必须说明 abuse path、缓解措施和 residual risk，不能只写“已考虑安全”。

## 分层约束

- Core 层只做平台无关业务逻辑。
- FFI 层只描述跨语言类型和函数。
- Swift 平台层处理 AppKit、FSEvents、iCloud、OSLog。
- SwiftUI 层只做状态与视图，不直接做文件 IO。

## 验证基线

- Prompt 执行体系：`python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py doctor`
- Rust：`cargo fmt`、`cargo clippy`、`cargo test`
- Swift：`xcodebuild test`、SwiftFormat、SwiftLint
- 发布前：按 `docs/development/testing.md` 的手工冒烟清单验证。
