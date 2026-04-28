# Changelog

All notable changes to AreaMatrix will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
