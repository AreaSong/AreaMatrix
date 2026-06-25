# 工程成熟路线图

> AreaMatrix 在核心功能闭环完成后，继续把代码从“能跑”推进到“可复用、可维护、可持续高速扩展”的工程成熟状态。
>
> 阅读时长：约 6 分钟。

---

## 目标定义

本文定义的 100% 不是所有未来产品功能都完成，而是 **macOS 前端与跨层工程治理达到长期可扩展状态**。

达到 100% 时应满足：

- 新功能先找到 feature owner，再写代码。
- SwiftUI View 只负责展示和交互，不直接做文件 IO 或平台副作用。
- Swift 调用 Rust Core 只走 `CoreBridge` 和受控 Bridge 扩展。
- `Bridge/Generated/` 与 `Bridge/UniFFI/` 保持纯生成绑定。
- FileManager、iCloud、FSEvents、open/save panel、NSWorkspace、Pasteboard 等平台能力进入 `PlatformServices/` 或明确迁移路径。
- Import、FileActions、Settings、AI、Search、MainList 等功能域有稳定落点。
- 高风险用户文件边界有固定评审、验证和回滚口径。
- 测试支撑能复用，新增 feature 不需要重复搭建 fixture 和 mock。
- 架构规则能通过文档、review 和自动化检查防止漂移。

## 当前进度口径

当前状态：

- 核心功能闭环：已完成。
- 顶层运行架构：已清晰，采用 Rust Core / UniFFI / Swift Platform / SwiftUI Feature UI。
- macOS 前端落点规则：已稳定起步，已有 `Features/MainList/`、`Features/FileActions/`、
  `Features/Search/`、`Features/CommandPalette/`、`Features/SyncConflicts/`、
  `Features/AI/` 和 `PlatformServices/`。
- 执行层复用：仍在迁移中。主要 feature owner 已开始归位，但 `Views/Main`、顶层
  `Models`、Import / Settings / Onboarding 以及测试支撑仍承载较多历史代码。
- 当前治理重点：从“功能各自能跑”继续推进到“状态、动作、routing、validation、测试
  fixture 可以跨 feature 复用”。

因此当前工程成熟度按本文口径约为 40%-45%。这不是功能完成度，而是工程治理成熟度。

## 治理路线

### 1. Checkpoint 第一轮治理

目标：冻结已完成的架构规则和低风险归位成果。

范围：

- `apps/macos/AGENTS.md`
- `docs/architecture/macos-frontend-architecture.md`
- `docs/architecture/layered-design.md`
- `PlatformServices/` 起步
- `Features/Search/` 起步
- Bridge startup recovery 归位

完成标准：

- macOS build 和 test 通过。
- docs / governance / quality / prompt / diff 检查通过。
- 后续改动能明确从这个节点继续演进。

### 2. MainList 样板化

目标：建立第一个低风险、主路径 feature 样板。

状态：已起步，列表过滤、selection、状态 banner、当前列表错误视图和多选详情入口已归入
`Features/MainList/`；后续重点是继续收敛剩余 `MainFileList*` 状态与 Detail / Search /
FileActions 交界。

范围：

- 当前列表过滤与展示 helper。
- selection / detail entry / loading / current list error 等状态边界。
- 主列表 route 与 Search / FileActions / Detail 的交界。

完成标准：

- `Features/MainList/` 成为新增主列表能力的默认落点。
- `Views/Main` 不再继续吸收新的主列表业务逻辑。
- 顶层 `Models` 中 MainList 相关文件减少，剩余文件有明确迁移原因。

### 3. FileActions 收拢

目标：统一 rename、delete、change category、batch actions、tag actions 的动作边界。

状态：已起步，rename / delete / change category / batch state / routing actions 已归入
`Features/FileActions/`；后续重点是沉淀单文件、多选和批量动作的共享执行模式。

范围：

- action state。
- sheet routing。
- CoreBridge 调用边界。
- 错误映射和刷新策略。

完成标准：

- 新增文件动作时进入 `Features/FileActions/`。
- 单文件、多选、批量动作共享可复用支撑。
- 高风险删除、移动、重命名路径保持显式确认和测试证据。

### 4. SyncConflicts owner 归位

目标：把 iCloud conflict / sync conflict 的 review、preview、resolve、entry banner 与 routing
收敛到独立 feature，同时保持 Bridge 和用户文件安全边界清晰。

状态：已起步，iCloud conflict / sync conflict 的主要 View、Model、State、Apply context 和
routing actions 已归入 `Features/SyncConflicts/`；Bridge 封装仍保持在 `Bridge/`。

范围：

- iCloud conflict list / minimal review / resolution apply context。
- sync conflict entry / review / replace confirmation。
- review route 与 MainList / FileActions / Settings 入口交界。
- CoreBridge conflict listing / detecting / resolving 边界。

完成标准：

- 新增 conflict review 或 resolution UI 默认进入 `Features/SyncConflicts/`。
- Bridge 继续作为 Core conflict API 的唯一手写入口。
- read-only listing、preview、resolve、Trash / backup / change-log 安全语义有测试证据。
- 不把 iCloud 下载、文件删除、覆盖、移动行为藏进 SwiftUI View。

### 5. Import 高风险治理

目标：把导入路径变成高风险 feature 的标准模板。

范围：

- single file import。
- folder preview / scanner / batch import。
- duplicate conflict。
- iCloud placeholder。
- copy / move / index 模式。
- result summary 和 retry / recovery。

完成标准：

- `Features/Import/` 有清晰 View / Model / State / Actions / Support 边界。
- 任何真实用户文件写入、移动、覆盖、占位符下载都能对应验证和回滚说明。
- 不把 FileManager 或 iCloud 副作用藏进 SwiftUI View。

### 6. Settings 分区

目标：设置页按能力域稳定拆分，避免继续膨胀。

范围：

- General。
- Repository。
- Classifier。
- Integrations。
- Advanced。
- Diagnostics。
- Recovery。
- Privacy / AI。

完成标准：

- 新增设置项能找到稳定 owner。
- 设置页 model 不继续吸收无关平台能力。
- 危险设置项保留确认、失败回滚和恢复入口。

### 7. AI feature 稳定化

目标：让 AI 能力继续扩展时不污染隐私、远程 provider、UI 状态和 CoreBridge 边界。

状态：已起步，provider config、privacy rules、summary、classification suggestion、remote probe
等能力已有 `Features/AI/` 落点；后续重点是继续拆解接近 500 行的状态文件并收敛隐私 /
provider 执行支撑。

范围：

- provider config。
- privacy gate。
- summary editor。
- classification suggestion。
- semantic search fallback。
- call log / provenance。

完成标准：

- AI 远程调用、用户数据离开本机、provider credential 都有明确边界。
- AI UI 状态和 Core / provider 调用不混在同一个大文件里。
- 本地优先与显式授权规则可被测试和 review。

### 8. PlatformServices 完整化

目标：统一平台副作用落点。

范围：

- FileManager。
- iCloud。
- FSEvents。
- NSOpenPanel / NSSavePanel。
- NSWorkspace。
- NSPasteboard。
- system capability probing。

完成标准：

- SwiftUI View 不直接做平台副作用。
- 可复用平台服务通过小接口注入 model 或 app shell。
- 仍留在 `App/` 或 `Models/` 的平台能力有退出条件。

### 9. Tests Support 收敛

目标：让测试支撑成为工程资产。

范围：

- temporary repo builder。
- mock bridge / recording bridge。
- fixture factories。
- assertion helpers。
- feature-local test support。

完成标准：

- 新增 feature 测试不复制大段支撑代码。
- 高风险路径有失败、回滚、恢复和 forbidden-touch 证据。
- fixture 命名能反映 feature owner。

### 10. 架构边界自动化

目标：让关键规则可检查。

候选检查：

- View / feature model 不直接调用 UniFFI 生成函数。
- `Bridge/Generated/` 和 `Bridge/UniFFI/` 无手写业务逻辑。
- 新增平台副作用优先进入 `PlatformServices/`。
- 新增复杂业务视图优先进入 `Features/<FeatureName>/`。
- Core API / UDL / docs drift 检查保持可见。

完成标准：

- 本地 check 或 CI 能发现主要架构漂移。
- review 不再完全依赖人工记忆。

### 11. 文档与治理闭环

目标：保证工程规则长期不失真。

范围：

- `docs/architecture/**`
- `docs/roadmap/**`
- `apps/macos/AGENTS.md`
- `CODE_REVIEW.md`
- CI / governance checks

完成标准：

- 文档讲清楚当前架构、执行路径、验证口径和非目标。
- 新人读文档能知道代码该放哪里。
- 每轮 feature 治理都更新对应完成证据或残余风险。

## 执行原则

- 不做一次性全仓库大搬家。
- 不为了行数拆分而拆分。
- 不改变 UI 行为作为架构治理的副作用。
- 不修改 Core API / UDL，除非发现明确漂移并单独评审。
- 不新增依赖，除非完成用途、许可证、替代方案和供应链风险评审。
- Import、FSEvents、iCloud、DB、reindex、staging recovery、删除、移动、覆盖等高风险边界必须单独说明影响、风险、验证和回滚。

## 验证策略

按改动路径选择最小充分验证：

- macOS 代码改动：

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -scheme AreaMatrix -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO
./dev test macos
```

- docs / governance / prompt 相关改动：

```bash
./dev check governance
./dev check skills
./dev check quality
./dev check prompts
./dev check diff
```

- workflow discussion 或 execution 结构变更：按 `workflow/AGENTS.md` 运行对应 doctor。

## 进度更新规则

本文的百分比只表示工程成熟度，不表示产品功能数量。更新时必须依据当前文件、验证命令和审计证据，不根据主观感觉调整。

## Related

- [version-roadmap.md](version-roadmap.md)
- [../architecture/macos-frontend-architecture.md](../architecture/macos-frontend-architecture.md)
- [../architecture/layered-design.md](../architecture/layered-design.md)
- [../architecture/ffi-design.md](../architecture/ffi-design.md)
- [../development/testing.md](../development/testing.md)
- [../../CODE_REVIEW.md](../../CODE_REVIEW.md)
