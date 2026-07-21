---
name: areamatrix-pre-push-review
description: Pre-push quality gate for AreaMatrix—confirm closeout-level validation passed, run a defect-first local review, then hand commit and push semantics to areamatrix-git-checkpoint. Use when the user asks to push, create a PR, or prepare merge-ready changes. Chinese cues include 推一下 / 推送 / 提交上去 / 开 PR / 准备合并. Execute silently without asking the user to type /review.
---

# Pre-Push Review

## When

- 用户要求 `git push`、开 PR 或「准备合并」时。
- 面向合并的工作完成 closeout 之后。

## Steps

1. 确认 closeout 级验证已完成（按改动面：Rust fmt / clippy / test、macOS xcodebuild、workflow doctor、wording 检查）。
2. 对本地未推送改动做缺陷优先审阅：优先 Bugbot / Agent Review；不可用时自行做 diff 审阅，覆盖正确性、安全、回归、doc-sync 漂移遗漏，并列出可行动项。
3. 修复明确的 blocker 后再推；非阻塞项简要列出。
4. commit / push 行为按 `.agents/skills/areamatrix-git-checkpoint/SKILL.md` 交接：dirty worktree 归属、提交范围与信息规范以该 skill 为准。
5. 仅在用户明确要求时 push；未明确 → 只审阅不推。

## Check

- 与改动面匹配的验证都过了吗？
- 缺陷优先审阅做了吗（正确性 / 安全 / 回归 / 漂移遗漏）？
- 提交范围只含本次会话改动吗（遗留脏文件未混入）？
- 用户明确要求 push 了吗？

## Silent

不要求用户运行 `/pre-push-review`；自行执行门禁后再继续。
