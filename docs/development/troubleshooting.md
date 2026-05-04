# Troubleshooting 常见问题排查

> 30+ 常见构建 / 运行 / 部署问题的诊断步骤。每条按"症状 → 可能原因 → 检查步骤 → 解决方案"组织。
>
> 阅读时长：约 18 分钟。

---

## 速查目录

- [构建相关](#构建相关) — UniFFI / Cargo / Xcode
- [签名与公证](#签名与公证) — codesign / notarytool
- [运行时](#运行时) — FSEvents / 权限 / iCloud
- [数据库](#数据库) — SQLite 锁 / 损坏 / 迁移
- [Staging / 事务](#staging--事务) — staging 残留 / 崩溃恢复
- [性能](#性能问题) — 慢操作 / 内存爆 / 启动慢
- [测试](#测试相关) — 单测失败 / CI 失败

---

## 构建相关

### B1. uniffi-bindgen 找不到

**症状**：

```text
error: failed to run custom build command for `core`
  process didn't exit successfully: ... uniffi-bindgen ...
  No such file or directory (os error 2)
```

**可能原因**：

- `uniffi-bindgen` 二进制未安装
- PATH 中无 cargo bin 目录

**检查**：

```bash
which uniffi-bindgen
echo $PATH | tr ':' '\n' | grep cargo
```

**解决**：

```bash
cargo install uniffi-bindgen --version 0.28
export PATH="$HOME/.cargo/bin:$PATH"
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.zshrc
```

---

### B2. UniFFI 版本不一致

**症状**：

```text
error: uniffi 0.28.0 vs uniffi-bindgen 0.27.0 mismatch
```

**检查**：

```bash
cargo tree -p uniffi
uniffi-bindgen --version
```

**解决**：在 `Cargo.toml` 锁定版本，重装 cli。

```toml
[dependencies]
uniffi = { version = "=0.28.0", features = ["cli"] }
```

```bash
cargo install --force uniffi-bindgen --version 0.28.0
```

---

### B3. Xcode link error: undefined symbol _ffi_

**症状**：

```text
Undefined symbols for architecture arm64:
  "_ffi_call_int", referenced from: ...
ld: symbol(s) not found for architecture arm64
```

**可能原因**：

- libffi 未链接
- Rust XCFramework 未生成或未导入到 Xcode 工程
- Build Phase 顺序错误

**检查**：

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj -showBuildSettings | grep -i framework
ls apps/macos/AreaMatrix/Frameworks/
otool -L apps/macos/AreaMatrix/Frameworks/AreaMatrixCore.framework/AreaMatrixCore
```

**解决**：

1. 重新生成 Core 静态库与 Swift bindings：`./dev build core`
2. 在 Xcode → Build Phases → Link Binary With Libraries 添加 `AreaMatrixCore.xcframework`
3. 在 Build Phases → Embed Frameworks 也加入
4. Clean Build Folder（⇧⌘K）后重试

---

### B4. cargo build 报 sqlite 链接错误

**症状**：

```text
error: linking with `cc` failed: exit status: 1
  ld: library not found for -lsqlite3
```

**检查**：

```bash
xcrun --show-sdk-path
ls $(xcrun --show-sdk-path)/usr/lib/libsqlite3*
```

**解决**：

确保 `rusqlite` 用 bundled 模式（避免依赖系统 sqlite）：

```toml
[dependencies]
rusqlite = { version = "0.31", features = ["bundled"] }
```

---

### B5. Rust 交叉编译 aarch64-apple-darwin 失败

**症状**：

```text
error: target may not be installed: aarch64-apple-darwin
```

**解决**：

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

XCFramework 构建脚本：

```bash
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
lipo -create \
  target/aarch64-apple-darwin/release/libarea_matrix.a \
  target/x86_64-apple-darwin/release/libarea_matrix.a \
  -output target/universal/libarea_matrix.a
```

---

### B6. UDL 修改后 Swift 端不生效

**症状**：修改了 `area_matrix.udl`，但 Xcode 中调 API 还是旧的。

**检查**：

```bash
ls apps/macos/AreaMatrix/Generated/
cat apps/macos/AreaMatrix/Generated/area_matrix.swift | head -30
```

**解决**：

```bash
./dev bindings update --udl core/area_matrix.udl --out-dir apps/macos/AreaMatrix/Bridge/Generated
```

确保 build script（`core/build.rs`）在 udl 改动时触发：

```rust
fn main() {
    println!("cargo:rerun-if-changed=src/area_matrix.udl");
    uniffi::generate_scaffolding("src/area_matrix.udl").unwrap();
}
```

---

### B7. Cargo workspace 子 crate 找不到

**症状**：

```text
error: no matching package named `area-matrix-core` found
```

**检查 `Cargo.toml`**：

```toml
[workspace]
members = ["core", "cli"]
resolver = "2"
```

**解决**：从 workspace 根运行命令；如果 IDE rust-analyzer 报错，重启它（Cmd+Shift+P → Rust Analyzer: Restart server）。

---

## 签名与公证

### S1. App 启动报"无法验证开发者"

**症状**：用户双击 .app 弹"无法验证开发者，请勿打开"。

**可能原因**：

- 未签名
- 用了 Adhoc 签名
- 公证失败但已发布

**检查**：

```bash
codesign -dvvv /Applications/AreaMatrix.app 2>&1 | head -20
spctl --assess --verbose /Applications/AreaMatrix.app
```

**解决**：

1. 用 Developer ID 证书重签：

```bash
codesign --force --sign "Developer ID Application: Your Name (TEAMID)" \
  --options runtime --timestamp --deep \
  /path/to/AreaMatrix.app
```

2. 公证：

```bash
xcrun notarytool submit AreaMatrix.zip \
  --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PWD --wait
xcrun stapler staple /path/to/AreaMatrix.app
```

详见 `docs/development/release.md`。

---

### S2. notarytool: "The signature of the binary is invalid."

**可能原因**：

- 签名后又修改了二进制（代码签名失效）
- 缺少 hardened runtime
- 内嵌的二进制（如 sqlite）未签名

**检查**：

```bash
codesign --verify --deep --verbose=2 /path/to/AreaMatrix.app
```

**解决**：

按依赖顺序逐个签名：先内嵌 framework，再 helper tools，最后 app：

```bash
find /path/to/AreaMatrix.app/Contents/Frameworks -type f -perm +111 \
  -exec codesign --force --sign "Developer ID..." --options runtime {} \;
codesign --force --sign "Developer ID..." --options runtime /path/to/AreaMatrix.app
```

---

### S3. notarytool: "The executable does not have the hardened runtime enabled."

**解决**：

- 在 Xcode → Signing & Capabilities → 勾 "Hardened Runtime"
- 或命令行加 `--options runtime`

如果应用需要 JIT / library validation 例外，配 `Entitlements.plist`：

```xml
<key>com.apple.security.cs.disable-library-validation</key>
<true/>
```

---

## 运行时

### R1. FSEvents 不工作 / UI 不更新

**症状**：在 Finder 改资料库文件，应用没反应。

**可能原因**：

- 应用没有「完整磁盘访问」权限
- watcher 未正确启动
- 资料库路径监听失败

**检查**：

```bash
log stream --predicate 'process == "AreaMatrix"' --info | grep -i fsevent
```

应用内 Debug 菜单 → "Show watcher state"：应显示 `Running, sinceEventId=<n>`。

**解决**：

1. 系统设置 → 隐私与安全性 → 完整磁盘访问 → 加入 AreaMatrix
2. 重启应用
3. 如果资料库在外接硬盘，确保该卷支持 FSEvents（exFAT 不支持，APFS / HFS+ 支持）

---

### R2. 应用启动后 CPU 100% 不下来

**可能原因**：

- 启动 reconcile 大库
- watcher 处理事件队列被卡

**检查**：

```bash
sample $(pgrep AreaMatrix) 5 -file /tmp/sample.txt
open /tmp/sample.txt
```

**解决**：

- 用 Instruments → Time Profiler 找热路径
- 详见 [performance.md](performance.md)

---

### R3. 拖入文件后应用没反应

**可能原因**：

- DropZone 未正确接收 NSDragOperation
- import 在主线程被阻塞
- 文件过大（hash 慢）

**检查 Console.app**：filter "AreaMatrix"。

**解决**：

- 确保 import_file 在 `Task.detached` 中调用
- 加进度条，文件 > 100MB 时显示

---

### R4. iCloud 文件无法导入

**症状**：

```text
CoreError.ICloudPlaceholder { path: "..." }
```

**检查**：

```bash
ls -la@ ~/AreaMatrix/docs/contract.pdf
mdls -name kMDItemUbiquitousItemDownloadingStatus ~/AreaMatrix/docs/contract.pdf
```

**解决**：

应用内自动重试逻辑见 [error-codes.md#icloudplaceholder](../api/error-codes.md)。手动触发下载：

```bash
brctl download ~/AreaMatrix/docs/contract.pdf
```

---

### R5. 资料库放在外接硬盘弹出后崩溃

**预期行为**：watcher 应正确处理 RootChanged 事件，弹出友好提示而非崩溃。

**检查 logs**：

```bash
log show --predicate 'process == "AreaMatrix" and category == "watcher"' --last 5m
```

**解决**：

- 重启应用（不会丢数据，因为 staging GC 在启动跑）
- 修复 watcher RootChanged 处理：见 [fs-watcher.md](../architecture/fs-watcher.md) 的 `onRootChanged`

---

### R6. 写权限被拒

**症状**：

```text
CoreError.PermissionDenied { path: "..." }
```

**可能原因**：

- 资料库目录用户不可写
- 应用 sandbox 限制
- macOS TCC 阻挡

**检查**：

```bash
ls -ld ~/AreaMatrix
ls -lae ~/AreaMatrix/docs   # 显示 ACL
```

**解决**：

```bash
chmod -R u+w ~/AreaMatrix
chflags -R nouchg ~/AreaMatrix
xattr -dr com.apple.quarantine ~/AreaMatrix
```

---

## 数据库

### D1. SQLITE_BUSY: database is locked

**症状**：

```text
CoreError.Db("database is locked")
```

**可能原因**：

- 多线程同时写
- WAL checkpoint 卡住
- 其他进程持有锁（如 SQLite Browser）

**检查**：

```bash
fuser ~/AreaMatrix/.areamatrix/index.db   # Linux only
lsof ~/AreaMatrix/.areamatrix/index.db
```

**解决**：

- 关闭外部 SQLite 工具
- 确认 `busy_timeout = 5000` 已设
- 单进程写：所有 import 走同一 actor

---

### D2. 启动时 schema_version 检查失败

**症状**：

```text
CoreError.Db("no such table: schema_version")
```

**可能原因**：DB 文件存在但 schema 没初始化（创建中断）。

**解决**：

```bash
mv ~/AreaMatrix/.areamatrix/index.db ~/AreaMatrix/.areamatrix/index.db.broken
```

应用启动会自动 init_repo + 重建。如果用户在意 change_log，从 `index.db.broken` 用 SQLite 工具导出。

---

### D3. PRAGMA integrity_check 报错

**症状**：启动 self-check 报 page 损坏。

**检查**：

```bash
sqlite3 ~/AreaMatrix/.areamatrix/index.db "PRAGMA integrity_check;"
```

**解决**：

1. 用 `.dump` 导出 SQL 再导入新库：

```bash
sqlite3 index.db.broken .dump > dump.sql
sqlite3 index.db.new < dump.sql
```

2. 如导出失败，从备份恢复：

```bash
cp ~/AreaMatrix/.areamatrix/index.db.bak.<timestamp> ~/AreaMatrix/.areamatrix/index.db
```

3. 兜底：「从文件系统重新索引」（丢 change_log）。

---

### D4. WAL 文件巨大

**症状**：`index.db-wal` > 1GB。

**可能原因**：长时间 reader 阻止 checkpoint。

**检查**：

```bash
ls -lh ~/AreaMatrix/.areamatrix/index.db*
```

**解决**：

```sql
PRAGMA wal_checkpoint(TRUNCATE);
```

应用内每次大写后调用 `truncate` checkpoint 模式。

---

### D5. Migration 执行到一半失败

**症状**：`index.db.pre-v3.bak` 存在但应用继续报 schema 错误。

**解决**：

```bash
mv ~/AreaMatrix/.areamatrix/index.db ~/AreaMatrix/.areamatrix/index.db.failed
mv ~/AreaMatrix/.areamatrix/index.db.pre-v3.bak ~/AreaMatrix/.areamatrix/index.db
```

详见 [migration.md](../architecture/migration.md)。

---

### D6. JOIN 查询变慢

**症状**：`list_changes` 耗时从 5ms 变 200ms。

**检查 EXPLAIN**：

```bash
sqlite3 index.db "EXPLAIN QUERY PLAN SELECT ... FROM change_log cl LEFT JOIN files f ON f.id=cl.file_id WHERE ..."
```

**解决**：

- 重跑 `ANALYZE`：`sqlite3 index.db "ANALYZE;"`
- 检查是否走了正确的索引（[data-model.md](../architecture/data-model.md)）

---

## Staging / 事务

### T1. .areamatrix/staging 目录占空间巨大

**症状**：

```bash
du -sh ~/AreaMatrix/.areamatrix/staging
# 5.2G
```

**可能原因**：

- import 异常退出后 GC 未运行
- 大批量 import 中断

**检查**：

```bash
ls -lt ~/AreaMatrix/.areamatrix/staging | head
sqlite3 ~/AreaMatrix/.areamatrix/index.db "SELECT id, path FROM files WHERE status = 'staging';"
```

**解决**：

应用内：设置 → 维护 → 清理 staging。

命令行兜底：

```bash
sqlite3 ~/AreaMatrix/.areamatrix/index.db "DELETE FROM files WHERE status = 'staging';"
rm -f ~/AreaMatrix/.areamatrix/staging/*
```

---

### T2. 应用崩溃后启动很慢

**可能原因**：staging 中残留大量文件，recover_on_startup 逐个清理。

**检查**：

```bash
ls ~/AreaMatrix/.areamatrix/staging | wc -l
```

> 100 时手动清理（同 T1）。

---

### T3. import 完成但文件没出现在 UI

**可能原因**：

- 事务 COMMIT 失败但 UI 未感知
- watcher 未触发刷新
- list_files 缓存陈旧

**检查**：

```bash
sqlite3 ~/AreaMatrix/.areamatrix/index.db \
  "SELECT id, path, status FROM files ORDER BY id DESC LIMIT 5;"
```

**解决**：

- 应用内 ⌘R 刷新
- 重启应用
- 如果 DB 中 status=staging：触发 recover_on_startup

---

## 性能问题

### P1. 启动 > 5 秒

**可能原因**：

- reindex_from_filesystem 在大库上跑
- migration 执行
- staging GC 大量文件

**诊断**：

```bash
log show --predicate 'process == "AreaMatrix"' --last 1m | grep -E "(startup|reindex|migration|recover)"
```

**优化**：

- 启动只跑 `recover_on_startup`，reindex 后台延后
- 详见 [performance.md](performance.md)

---

### P2. 拖入大文件 UI 卡死

**可能原因**：hash 在主线程执行。

**检查**：Instruments → Main Thread Stalls。

**解决**：

确保 `import_file` 用 `Task.detached`，不在 `@MainActor` 调用：

```swift
let entry = try await Task.detached(priority: .userInitiated) {
    try AreaMatrix.importFile(...)
}.value
```

---

### P3. 内存 > 1GB

**可能原因**：

- `mmap_size` 配高 + 大库
- TreeNode 缓存大对象
- change_log 全量加载

**诊断**：Instruments → Allocations → 看 sticky bytes。

**解决**：

- 调小 `PRAGMA mmap_size`
- TreeCache 加 LRU 限制
- list_changes 限 limit ≤ 1000

---

### P4. SQL 查询慢

**诊断**：

```bash
sqlite3 index.db
.timer on
SELECT ...;
```

**解决**：见 [data-model.md](../architecture/data-model.md) 的 EXPLAIN 章节，确认走索引。

---

## 测试相关

### T-1. 单测在 CI 失败但本地通过

**可能原因**：

- 时间相关（chrono::Local 时区差异）
- 文件系统大小写敏感（macOS 默认大小写不敏感，Linux 敏感）
- 临时目录权限差异

**检查 CI logs** → 寻找具体 panic 行号。

**解决**：

- 时间：测试用固定时间戳 mock
- 文件名大小写：测试不依赖
- 路径：用 `tempfile::tempdir()` 而非硬编码

---

### T-2. UniFFI 集成测试卡死

**可能原因**：UniFFI 异步 callback 未实现 Send + Sync。

**检查**：

```bash
cargo test --test ffi_integration -- --nocapture --test-threads=1
```

**解决**：

```rust
struct MyCallback;
unsafe impl Send for MyCallback {}
unsafe impl Sync for MyCallback {}
```

详见 [uniffi-recipes.md](../api/uniffi-recipes.md) 的 callback 章节。

---

### T-3. SwiftUI snapshot 测试失败

**可能原因**：macOS 版本不同导致字体渲染像素差异。

**解决**：

- 容差设到 0.95+
- 或固定 macOS runner 版本

---

## 部署相关

### DP1. DMG 安装后无法启动

**症状**：双击 .app 闪退。

**检查 Console.app** → Crash Reports → AreaMatrix。

**可能原因**：

- 缺少 Frameworks 内嵌
- arch 不匹配（用户 Intel Mac 装了 arm64-only 包）

**解决**：

- 构建 universal binary（lipo）
- 确认 Embed Frameworks phase 配了

---

### DP2. 自动更新失败

**症状**：Sparkle 检测不到新版。

**检查**：

```bash
defaults read com.areamatrix.app SUFeedURL
```

**解决**：

- 确认 appcast.xml 可访问
- 确认 `SUEnableAutomaticChecks = YES`
- 详见 release.md

---

## 收集诊断信息

应用内：菜单 → Help → "导出诊断包"。

或命令行：

```bash
mkdir -p /tmp/am-diag
cp ~/AreaMatrix/.areamatrix/index.db /tmp/am-diag/
log show --predicate 'process == "AreaMatrix"' --last 1h --info > /tmp/am-diag/log.txt
sqlite3 ~/AreaMatrix/.areamatrix/index.db "PRAGMA integrity_check;" > /tmp/am-diag/integrity.txt
sqlite3 ~/AreaMatrix/.areamatrix/index.db "SELECT version FROM schema_version;" > /tmp/am-diag/schema_version.txt
ls -la ~/AreaMatrix/.areamatrix/staging > /tmp/am-diag/staging.txt
zip -r am-diag.zip /tmp/am-diag/
```

提交到 issue 时附上 zip。

---

## 求助前的自检清单

```text
[ ] 已重启应用
[ ] 已重启 macOS
[ ] AreaMatrix 版本：____
[ ] macOS 版本：____
[ ] CPU 架构（Intel/Apple Silicon）：____
[ ] 资料库位置（本地/外接/iCloud/NAS）：____
[ ] 资料库大小（文件数）：____
[ ] 复现步骤：____
[ ] 期望行为：____
[ ] 实际行为：____
[ ] 已收集诊断包（am-diag.zip）：____
```

---

## Related

- [../api/error-codes.md](../api/error-codes.md)
- [observability.md](observability.md)
- [performance.md](performance.md)
- [../architecture/migration.md](../architecture/migration.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
- [release.md](release.md)
