# Engineering Quality Rules

> 目标：每个 AreaMatrix prompt task 都按可维护、可验证、可长期演进的工程标准交付，而不是只让当前命令跑通一次。

## 必读源

- `docs/development/coding-standards.md` 是 Rust、Swift、Markdown、Mermaid 的编码规范源事实。
- 本文件是 prompt 执行与验收的工程质量门禁；copy-ready 和 verify-ready 都必须执行。

## 总原则

1. **真实闭环优先**：实现必须连接真实代码路径、真实数据结构和真实错误处理；占位、空壳、硬编码通过态、只为测试而绕过业务路径，都不能算完成。
2. **逻辑清晰优先**：数据流、控制流、错误流要能被后续维护者直接读懂；复杂逻辑必须拆分到命名清楚的小函数或类型。
3. **边界清楚优先**：只做当前 task 的 `Expected New Paths` 和绑定能力；不得顺手实现相邻 task，也不得把后续架构塞进当前任务。
4. **可测试优先**：新增行为必须有与风险匹配的单元、集成或脚本验证；无法运行时要说明具体环境缺口与残余风险。
5. **可回溯优先**：完成报告必须说明改动范围、验证证据、未运行检查、残余风险；不能用“应该可以”“看起来没问题”代替证据。

## 实现门禁

执行 task 时必须满足：

- 先读取 task、manifest、`Exact Docs`、`Existing Code`，再开始实现。
- 遵守 `docs/development/coding-standards.md` 的文件长度、函数长度、嵌套层级、错误处理和命名要求。
- Rust 库代码不得使用 `unwrap()` / `expect()` / `panic!()` 处理可恢复业务错误；测试中的 `expect` 必须有清楚信息。
- Swift 生产代码不得使用 `try!`、无根据的强制解包、View body 内 IO、绕过 `CoreBridge` 的 UniFFI 直接调用。
- 新增 public Rust API 必须有 rustdoc；复杂行为要说明 `# Errors`，必要时补 `# Examples`。
- 注释只解释 WHY、约束、权衡或安全边界；不要重复代码已经表达的 WHAT。
- 错误处理必须显式、可传播、可观察；不得静默吞掉失败或只写 `TODO`。
- 测试和验证必须覆盖正常路径、关键失败路径、边界条件；高风险边界要有文件系统、DB、回滚或隐私证据。
- 不为通过验收引入 mock-only wiring、fixture-only workflow、测试专用分支或硬编码完成状态。

## 验收门禁

验收 task 时必须把以下问题视为不通过：

- task checklist 或 completion standard 任一项缺证据。
- manifest 的 `Expected New Paths` 未真实落地，或 `Forbidden Touches` 被违规触碰。
- 文档定义了行为，但实现没有连接真实业务路径。
- 代码只满足单次运行，缺少错误处理、边界处理、可维护结构或必要测试。
- 新增代码明显违反编码规范，例如函数过长、嵌套过深、公共 API 无文档、生产路径 `unwrap()`、Swift 强制解包、无理由全局状态。
- 任务声称完成，但 validation 没运行、失败未解释、或 dry-run 被当成产品实现证据。

## 报告要求

执行报告和验收报告都必须单独说明工程质量：

- 代码结构是否清晰，是否存在过度抽象或单次脚本化实现。
- 关键错误路径、边界路径是否被处理和验证。
- 注释、rustdoc、文档同步是否满足当前改动范围。
- 已运行和未运行的验证命令。
- 仍然存在的技术债、残余风险和阻断项。

## Dry-run 规则

Dry-run 只能证明 runner、prompt 生成、风险门禁或日志链路能工作；不能证明任何产品代码、业务闭环或任务完成。
