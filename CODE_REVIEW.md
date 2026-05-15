# Code Review Policy

> AreaMatrix 的代码评审规则：把功能正确性、用户文件安全、工程质量、测试证据和可追溯性作为同一套合并门禁。
>
> 阅读时长：约 5 分钟。

---

## 评审目标

Code review 不是只看代码风格。评审必须确认：

- 改动符合文档源事实、ADR 和任务边界。
- 实现连接真实业务路径，不是一次性脚本、占位、mock-only 或硬编码通过态。
- 用户文件、`.areamatrix/` 元数据、DB、staging、FSEvents/iCloud 和隐私边界没有被悄悄打穿。
- 失败路径、回滚或恢复路径有证据。
- 测试和 CI 能证明当前风险级别下的最小充分正确性。

## 评审分级

| 等级 | 典型改动 | 要求 |
|---|---|---|
| Low | 文案、注释、低风险 docs | 作者自测 + 一位维护者可快速合并 |
| Medium | 单模块功能、测试、脚本 | 至少 1 位维护者 review，相关测试通过 |
| High | Core API、UDL、跨层 wiring、DB、文件系统行为 | 至少 1 位熟悉该域的维护者 review，必须有验证证据 |
| Mission-Critical | 用户文件破坏性风险、migration、staging recovery、隐私、安全 | 先说明影响、风险、验证、回滚；不得只凭口头判断合并 |

## 阻断项

出现以下任一项，评审必须阻断：

- 没有读取或对齐权威文档，却改变产品/API/安全语义。
- `Expected New Paths` 缺失、`Forbidden Touches` 被触碰，或 task scope 扩散。
- 生产路径存在 `unwrap()`、`panic!()`、`try!`、强制解包、静默吞错或无理由全局状态。
- public Rust API 缺 rustdoc，复杂错误路径缺 `# Errors` 或必要示例。
- 新依赖没有说明用途、许可证、供应链风险和替代方案。
- 安全、隐私、用户文件、DB、staging 或外部同步风险缺少验证和恢复证据。
- 测试只覆盖 happy path，缺少关键失败路径、边界条件或回归用例。
- dry-run、mock-only、fixture-only 或截图被当成真实闭环证据。
- Git checkpoint 混入旧改动，或者 PASS task 没有可追溯 progress/log/summary/commit 证据。

## 评审输出格式

评审报告必须 findings first：先列可行动问题，再写简短总结或正向说明。没有问题时也要明确写出“未发现阻断性问题”，并说明剩余风险或未验证项。

每条 finding 应包含：

- **Severity**：`P0` 阻断 / `P1` 高风险 / `P2` 中风险 / `P3` 建议。
- **位置**：具体文件和行号；无法给行号时说明证据来源。
- **问题**：说明实际错误、回归风险、缺失测试、安全 / 隐私 / 用户文件风险，而不是只给风格偏好。
- **影响**：说明用户、数据、文件系统、DB、staging、FSEvents/iCloud、远程 AI 或 CI 合并门禁会受到什么影响。
- **建议**：给出最小可执行修复方向或需要补充的验证。

优先级顺序是 correctness、regression risk、missing tests、security / privacy / user-file risk、maintainability。纯风格意见不得压过可证明的行为风险。

## 评审清单

评审者按以下顺序看：

1. **范围**：PR 描述、task、manifest、ADR、CODEOWNERS 是否匹配。
2. **设计**：是否遵循 KISS、YAGNI、高内聚低耦合；是否引入不必要抽象。
3. **实现**：数据流、控制流、错误流是否清晰；复杂逻辑是否拆分。
4. **安全**：路径、权限、隐私、日志、外部输入、依赖和本地文件安全是否可证明。
5. **测试**：单测、集成、E2E、手工证据是否覆盖风险。
6. **文档**：Core API、UDL、README、ADR、CHANGELOG 和 prompt manifest 是否需要同步。
7. **CI**：必须通过相关 workflow；失败不能用“本地可以”替代。

## Task-loop PASS 后评审

自动 task-loop 的 PASS 只能说明单任务验收通过。合并前仍要看：

- `verify_log` 是否含完整验收报告和最终 `VERIFY_RESULT: PASS`。
- `progress.json`、`summary.json`、`index.json` 是否记录 task、attempt、Git 证据。
- task completion commit 和 evidence commit 是否只包含该 task 范围内的改动。
- CI 是否覆盖该改动类型；CI 未跑时必须写明原因。

## Related

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [docs/development/coding-standards.md](docs/development/coding-standards.md)
- [docs/development/testing.md](docs/development/testing.md)
- [docs/development/dependency-policy.md](docs/development/dependency-policy.md)
- [docs/development/ci-governance.md](docs/development/ci-governance.md)
- [tasks/prompts/_shared/engineering-quality-rules.md](tasks/prompts/_shared/engineering-quality-rules.md)
