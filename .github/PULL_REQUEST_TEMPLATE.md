<!--
感谢提交 PR！请按下方模板填写。
Thanks for the PR! Please fill out the template below.
-->

## 改动摘要 / Summary

<!-- 一两句话说明这个 PR 做了什么 -->

## 改动动机 / Motivation

<!-- 为什么需要这个改动？解决了什么问题？ -->
<!-- 关联 issue: Closes #xxx / Related to #xxx -->

## 改动内容 / Changes

<!-- 具体改了哪些模块、哪些行为发生了变化 -->

- [ ]
- [ ]

## 改动类型 / Change Type

- [ ] Bug 修复（不破坏兼容性）/ Bug fix (non-breaking)
- [ ] 新功能（不破坏兼容性）/ New feature (non-breaking)
- [ ] 破坏性变更 / Breaking change
- [ ] 文档更新 / Documentation only
- [ ] 重构（无行为变化）/ Refactor (no behavior change)
- [ ] 性能优化 / Performance improvement
- [ ] 测试 / Tests
- [ ] CI / 工程化 / CI / Tooling

## 测试方式 / How to Test

<!-- 评审者怎么验证这个改动？给出可执行的步骤 -->

```bash
# 例：
# cargo test --package area_matrix_core --test classify_test
# 然后在 macOS app 中拖入 .pdf 文件，验证分类结果
```

## 截图 / 录屏 / Screenshots

<!-- 如果有 UI 改动，附上前后对比 -->

## 检查清单 / Checklist

- [ ] 我的代码遵循项目编码规范（[coding-standards.md](../docs/development/coding-standards.md)）
- [ ] 我已运行本地测试并通过
- [ ] 我已运行 `cargo fmt && cargo clippy -- -D warnings`（Rust 部分）
- [ ] 我已运行 SwiftFormat / SwiftLint（Swift 部分）
- [ ] 我已添加必要的单元测试 / 集成测试
- [ ] 我已更新相关文档（README / docs / API 注释）
- [ ] 我已在 `CHANGELOG.md` 的 `[Unreleased]` 段落添加条目
- [ ] Commit 信息符合 [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] 这个 PR 不引入未授权的第三方资源 / 商业 logo
- [ ] 这个 PR 不包含许可证不兼容的代码

## 给评审者的备注 / Notes for Reviewer

<!-- 任何需要提醒评审者特别关注的点：不确定的设计、潜在的副作用、跳过的边界等 -->
