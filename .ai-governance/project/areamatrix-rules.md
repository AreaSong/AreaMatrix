# AreaMatrix Project Rules

> AreaMatrix 项目专用规则：文档为源事实，本地优先，用户文件安全优先。

## 项目结构目标

```text
AreaMatrix/
├── core/              # Rust 核心库
├── apps/              # 平台原生应用，macOS 为第一目标，其他平台为早期表面层
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
根 `AGENTS.md` 持有任务到 repo-local skill 的路由表；新增或删除 skill 时必须同步该表，
一致性由 `./dev check skills` 校验。
v1 历史 prompt 执行队列已完成并归档在
`workflow/versions/v1-mvp/execution/`；不得为了整理状态重写历史
`progress.json`、task-loop logs、checkpoint 或 evidence。未来真实版本必须先通过
`workflow/versions/<version>/discussion/`、middle-layer、changes、plans、drafts、
queue、promotion preview、显式 approval 和 live mapping，才允许进入对应版本的
`execution/`。
轻量独立任务使用 `tasks/active/<number>.<slug>/` 和
`tasks/done/YYYY/<number>.<slug>/`，由 `./dev tasks` 按数字索引进度；
`tasks/backlog/` 是候选池，不算当前进度，不进入 live runner，也不替代 workflow
promotion。
`.build/`、`build/`、`core/target/`、`apps/*/.build`、`apps/**/bin`、
`apps/**/obj`、`apps/macos/DerivedData/` 等本地生成物应通过 ignore / editor
exclude 隐藏，不纳入源码目录语义。

## 文档源事实

- 产品范围：`docs/product/`
- 架构与目录：`docs/architecture/`
- Core API：`docs/api/core-api.md`
- 开发规范：`docs/development/`
- 企业治理适配、项目章程、RAID 与生命周期：`docs/governance/`
- v1 source docs archive：`workflow/versions/v1-mvp/source-docs/`
- 版本化 workflow：`workflow/versions/`、`workflow/templates/`
- 长期路线图：`docs/roadmap/version-roadmap.md`

## 长期源事实口径

- `docs/**`、`core/**`、README、Core API / UDL、ADR、开发规范和治理规则应表达长期产品、架构、API、UX、测试或发布事实，不使用阶段性执行口径替代长期语义。
- 长期源事实不得新引入 `stage` / `phase` / `MVP` / `local-qa` / `unnotarized` / `prerelease` / `release gate` / `alpha` / `beta` / `milestone` / `iteration` / `sprint` / `C1-C4` / `S1-S4` 等作为当前命名、当前发布轨道、当前 API 合同、当前任务拆解或当前完成标准。
- 中文长期文档不得用“本任务”“对应版本任务”“任务补齐”“后续任务”“页面任务”“apply 任务”“任务拆解”“implementation 任务”“后续 apply 行为”“后续清理能力”“临时 mock”“静态占位”“假数据”“交付期”“临时版本”“进入对应阶段”“核心交付”“计划交付”“时间预算”“第一刀”“能力规格”“最终验收”“真实闭环验收”或 `GL-*` 等执行期措辞描述当前产品事实。
- 严格长期源层包括 `docs/**`、Core 正式代码面、Core API / UDL、README、ADR、开发规范和治理规则；这些文件不得散落具体旧发布轨道名或历史任务编号。需要追溯归档时，优先引用 `workflow/versions/README.md`、`workflow/versions/source-docs-guide.md` 或 residual ledger 等中性入口，不在长期源事实中重复深层历史路径和旧分发名称。
- 允许保留明确标注为历史归档、证据、旧执行实例或工具兼容说明的引用；上下文必须说明它们不是当前模板、当前发布命名或当前执行状态。`core/tests/**` 中的历史证据断言必须集中在专门测试文件，并用中性测试命名标明 archived evidence，不得扩散到普通 fixture、source、id 或 detail_json。
- 允许保留合法技术语义，例如事务式 `staging` / `staged`、Xcode `Build Phase`、macOS beta 测试、DB schema/migration version、外部 API version、Cargo dependency version、UUID v4、示例数据中的 `alpha` / `beta`。
- 修改长期源事实、Core API / UDL、README、repo-local skill、治理规则或相关测试后，必须运行 `./dev check wording` 或 `./dev wording audit --show-allowed`，确认剩余命中均为治理规则清单、集中归档证据、合法技术语义或 fixture 示例数据。

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

## 企业治理门禁

- 所有中高风险变更按 `docs/governance/enterprise-workflow-baseline.md` 选择 L0-L4 和 G0-G8 当前门禁。
- `@AreaSong` 可以合并产品、技术、数据、安全协调和发布准备角色，但 L3/L4 缺少独立合格复核时必须保持 blocked。
- 外部签名、公证、测试参与者、远端 CI 和 AreaFlow execution 必须保留真实 external/deferred 状态，不能用本地检查替代。
- 长期文档 owner、状态、复审触发和外部依赖统一登记到 `docs/governance/governance-register.yaml`。

## 安全重点

- 用户原文件、`.areamatrix/` 元数据、DB、staging 临时区、索引、日志、配置和 AI 请求 / 响应内容是默认保护资产。
- 文件系统与 DB、导入 staging 区与最终目录、FSEvents / iCloud 外部事件、本机与远程 AI /
  网络服务之间都是默认信任边界。
- 命中高风险边界的设计或 review 必须说明 abuse path、缓解措施和 residual risk，不能只写“已考虑安全”。

## 分层约束

- Core 层只做平台无关业务逻辑。
- FFI 层只描述跨语言类型和函数。
- Swift 平台层处理 AppKit、FSEvents、iCloud、OSLog。
- SwiftUI 层只做状态与视图，不直接做文件 IO。

## 验证基线

- Workflow 结构：`./dev workflow doctor`
- 版本化 workflow：`./dev workflow doctor`
- v1 历史 prompt 执行库审计 / 恢复：
  `python3 workflow/versions/v1-mvp/execution/_shared/prompt_pipeline.py doctor`
- Rust：`cargo fmt`、`cargo clippy`、`cargo test`
- Swift：`xcodebuild test`、SwiftFormat、SwiftLint
- 发布前：按 `docs/development/testing.md` 的手工冒烟清单验证。
