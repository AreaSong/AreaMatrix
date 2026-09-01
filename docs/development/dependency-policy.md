# Dependency Policy

> AreaMatrix 的依赖、许可证与供应链规则：默认少依赖、可解释、可锁定、可替换、许可证兼容。
>
> 阅读时长：约 4 分钟。

---

## 原则

1. **少即是稳**：标准库或现有依赖能解决时，不新增依赖。
2. **用途明确**：每个新增依赖都必须说明解决的问题和替代方案。
3. **许可证兼容**：不得引入与 PolyForm Noncommercial 1.0.0 冲突的代码或资源。
4. **可锁定**：Rust、SwiftPM、GitHub Actions 和 Python 工具依赖必须能被 lockfile、commit 或 artifact hash 约束。
5. **可替换**：核心业务路径不要绑定无法替换的边缘库。

## 新增依赖要求

PR 中新增依赖时必须说明：

- 依赖名称、版本、来源和许可证。
- 使用位置和为什么不能用现有能力。
- 是否处理用户文件、路径、网络、压缩包、解析器、加密或数据库。
- 供应链风险：维护活跃度、下载源、是否执行 build script、是否引入原生二进制。
- 测试证据和回滚方案。

## Rust

- 依赖必须写入 `Cargo.toml`，版本范围要尽量窄。
- `Cargo.lock` 变更必须随 PR 提交。
- 含 `build.rs`、FFI、压缩/解压、解析外部格式、网络或加密能力的依赖按 High 风险评审。
- 不允许为了测试便利在生产路径引入 mock-only 依赖。

推荐检查：

```bash
cd core && cargo tree
cd core && cargo test --locked --workspace
```

## Swift / macOS

- Swift Package 依赖必须可被 Xcode/SwiftPM 锁定。
- UI-only 依赖不得泄漏到 Core 或 FFI 边界。
- 处理文件系统、iCloud、AppKit 权限、日志、网络或沙盒能力的依赖按 High 风险评审。

## GitHub Actions

- 官方 action 优先，生产 workflow 使用经审阅的完整 40 位 commit SHA，并在行尾记录对应 release。
- 非官方 action 需要说明来源和用途。
- 不在 workflow 中打印 secret、token、用户路径或私有文件内容。

## 许可证

允许：

- MIT
- Apache-2.0
- BSD-2-Clause / BSD-3-Clause
- ISC
- MIT-CMU（仅限来源和许可证文本已登记的 Pillow 等工具依赖）
- OFL-1.1（字体和派生品牌资产仍需合格 reviewer 确认具体分发义务）
- Unicode-DFS-2016

## 品牌工具

品牌导出和校验使用 `Pillow==12.3.0`，来源为 PyPI，许可证登记为 MIT-CMU。它只运行在开发工具和 CI，
负责 PNG 重采样、ICO 封装、品牌总览合成和 CMYK TIFF；不进入 AreaMatrix 应用、Rust Core 或用户文件处理路径。
`scripts/brand/requirements.txt` 锁定该 release 的官方 artifact SHA-256，CI 同时使用
`--only-binary=:all:` 和 `--require-hashes`，避免源码构建与未登记 artifact。macOS 自带 `sips` 和 `iconutil`
负责 SVG 栅格化、PDF 与 ICNS，但不能独立覆盖 ICO、图层合成和 CMYK 校验，因此不作为完整替代。

Inter Bold 字标输入的版本、精确 GitHub blob 坐标、上游 `rsms/inter` 谱系、输入 hash、OFL-1.1 文本和派生轮廓
hash 记录在 `assets/brand/provenance.json`。精确输入对象必须保持固定为
`linagora/tmail-flutter@0e6c107f63e4fd35615605b718963ffa6b2897a4:assets/fonts/Inter/Inter-Bold.ttf`，不得仅凭
上游版本字符串替换来源。该记录提供技术可追溯性，不替代合格许可证 reviewer 对字体使用、归属和分发义务的确认。
`assets/brand/archive/` 的来源与授权证据尚未建立，必须保持 `evidence-blocked` 且排除发布。

版本固定在 `scripts/brand/requirements.txt`。移除品牌自动化时，可同时删除该 requirements 文件、品牌 Python
工具和 Governance CI 的品牌步骤，产品运行时不受影响。

## 外部 AI Runtime

当前产品构建没有获批的外部 AI 可执行 runtime。`AREAMATRIX_AI_*_RUNTIME` 环境变量只在已知 Rust 测试二进制
持有进程内 test-harness capability 时启用；普通 debug 调用和 release build 都必须 fail closed。测试 fixture
manifest 固定绑定 capability、协议版本、绝对可执行路径、平台、SHA-256、`areamatrix-test-fixture` provider、测试
endpoint、`synthetic-test-data-only` 隐私分类、MIT 许可证和仓库定义的测试来源。

未来若要启用产品 runtime，必须先建立独立于 runtime 及其相邻 manifest 的可信批准记录，至少绑定 provider、
endpoint / 数据离机分类、版本、安装根、可执行文件 SHA-256、来源、许可证、SBOM、签名或平台验证证据，并完成
隐私、远程调用和发布包检查。相邻 manifest 不能自我批准，HPND / MIT-CMU 例外也不得从品牌工具扩展到产品
runtime。

需要人工确认：

- MPL-2.0
- LGPL
- 双许可证
- 未声明许可证

默认不接受：

- GPL/AGPL 代码直接链接进产品
- 未授权商业素材、logo、字体或图标
- 无法追溯来源的代码片段

## 升级与移除

- 安全升级优先，必须记录影响范围和验证命令。
- 大版本升级需要说明 breaking change 和回滚方式。
- 移除依赖时确认 lockfile、文档、CI 和脚本不再引用它。

## Related

- [coding-standards.md](coding-standards.md)
- [testing.md](testing.md)
- [ci-governance.md](ci-governance.md)
- [../../CONTRIBUTING.md](../../CONTRIBUTING.md)
- [../../SECURITY.md](../../SECURITY.md)
