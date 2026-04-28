# AreaMatrix Project Rules

> AreaMatrix 项目专用规则：文档为源事实，本地优先，用户文件安全优先。

## 项目结构目标

```text
AreaMatrix/
├── core/              # Rust 核心库
├── apps/macos/        # SwiftUI macOS App
├── scripts/           # 构建与检查脚本
├── docs/              # 项目文档
├── tasks/prompts/     # 可执行 prompt 任务库
├── .ai-governance/    # AI 治理源事实
└── .codex/            # Codex 适配材料
```

## 文档源事实

- 产品范围：`docs/product/`
- 架构与目录：`docs/architecture/`
- Core API：`docs/api/core-api.md`
- 开发规范：`docs/development/`
- MVP 拆解：`docs/roadmap/stage-1-mvp.md`
- 长期路线图：`docs/roadmap/milestones.md`

## 高风险项目边界

- 任何用户文件删除、移动、覆盖、重命名都属于高风险。
- 非空目录接管必须先索引，不得改变原文件布局。
- DB migration 必须有升级、回滚或恢复说明。
- staging recovery 必须保证失败不污染最终目录。
- FSEvents 与 iCloud 处理必须考虑重复事件、延迟、占位符和外部改动。
- 自动概览默认写入 `.areamatrix/generated/`，不得默认覆盖 `README.md`。

## 分层约束

- Core 层只做平台无关业务逻辑。
- FFI 层只描述跨语言类型和函数。
- Swift 平台层处理 AppKit、FSEvents、iCloud、OSLog。
- SwiftUI 层只做状态与视图，不直接做文件 IO。

## 验证基线

- Prompt 执行体系：`python3 tasks/prompts/_shared/prompt_pipeline.py doctor`
- Rust：`cargo fmt`、`cargo clippy`、`cargo test`
- Swift：`xcodebuild test`、SwiftFormat、SwiftLint
- 发布前：按 `docs/development/testing.md` 的手工冒烟清单验证。

