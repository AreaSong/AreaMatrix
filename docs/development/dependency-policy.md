# Dependency Policy

> AreaMatrix 的依赖、许可证与供应链规则：默认少依赖、可解释、可锁定、可替换、许可证兼容。
>
> 阅读时长：约 4 分钟。

---

## 原则

1. **少即是稳**：标准库或现有依赖能解决时，不新增依赖。
2. **用途明确**：每个新增依赖都必须说明解决的问题和替代方案。
3. **许可证兼容**：不得引入与 PolyForm Noncommercial 1.0.0 冲突的代码或资源。
4. **可锁定**：Rust、SwiftPM、GitHub Actions 依赖必须能被版本或 lockfile 约束。
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
cd core && cargo test --workspace
```

## Swift / macOS

- Swift Package 依赖必须可被 Xcode/SwiftPM 锁定。
- UI-only 依赖不得泄漏到 Core 或 FFI 边界。
- 处理文件系统、iCloud、AppKit 权限、日志、网络或沙盒能力的依赖按 High 风险评审。

## GitHub Actions

- 官方 action 优先，使用明确 major 版本，例如 `actions/checkout@v4`。
- 非官方 action 需要说明来源和用途。
- 不在 workflow 中打印 secret、token、用户路径或私有文件内容。

## 许可证

允许：

- MIT
- Apache-2.0
- BSD-2-Clause / BSD-3-Clause
- ISC
- Unicode-DFS-2016

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
