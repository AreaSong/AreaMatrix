# CI Governance

> AreaMatrix 的持续集成治理：所有 PR 都要跑核心、macOS、prompt、skill 和治理门禁。
>
> 阅读时长：约 4 分钟。

---

## 目标

CI 是合并前的最低共同质量线。它不能替代 review，但可以阻止明显不完整、不可复现或不可追溯的改动进入主线。

## 必跑矩阵

| Workflow | 目的 | 触发 |
|---|---|---|
| `core-ci.yml` | Rust fmt、clippy、test、universal build、coverage | 所有 PR、main push |
| `macos-ci.yml` | Xcode build/test、SwiftLint、SwiftFormat | 所有 PR、main push |
| `governance-ci.yml` | governance files、skills、task-loop、prompt doctor、diff check | 所有 PR、main push |

macOS app 工程尚未存在时，`macos-ci.yml` 可以按现有保护逻辑跳过 app build/test，但 workflow 本身必须运行。

## 本地等价检查

提交前至少运行与改动范围匹配的检查：

```bash
bash scripts/check-governance.sh
bash scripts/check-skills.sh
bash scripts/check-task-loop.sh
python3 tasks/prompts/_shared/prompt_pipeline.py doctor
git diff --check
```

Rust 改动：

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --all-targets --all-features -- -D warnings
cd core && cargo test --workspace
```

Swift 改动：

```bash
bash scripts/check-macos-tests.sh
swiftlint --strict
swiftformat --lint .
```

`scripts/check-macos-tests.sh` 会优先执行标准 `xcodebuild test`。只有本地沙箱阻断
`testmanagerd` 通信时，才改用 `xcrun xctest` 执行已构建的 XCTest bundle；CI
仍以 `.github/workflows/macos-ci.yml` 中的 `xcodebuild test` 为远端门禁。

## 失败处理

- CI 失败默认阻断合并。
- 修复 CI 失败优先于继续堆叠功能。
- 环境性失败必须在 PR 中写明失败 job、错误摘要、重跑结果和残余风险。
- 不允许用本地截图替代可复现命令输出。

## Task-loop 与 CI

Task-loop 的 `VERIFY_RESULT: PASS` 是单任务验收证据。合并前仍需 CI 作为远端质量门禁。

如果 `GIT_CHECKPOINT=push` 自动上传 PASS task：

- commit 必须包含 progress/log/summary evidence；
- PR 仍需要 governance/core/macos CI；
- CI 失败时不得继续合并，需要新 commit 修复。

## 跳过规则

只有以下情况允许跳过部分检查：

- 目标工程尚未存在，workflow 内部已显式检测并说明。
- 外部服务不可用，且 PR 描述记录了命令、错误和补跑计划。
- 文档-only 改动无需跑产品 build，但 governance/prompt/skill 检查仍必须跑。

## Related

- [testing.md](testing.md)
- [git-workflow.md](git-workflow.md)
- [dependency-policy.md](dependency-policy.md)
- [../../CODE_REVIEW.md](../../CODE_REVIEW.md)
