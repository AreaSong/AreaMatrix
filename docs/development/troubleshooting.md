# 开发排障

> 提供 AreaMatrix 构建、Core、macOS、资料库、watcher、recovery 和 diagnostics 的安全排障入口。
>
> 阅读时长：约 9 分钟。

---

## 排障顺序

1. 记录准确命令、错误和环境。
2. 判断失败属于 build、binding、test、DB、文件系统、watcher、workflow 或发布证据。
3. 先运行最小复现，不先删除缓存、DB 或 staging。
4. 用户文件、DB、migration、recovery、reindex、FSEvents/iCloud 问题先保留 evidence。
5. 修复后重跑原失败命令，再执行匹配风险的完整门禁。

## 仓库状态

```bash
git status --short --branch
git diff --check
git diff --cached --check
./dev workflow doctor
./dev check docs
```

不要用 `git reset --hard`、删除 worktree 或重建历史 progress 来掩盖失败。

## Core 构建

### Cargo 或 target 缺失

```bash
rustc --version
cargo --version
rustup target list --installed
./dev build core
```

macOS universal build需要 `aarch64-apple-darwin` 和 `x86_64-apple-darwin`。安装 target 后重新执行仓库命令，
不要手工复制旧 static library。

### Rust 检查失败

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-features --workspace
```

先定位首个真实编译/断言错误。不要降低 lint、删除测试或把 workspace test 换成窄测试后宣称修复。

## UniFFI 与 bindings

```bash
./dev build core
./dev bindings verify
```

UDL/API 变化后 bindings drift 属于合同问题。修改顺序是 Core API → UDL → Rust → bindings → Swift bridge。
不要手工编辑 `Bridge/Generated` 或 `Bridge/UniFFI` 生成文件。

Xcode 报 module/header/staticlib 缺失时，先重新运行 `./dev build core`，再检查 Xcode target membership 和
Build Settings。

## macOS build/test

```bash
xcodebuild -project apps/macos/AreaMatrix.xcodeproj \
  -scheme AreaMatrix \
  -destination 'platform=macOS,arch=arm64' \
  build CODE_SIGNING_ALLOWED=NO

./dev test macos
```

只有日志明确指向 `testmanagerd` sandbox restriction 时，`./dev test macos` 才允许 hostless fallback。
断言、编译、链接和普通 runtime 错误仍然是失败。

版本号来自 `project.pbxproj` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`，app `Info.plist` 由 Xcode
生成。

## 资料库未初始化

`RepoNotInitialized` 不会自动执行 `init_repo` 或重建 DB。处理方式：

- 新目录：通过明确的初始化流程创建 `.areamatrix/`。
- 已有资料库 metadata 缺失/损坏：进入用户确认的 repair/reindex 路由。
- 不要在未知目录直接创建空 DB 冒充恢复。

删除 `.areamatrix/` 不删除用户文件，但会丢失 DB-only metadata。

## 权限被拒

`PermissionDenied` 需要先确定被阻断的是资料库目录、单个导入来源、系统 Trash、metadata DB 还是平台
picker 授权：

- 资料库不可写：在系统设置中恢复权限，或选择其他资料库位置。
- 单个来源不可读：保留其他批量项状态，修复文件权限后再重试该项。
- Trash 不可用：禁用 Replace/Delete，不提供永久删除替代。
- picker 或 security scope 失效：重新选择文件；用户取消时不得调用 Core 写 API。

权限错误不自动重试，不通过放宽路径校验或绕过确认恢复。

## SQLite busy 或损坏

### Busy/locked

- 退出其他 AreaMatrix、测试和手工 `sqlite3` 写会话。
- Core 已使用 WAL 和 5 秒 busy timeout；持续冲突需定位持锁进程。
- 不要在应用运行时对 DB 执行写命令。

### Corrupt/repair

优先从 UI 触发 diagnostics snapshot 和 repair。Core 可以：

- 复制 `index.db` 及存在的 WAL/SHM 到 `.areamatrix/diagnostics/`。
- 执行 `PRAGMA integrity_check` 和 foreign-key check。
- full rescan 时创建临时 replacement DB，安装失败恢复旧 DB。

schema migration 当前只创建一次性 `.areamatrix/index.db.pre-v2.bak`，没有时间戳轮转、pre-v3 或自动保留
多份。详见 [migration.md](../architecture/migration.md)。

## Staging recovery

使用应用的 startup recovery 路径，不要直接 `rm -rf .areamatrix/staging/*` 或 `DELETE FROM files WHERE
status='staging'`。

`recover_on_startup` 会：

- 安全清理受控 Copy residue。
- 为 Move residue优先恢复原源路径。
- 对源已存在、父目录缺失、不安全路径、未知文件/目录/symlink 返回 warning 并保留。

任何 warning 都需要人工审查 FS 与 DB；不存在公开“清空 staging”按钮或 24h GC。

## FSEvents / UI 未更新

检查：

- 当前资料库是否成功打开并有 cursor。
- 页面是否显示 watcher startup、external-sync failed 或 rescan/reconnect 状态。
- 事件路径是否位于资料库内且不在 `.areamatrix/`。
- 是否命中 InFlight TTL grace。
- 是否出现 dropped/wrapped/RootChanged recovery flag。

恢复：

- startup/cursor 失败：按 UI 重试或进入确认重扫。
- dropped/wrapped：停止 watcher，用户确认后 full rescan。
- RootChanged：重新连接资料库路径。
- watermark 补写失败：保留 pending 事件，重试 external sync；不能手工跳过 cursor。

当前没有 Debug → Show watcher state 或已接入的 OSLog watcher stream。开发验证使用 watcher tests、页面状态和
Core cursor/DB 证据。

## iCloud placeholder

- watcher/Core 不自动下载。
- 用户选择 `Download & retry` 后由 macOS 平台层触发下载。
- 未下载或失败时 cursor 不应错误前进，用户文件和 marker 保持不变。

真实 iCloud 环境证据属于发布 residual，不能由 fixture 或本机模拟关闭。

## 分类与 classifier.yaml

- 文件缺失时使用内嵌默认规则。
- 文件存在但 YAML/字段无效时返回错误，不静默回退。
- 使用 Core rule editor/save API 原子更新；不要让 Swift 直接修改 YAML。
- 保存规则只影响未来分类，不自动移动已有文件。

## 性能

```bash
cargo test --manifest-path core/Cargo.toml \
  --release --bench core_hot_paths -- --ignored --nocapture

./dev test macos --only-testing AreaMatrixTests/AreaMatrixPerfTests
```

Rust benchmark 需要检查每行 `result`；exit 0 不等于阈值全部通过。大树内存问题先用 Instruments 判断扫描、
JSON 构造还是 UI 持有对象；当前没有 TreeCache/LRU 可调。

## Diagnostics

应用内真实入口：

- Repository/Advanced settings：创建 repository metadata snapshot。
- About settings：隐私确认后导出脱敏文本 diagnostics。
- Open logs：只打开已存在的 `.areamatrix/logs/`，当前不保证存在日志 writer。

repository snapshot 可能包含路径、文件名、tags、notes 等敏感 metadata；不要公开上传。About diagnostics
排除用户内容、脱敏路径且不自动上传。

应用无法运行且必须人工保全时，先完全退出应用，再复制 `index.db`、存在的 WAL/SHM 和相关 warning；不要
在原文件上执行写入或修复命令。

## Workflow 与治理

```bash
./dev workflow doctor
./dev workflow discuss --version v2 doctor
./dev check governance
./dev check skills
./dev check prompts
./dev check diff
```

v2 仍是 authoring-only；不要通过排障执行 promotion apply、写 execution 或启动 runner。v1 历史 execution、
progress 和 evidence 保持只读。

## Related

- [build.md](build.md)
- [testing.md](testing.md)
- [observability.md](observability.md)
- [recovery.md](recovery.md)
- [../architecture/migration.md](../architecture/migration.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [../architecture/fs-watcher.md](../architecture/fs-watcher.md)
