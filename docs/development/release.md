# 发布流程

> 从版本号 bump 到用户拿到签名公证后的 .app/.dmg 的完整步骤。
>
> 阅读时长：约 5 分钟。

---

## 发布频率

| 阶段 | 节奏 |
|---|---|
| Stage 1 (MVP) | 不公开发布；alpha tester 内部分发 |
| Stage 2 | 月度 / 双月度 minor 版本 |
| Stage 3+ | 视情况，至少季度一次 |
| 安全修复 | 随时发 patch |

---

## 版本规则（Semver）

`MAJOR.MINOR.PATCH`：

- **MAJOR**：DB schema 不兼容 / Core API 不兼容 / 配置 schema 不兼容
- **MINOR**：向后兼容功能增加
- **PATCH**：bug 修复 + 性能 + 安全

详见 [../../CHANGELOG.md](../../CHANGELOG.md)。

---

## 发布前清单

发布人执行：

- [ ] Stage 1 alpha 分发前，先更新并通过
      [stage-1-release-checklist.md](stage-1-release-checklist.md)；若该清单仍有
      P0/P1、check-all 失败、手工冒烟未跑、性能基线缺失或签名/公证状态不明，
      不得放行最终集成验收。
- [ ] `./dev release preflight` 通过，确认本机存在 Developer ID Application
      signing identity，且 `AC_PASSWORD` notarytool keychain profile 可用；该预检
      只证明发布凭据可用，不能替代最终 codesign、notarytool submit、stapler、DMG
      和干净 Mac 首启证据。
- [ ] 若当前未加入付费 Apple Developer Program，则不得继续执行 Developer ID alpha
      分发；只能产出 local QA build，并在 checklist / release notes 中保留 P1-RL-003 blocked。
- [ ] `main` 分支所有 PR 已合并
- [ ] 全部 CI 绿
- [ ] CHANGELOG `[Unreleased]` 段落内容完整
- [ ] 所有 P0/P1 issues 已关闭或挪到下版
- [ ] 手工冒烟（[testing.md#手工冒烟清单](testing.md)）全过
- [ ] 性能基线无回退
- [ ] 已升级依赖（`cargo update --dry-run` 检查）
- [ ] 文档与代码一致（特别是 docs/api/）

---

## 不付费 local QA build

未加入付费 Apple Developer Program 时，项目不能获取 Developer ID Application 证书，也不能完成
notarytool 公证。此时允许制作 **local QA build** 用于本机或受控测试机验证，但它不是正式 alpha
分发物，不能关闭 [stage-1-release-checklist.md](stage-1-release-checklist.md) 中的 P1-RL-003。

local QA build 可使用 Xcode 本地构建、ad-hoc signing 或自签名证书验证包结构和启动行为；测试记录
必须写明以下限制：

- 不是 Developer ID signed app。
- 没有 notarytool accepted log，也没有 stapler 证据。
- DMG 若生成，只能标记为 local QA DMG，不得上传为正式 alpha 分发物。
- 干净 Mac 首启只能证明受控环境行为，不能替代 notarized app 的 Gatekeeper 验证。

恢复正式 alpha 分发的唯一闭环是：加入 Apple Developer Program，取得 Developer ID Application
证书，配置 `AC_PASSWORD` notarytool profile，随后重新执行 `./dev release preflight`、codesign、
notarytool submit、stapler、DMG 公证和干净 Mac 首启验证。

`0.1.0-local-qa` 内部测试构建入口：

```bash
./dev release local-qa --install
```

该命令会用当前本地时间生成 `YYYYMMDDHHMM` 形式的 `CURRENT_PROJECT_VERSION`，执行 Release
构建，保留 ad-hoc / local QA 签名状态，并在 `--install` 时安装到 `/Applications/AreaMatrix.app`。
About 页中的 build number 因此表示该二进制的构建时间，而不是 Xcode 项目里长期写死的版本号。

如需只生成 local QA DMG，可在构建通过后使用：

```bash
APP_PATH="build/Build/Products/Release/AreaMatrix.app"
hdiutil create \
  -volname "AreaMatrix 0.1.0 Local QA" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  AreaMatrix-0.1.0-local-qa.dmg
shasum -a 256 AreaMatrix-0.1.0-local-qa.dmg
```

发布记录必须明确写出 `Signature=adhoc`、`TeamIdentifier=not set`、无 notarytool accepted
log、无 stapler 证据，并保留 P1-RL-003 blocked。local QA 不创建 `v0.1.0` tag，也不创建
GitHub Release。

local QA 首启交互 smoke 可以用来证明受控测试机上 `.app` 能打开、窗口能置前并接收基本输入事件。
该证据必须标记为 **local QA smoke**，不得写成干净 Mac 首启、Gatekeeper 或 notarized app 证据。

```bash
open -n "/Volumes/AreaMatrix 0.1.0 Local QA/AreaMatrix.app"

osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "AreaMatrix"
    set frontmost to true
    set position of window 1 to {60, 50}
    set size of window 1 to {1500, 980}
    get {exists window 1, position of window 1, size of window 1, name of window 1}
  end tell
end tell
APPLESCRIPT

cat > /tmp/areamatrix_scroll_down.swift <<'SWIFT'
import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)
let point = CGPoint(x: 900, y: 610)
CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
    .post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.1)
for _ in 0..<7 {
    CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: -6, wheel2: 0, wheel3: 0)?
        .post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
}
print("scroll_probe=posted events=7 point=900,610")
SWIFT
xcrun swift /tmp/areamatrix_scroll_down.swift
```

Developer ID / notarization 后续补证必须至少包含：

- `./dev release preflight` 通过。
- `security find-identity -v -p codesigning` 中存在 valid Developer ID Application identity。
- `codesign -dv --verbose=4 "$APP_PATH"` 显示 Developer ID team，而不是 `Signature=adhoc`。
- `xcrun notarytool submit ... --wait` 返回 accepted，并保存 submission id / log URL。
- `xcrun stapler staple "$APP_PATH"` 和 `xcrun stapler validate "$APP_PATH"` 通过。
- DMG 也完成签名、公证、staple / assess，并记录 SHA-256。
- 干净 Mac 上首次打开通过 Gatekeeper，完成 repo 选择或已配置 repo 首屏加载。

---

## 步骤 1：bump 版本号

```bash
git checkout main && git pull

# 1. core/Cargo.toml
sed -i '' 's/^version = ".*"/version = "0.1.0"/' core/Cargo.toml

# 2. apps/macos/AreaMatrix/Info.plist
# 用 plutil 或 PlistBuddy 修改：
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.1.0" \
  apps/macos/AreaMatrix/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M)" \
  apps/macos/AreaMatrix/Info.plist

# 3. CHANGELOG.md
# 手动编辑：[Unreleased] → [0.1.0] - 2026-04-28
# 在顶部加新的 [Unreleased] 空段落
```

提交：

```bash
git add -A
git commit -m "chore(release): 0.1.0"
```

---

## 步骤 2：打 Tag

```bash
git tag -a v0.1.0 -m "Release 0.1.0

主要变化：
- MVP 完整端到端功能
- 拖拽导入、自动分类、改动追踪
- iCloud 兼容
- 详见 CHANGELOG.md
"

git push origin main v0.1.0
```

CI 在 tag push 时触发 release workflow（详见 `.github/workflows/release.yml`，未来添加）。

---

## 步骤 3：本地 Release 构建

```bash
# 1. 干净构建
git clean -fdx -e .vscode -e .idea  # 谨慎！会删除未提交文件
./dev build core --profile release

# 2. Xcode Release
xcodebuild -project apps/macos/AreaMatrix.xcodeproj \
  -scheme AreaMatrix \
  -configuration Release \
  -derivedDataPath build/ \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=<TEAM_ID>

APP_PATH="build/Build/Products/Release/AreaMatrix.app"
ls -la "$APP_PATH"  # 验证产出
```

---

## 步骤 4：代码签名

需要 Apple Developer 账号 + Developer ID 证书。

### 准备 entitlements

`apps/macos/AreaMatrix/AreaMatrix.entitlements`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
</dict>
</plist>
```

> 注：MVP 不开 sandbox，因为 FSEvents + 整库读写在沙盒下很复杂。Stage 2+ 重新评估沙盒化。

### 签名

```bash
codesign --deep --force \
  --options runtime \
  --timestamp \
  --sign "Developer ID Application: <YOUR NAME> (<TEAM_ID>)" \
  --entitlements apps/macos/AreaMatrix/AreaMatrix.entitlements \
  "$APP_PATH"

# 验证
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -t exec -vv "$APP_PATH"
```

---

## 步骤 5：公证（Notarize）

### 准备凭据

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "<your-apple-id@example.com>" \
  --team-id "<TEAM_ID>" \
  --password "<app-specific-password>"
```

仅需做一次，存入 keychain。

### 提交公证

```bash
# 1. 打 zip
ditto -c -k --keepParent "$APP_PATH" AreaMatrix.zip

# 2. 提交并等待
xcrun notarytool submit AreaMatrix.zip \
  --keychain-profile "AC_PASSWORD" \
  --wait \
  --timeout 30m

# 3. Stapler
xcrun stapler staple "$APP_PATH"

# 4. 验证
spctl --assess -vvv --type install "$APP_PATH"
# 应输出：accepted, source=Notarized Developer ID
```

公证耗时 5-30 分钟。如失败 → `xcrun notarytool log <id> --keychain-profile "AC_PASSWORD"` 查看详情。

---

## 步骤 6：制作 DMG

```bash
hdiutil create \
  -volname "AreaMatrix" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  AreaMatrix-0.1.0.dmg

# 也对 DMG 签名
codesign --sign "Developer ID Application: <YOUR NAME> (<TEAM_ID>)" \
  AreaMatrix-0.1.0.dmg

# DMG 也要公证
xcrun notarytool submit AreaMatrix-0.1.0.dmg \
  --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple AreaMatrix-0.1.0.dmg
```

---

## 步骤 7：GitHub Release

```bash
gh release create v0.1.0 \
  --title "AreaMatrix 0.1.0" \
  --notes-file release-notes-0.1.0.md \
  AreaMatrix-0.1.0.dmg \
  AreaMatrix.zip
```

`release-notes-0.1.0.md` 来自 CHANGELOG 该版本段落 + 致谢 + 已知问题。

---

## 步骤 8：post-release

- [ ] 关闭对应 milestone
- [ ] 在 Discussions 发 release 公告
- [ ] 更新文档站（如有）
- [ ] 更新顶层 README 中的 status badge / 版本徽标
- [ ] 在 Memory（团队知识库）记录本次 release 的踩坑

---

## 回滚流程

如发布后发现严重问题：

```bash
# 1. 在 GitHub Release 标记为 "Pre-release" 或 "Draft"，让用户停下载
# 2. 推紧急 patch 版本

git checkout main
git checkout -b fix/critical-rollback-issue
# ...修复...
git push -u origin fix/critical-rollback-issue
gh pr create --base main

# 3. 合并后立即发 patch
git checkout main && git pull
# 重复 release 流程，版本号 0.1.1
```

不要删除已发布的 Release（用户可能已下载，删除会让 link 失效）。

---

## CI 自动化（Stage 2 起）

`.github/workflows/release.yml`（待加）会在 tag push 时：

1. 构建 Rust + Swift
2. 自动签名（需配置 secrets：CERT_BASE64 / KEYCHAIN_PASS）
3. 自动公证（NOTARIZE_PROFILE）
4. 上传 .dmg / .zip 到 GitHub Release
5. 发邮件通知维护者

MVP 阶段全手工，Stage 2+ 自动化。

---

## 紧急安全发布

发现高危安全漏洞时：

1. **不公开 issue**：在 GitHub Security Advisory 私下处理
2. **创建 fix 分支**：从 main 切，名 `fix/sec-<id>`
3. **修复 + 测试**：CI 必须绿
4. **协调披露**：与报告者商定披露时间
5. **发布**：走正常 release 流程，CHANGELOG 中标 `### Security`
6. **公开披露**：发布后立即在 Advisory 中公开

详见 [../../SECURITY.md](../../SECURITY.md)。

---

## Related

- [build.md](build.md)
- [git-workflow.md](git-workflow.md)
- [testing.md](testing.md)
- [../../CHANGELOG.md](../../CHANGELOG.md)
- [../../SECURITY.md](../../SECURITY.md)
