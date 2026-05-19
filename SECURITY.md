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

### 威胁建模触发与边界

威胁建模（threat model，按资产、信任边界和攻击路径分析系统风险）只在以下情况触发：

- 用户、维护者或任务明确要求 threat model / abuse path / AppSec 分析。
- 改动命中 AreaMatrix 高风险边界：用户文件、DB / migration、staging recovery、reindex、FSEvents / iCloud、隐私、远程 AI 调用、Core API / UDL 破坏性变化。
- 安全事件响应或重大架构变更需要在修复前明确风险模型。

普通 code review 仍按 [CODE_REVIEW.md](CODE_REVIEW.md) 执行。安全威胁建模不能替代普通 review、测试、CI 或 file-safety 验收；普通 review 中发现明显安全风险时，应把该风险列为 finding，并在需要时升级为威胁建模任务。

### 威胁建模清单

威胁模型报告至少覆盖：

- **资产**：用户原文件、`.areamatrix/` 元数据、DB、staging 临时区、索引、日志、配置、凭证、AI 请求 / 响应内容。
- **信任边界**：用户选择的目录与应用内部状态、Core 与 Swift 平台层、文件系统与 DB、staging 与最终目录、FSEvents / iCloud 外部事件、本机与远程 AI / 网络服务、CI / 开发工具与运行时。
- **入口**：目录接管、导入、reindex、staging recovery、文件 watcher、iCloud placeholder、Core API / UDL、日志与错误上报、远程 AI 调用、依赖和构建脚本。
- **攻击能力**：攻击者能控制哪些文件名、路径、内容、事件时序、符号链接、占位符状态、网络响应或依赖输入；同时说明不具备的能力，避免夸大严重性。
- **Abuse path**：用可复现路径描述如何造成数据丢失、越权读写、路径穿越、信息泄漏、DB / 文件系统不一致、DoS、日志泄密或远程数据外流。
- **缓解措施**：区分已有控制和建议控制，落到具体组件、边界或入口，例如路径规范化、禁止覆盖、事务 / rollback、schema 校验、in-flight event 过滤、placeholder 策略、最小化日志、AI 明示同意和数据最小化。
- **Residual risk**：说明缓解后仍存在的残余风险、依赖的假设、未验证项和后续监控。

用户文件、DB、staging、iCloud / FSEvents、隐私和远程 AI 调用是 AreaMatrix 默认高风险重点；相关威胁模型必须同时引用 file-safety 不变量和 CODE_REVIEW 合并门禁。

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

### Threat Modeling Triggers and Boundary

Threat modeling is triggered only when:

- A user, maintainer, or task explicitly asks for a threat model, abuse-path analysis, or AppSec analysis.
- A change touches AreaMatrix high-risk boundaries: user files, DB / migrations, staging recovery, reindex, FSEvents / iCloud, privacy, remote AI calls, or breaking Core API / UDL changes.
- Security incident response or major architecture work needs a risk model before remediation.

General code review still follows [CODE_REVIEW.md](CODE_REVIEW.md). Threat modeling does not replace normal review, tests, CI, or file-safety acceptance. If a general review finds an obvious security risk, list it as a finding and escalate to threat modeling only when the risk needs explicit security analysis.

### Threat Modeling Checklist

A threat model report must cover:

- **Assets**: original user files, `.areamatrix/` metadata, DB, staging area, index, logs, config, credentials, AI request / response content.
- **Trust boundaries**: user-selected folders vs internal app state, Core vs Swift platform layer, filesystem vs DB, staging vs final directories, FSEvents / iCloud external events, local machine vs remote AI / network services, CI / developer tooling vs runtime.
- **Entry points**: folder adoption, import, reindex, staging recovery, file watcher, iCloud placeholders, Core API / UDL, logs and error reporting, remote AI calls, dependencies and build scripts.
- **Attacker capabilities**: which filenames, paths, contents, event ordering, symlinks, placeholder states, network responses, or dependency inputs an attacker can control; also state non-capabilities to avoid inflated severity.
- **Abuse paths**: concrete paths to data loss, unauthorized read/write, path traversal, information disclosure, DB / filesystem mismatch, DoS, log leakage, or remote data exfiltration.
- **Mitigations**: distinguish existing and recommended controls, tied to components, boundaries, or entry points, such as path normalization, no-overwrite rules, transactions / rollback, schema validation, in-flight event filtering, placeholder policy, minimal logging, explicit AI consent, and data minimization.
- **Residual risk**: remaining risk after mitigation, assumptions, unverified items, and follow-up monitoring.

User files, DB, staging, iCloud / FSEvents, privacy, and remote AI calls are default AreaMatrix high-risk focus areas; related threat models must reference file-safety invariants and CODE_REVIEW merge gates.

### Recognition

Reporters of confirmed vulnerabilities will be credited in the corresponding [CHANGELOG.md](CHANGELOG.md) entry (let us know if you prefer anonymity).

### Out of Scope

- Known vulnerabilities in third-party dependencies (report upstream; we appreciate heads-up so we can update)
- Issues caused by users disabling security features
- Issues requiring physical access
- Social engineering
