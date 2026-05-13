# Changelog

All notable changes to AreaMatrix will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- 生成 `0.1.0-local-qa` 内部测试产物：ad-hoc signed `AreaMatrix.app`、
  `AreaMatrix-0.1.0-local-qa.dmg` 和 SHA-256 checksum。
- 补充 iCloud placeholder、Developer ID / notarization 后续补证模板，并记录同机 local QA
  首启交互 smoke。

### Changed
- `release-notes-0.1.0.md` 调整为 `0.1.0-local-qa` 内部测试说明，不再暗示正式 alpha 发布。

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- 拆分批量导入执行和 session persistence 代码，关闭 SwiftLint `file_length` 工程门禁。

### Security
- N/A

---

## [0.1.0] - 2026-05-10

### Added
- 项目文档体系完整产出（README 双语 / docs / .github 模板 / CI 工作流配置）
- PolyForm Noncommercial 1.0.0 许可证 + COMMERCIAL_LICENSE.md 商业授权窗口
- 10 篇 ADR 固化关键架构决策
- ADR-0010：接管已有目录与专属概览文件决策
- `docs/architecture/adopt-existing-folders.md`：补齐接管已有目录的分类、拖入目标、忽略规则、扫描恢复与来源标记

### Changed
- 顶层 README.md 由占位说明改为正式项目门面（中英双语）
- Stage 1 产品口径调整为支持非空目录接管；自动概览默认写入 `.areamatrix/generated/`，不覆盖 `README.md`
- Core API / 数据模型 / tree / overview 文档同步 `origin`、`scan_sessions`、`ignore.yaml` 与顶层节点概览规则

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- N/A

### Security
- N/A

### Known Issues
- Stage 1 alpha 分发仍需补齐 M-02 iCloud placeholder 真实环境手工冒烟；M-01 Copy
  中断恢复、M-03 权限恢复和 M-04 DB repair 已在 local QA Release build 手工通过。
- M-03 本轮使用 local QA repo 的可逆 POSIX 权限阻断模拟失去访问权限，未修改系统
  TCC 数据库；如需发布机 TCC 数据库级证据，应在后续真实分发环境补测。
- 当前未加入付费 Apple Developer Program；自签名、ad-hoc signed `.app` 或 local QA DMG
  不能替代 Developer ID 签名、公证、DMG、干净 Mac 首启和 `v0.1.0` tag。
- 同机 local QA 首启交互 smoke 不能替代干净 Mac 首启、Gatekeeper 或 notarized app 验证。

---

## 版本发布约定

- **版本号格式**：`MAJOR.MINOR.PATCH`（语义化版本）
- **MAJOR**：破坏性变更（数据库 schema 不兼容、Core API 不兼容、配置文件 schema 不兼容）
- **MINOR**：向后兼容的功能增加
- **PATCH**：向后兼容的 bug 修复

### 变更类别

每个版本下的变更分为以下类别：

- **Added**：新功能
- **Changed**：现有功能的变更
- **Deprecated**：即将移除的功能
- **Removed**：本版本移除的功能
- **Fixed**：bug 修复
- **Security**：安全相关修复

### 写作规范

- 每条变更一行，简洁说明
- 引用相关 issue / PR：`(#123)`
- 致谢贡献者：`(@username)`
- 安全致谢：`Reported by @username`

### 模板

```markdown
## [x.y.z] - YYYY-MM-DD

### Added
- 新增 xxx 功能 (#issue) (@author)

### Fixed
- 修复 xxx bug (#issue)

### Security
- 修复 xxx 漏洞，Reported by @reporter (CVE-2026-xxxx)
```
