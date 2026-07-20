# Changelog

All notable changes to AreaMatrix will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- 记录 v1 分发证据归档中的内部验证产物与未公证测试者预览产物，并保存 checksum。
- 补充 iCloud placeholder、Developer ID / notarization 后续补证模板，并记录同机首启交互 smoke。
- 记录 GitHub immutable release / tag 规则对测试者预览产物编号复用的限制。
- 新增 `docs/security/threat-model.md` 威胁模型：信任边界、威胁主体、数据分类、控制映射与复审触发。
- 治理登记册新增 `document_domains` 域级 owner 与复审登记，覆盖 `docs/` 全部顶层文档域。

### Changed
- v1 release notes 调整为内部验证说明，不再暗示正式分发。
- 本地验证打包命令改为显式 ad-hoc bundle signing、静态链接 Rust core，并在构建后验证
  bundle 签名和自包含链接状态，避免测试包依赖开发机 dylib。
- 企业治理基线按 2026-07 审计结论修订：上游快照保持与原始文件逐字节一致、补充结构裁剪记录、
  RAID 增加 probability/impact/impact_scope 维度；治理检查同步强化威胁模型、文档域覆盖与
  快照 hash 漂移校验；v2 治理账本补齐 charter/ops/威胁模型登记并重新钉扎 baseline。

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
- v1 产品口径调整为支持非空目录接管；自动概览默认写入 `.areamatrix/generated/`，不覆盖 `README.md`
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
- v1 分发证据仍需补齐 M-02 iCloud placeholder 真实环境手工冒烟；M-01 Copy
  中断恢复、M-03 权限恢复和 M-04 DB repair 已在内部 Release build 手工通过。
- M-03 使用可逆 POSIX 权限阻断模拟失去访问权限，未修改系统
  TCC 数据库；如需发布机 TCC 数据库级证据，应在后续真实分发环境补测。
- 当前未加入付费 Apple Developer Program；自签名、ad-hoc signed `.app` 或内部测试 DMG
  不能替代 Developer ID 签名、公证、DMG、干净 Mac 首启和 `v0.1.0` tag。
- 未公证测试者预览产物只是可信测试者验证材料，不是正式分发；它未使用 Developer ID
  签名，未公证，也未 stapled。
- 同机首启交互 smoke 不能替代干净 Mac 首启、Gatekeeper 或已公证 app 验证。

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
