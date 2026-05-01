# 安全政策 / Security Policy

[English](#english) | [中文](#中文)

---

## 中文

### 受支持的版本

| 版本 | 是否接受安全修复 |
|---|---|
| 0.x（pre-alpha） | 是 |
| < 0.1（pre-release） | 否 |

### 报告安全漏洞

**请不要通过公开 issue 报告安全漏洞。**

请通过私密渠道提交：

- GitHub Security Advisory：在主仓库点击 Security → Report a vulnerability

### 报告应包含

- 漏洞类型（如：越权读写、路径穿越、SQL 注入、反序列化、供应链等）
- 受影响的文件路径或函数（如有）
- 复现步骤（最小可复现）
- 影响范围（数据丢失 / 任意代码执行 / 信息泄漏 / DoS 等）
- 你的复现环境（OS / 版本 / 配置）
- 建议的修复方案（可选）

### 响应时间承诺

| 阶段 | 时限 |
|---|---|
| 初步确认 | 3 个工作日内 |
| 严重程度评估 | 7 个工作日内 |
| 修复发布（高危） | 30 天内 |
| 公开披露 | 修复发布后协调披露 |

### 严重程度分级（参考 CVSS 3.1）

| 级别 | 影响 | 例 |
|---|---|---|
| Critical | 任意代码执行、数据完全泄漏 | 通过拖入特制文件触发 RCE |
| High | 越权数据访问、关键功能绕过 | 跨用户读取资料库 |
| Medium | 部分功能拒绝服务、信息泄漏 | 路径穿越读取 .areamatrix/ 外文件 |
| Low | 体验问题、低危信息泄漏 | 错误日志包含敏感路径 |

### 致谢机制

报告并经验证的安全研究者会在 [CHANGELOG.md](CHANGELOG.md) 的对应版本记录中获得致谢（如希望保持匿名请告知）。

### 范围之外

以下不在安全报告范围：

- 第三方依赖的已知漏洞（请直接向上游报告，但欢迎告知我们以便升级）
- 用户自行禁用安全特性导致的问题
- 物理访问导致的问题
- 社会工程学攻击

---

## English

### Supported Versions

| Version | Security Fixes |
|---|---|
| 0.x (pre-alpha) | Yes |
| < 0.1 (pre-release) | No |

### Reporting a Vulnerability

**Please do not report security issues via public GitHub issues.**

Use the private reporting channel:

- GitHub Security Advisory: Repository → Security → Report a vulnerability

### Your Report Should Include

- Vulnerability class (e.g. authz bypass, path traversal, SQLi, deserialization, supply chain)
- Affected files / functions if known
- Minimal reproducible steps
- Impact (data loss / RCE / info disclosure / DoS)
- Your reproduction environment (OS / version / config)
- Suggested fix (optional)

### Response Timeline

| Stage | SLA |
|---|---|
| Initial acknowledgement | Within 3 business days |
| Severity assessment | Within 7 business days |
| Fix release (high severity) | Within 30 days |
| Public disclosure | Coordinated after fix release |

### Severity Classification (CVSS 3.1 reference)

| Level | Impact | Example |
|---|---|---|
| Critical | RCE, full data exfiltration | Crafted file drop triggers RCE |
| High | Unauthorized data access, critical bypass | Cross-user repo access |
| Medium | DoS, info disclosure | Path traversal reading outside `.areamatrix/` |
| Low | UX issues, low-risk info disclosure | Error logs containing sensitive paths |

### Recognition

Reporters of confirmed vulnerabilities will be credited in the corresponding [CHANGELOG.md](CHANGELOG.md) entry (let us know if you prefer anonymity).

### Out of Scope

- Known vulnerabilities in third-party dependencies (report upstream; we appreciate heads-up so we can update)
- Issues caused by users disabling security features
- Issues requiring physical access
- Social engineering
