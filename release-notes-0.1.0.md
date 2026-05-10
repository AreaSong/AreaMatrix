# AreaMatrix 0.1.0-local-qa

Internal QA date: 2026-05-11

This is an internal local QA artifact, not an official Stage 1 alpha release.
No `v0.1.0` tag or GitHub Release has been created.

## Highlights

- 完成 Stage 1 MVP 文档、架构决策、开发规范和 CI 治理骨架。
- 确立非空目录接管规则，自动概览默认写入 `.areamatrix/generated/`，不覆盖用户 `README.md`。
- Core API、数据模型、tree、overview、`origin`、`scan_sessions` 和 `ignore.yaml` 文档对齐。

## Validation Snapshot

- 本地 `./dev check all` 已通过，SwiftFormat 输出 `0/226 files require formatting, 3 files skipped`，
  SwiftLint 输出 `Found 0 violations, 0 serious in 228 files`。
- `AreaMatrix-0.1.0-local-qa.dmg` 已生成：
  `4e52b8e648326aaf3731fc61f12f4d576bbeeeff7a521d0efe528eec032c617b`。
- DMG 挂载后，`/Volumes/AreaMatrix 0.1.0 Local QA/AreaMatrix.app` 通过 ad-hoc
  `codesign --verify --deep --strict --verbose=2`。
- DMG 内 `.app` 可打开已配置 QA repo 主窗口：
  `applicationLaunchToFirstScreen.localQA.dmgConfiguredRepo = 668.973 ms < 1.5 s`。
- 2026-05-11 00:58 CST 同机 local QA 首启交互 smoke 已通过：
  `open -n "/Volumes/AreaMatrix 0.1.0 Local QA/AreaMatrix.app"` 成功，AppleScript 返回
  `true, 60, 50, 1500, 980, AreaMatrix`，scroll probe 输出
  `scroll_probe=posted events=7 point=900,610`。
- Stage 1 性能基线已通过，真实 Release `.app` 启动到首屏为 `777.606 ms < 1.5 s`。
- `cargo update --dry-run` 已通过，未修改 lockfile。
- `./dev release preflight` 已补为可复现预检；当前机器因缺 Developer ID Application
  signing identity 和 `AC_PASSWORD` notarytool profile 被正确判为 blocked。当前项目未加入付费
  Apple Developer Program，因此只能制作 local QA build，不能关闭正式 alpha 分发门禁。

## Known Issues

- M-01 Copy 中断恢复、M-03 权限恢复和 M-04 DB repair 已在 local QA Release build 手工通过；
  M-02 iCloud placeholder 因当前没有 iCloud placeholder 环境仍 blocked。M-03 本轮使用 local QA repo
  的可逆 POSIX 权限阻断模拟失去访问权限，未修改系统 TCC 数据库。
- Developer ID 签名、公证、DMG 和干净 Mac 首启仍需真实分发环境证据；当前本机 release
  preflight 只能证明环境 blocked，自签名、ad-hoc signed `.app` 或 local QA DMG 不能替代可分发产物。
- 同机 local QA 首启交互 smoke 不能替代干净 Mac 首启、Gatekeeper 或 notarized app 验证。
- `v0.1.0` tag 当前 pending，不创建；应在正式 release candidate 提交且 alpha 门禁关闭后创建。
