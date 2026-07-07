# 发布流程

> 从版本号 bump 到用户拿到签名公证后的 .app/.dmg 的完整步骤。
>
> 阅读时长：约 5 分钟。

---

## 发布频率

| 版本范围 | 节奏 |
|---|---|
| v1 基础闭环 | 不公开发布；历史验证记录见 v1 归档 |
| v2 体验完善 | 月度 / 双月度 minor 版本 |
| 后续版本 | 视情况，至少季度一次 |
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

- [ ] 若需要追溯历史分发判断，先从
      [workflow versions](../../workflow/versions/README.md) 定位对应归档证据；归档清单不作为后续版本发布命名模板。
- [ ] 补证期间可运行 `./dev release status --json --remote` 读取 `release_blockers` 和
      `next_required_evidence`；此时输出 `BLOCKED` 是预期状态。若
      `residual_evidence_gate.status` 为 `BLOCKED`，不得继续创建正式 tag 或用户分发物。
      若 residual 证据门禁已 `PASS` 但仅 `formal_tag_gate` 因正式 tag 缺失而 `BLOCKED`，
      可按本流程的 tag 步骤创建 / 推送正式 tag。最终 GitHub Release 或用户分发前，该命令必须在
      `--remote` 下整体返回 `PASS`。该命令是只读聚合检查，不能创建 tag、不能发布 GitHub
      Release，也不能替代 Developer ID、公证、DMG、干净 Mac 首启或反馈路线的真实证据。
- [ ] 补证文档更新后运行 `./dev release evidence-audit --json`，确认 release evidence record 与
      residual 索引一致。该命令只审计记录结构和 `closes_residual` 对齐，不关闭 residual，
      也不能替代真实外部分发证据。
- [ ] 创建正式 tag 前运行 `./dev release final-tag-readiness-audit --json --remote`。
      只有该命令返回 `PASS`，且 `ready_to_create_formal_tag: true` 时，才允许进入正式
      `v0.1.0` tag 创建步骤。该命令只读，不创建 tag、不推送 tag、不创建 GitHub Release，
      也不关闭 `v1-rl-004`。
- [ ] 核对 iCloud placeholder M-02 smoke record 时运行
      `./dev release icloud-placeholder-smoke-audit --json`。当前 metadata probe、真实 UI retry、
      DB row 或用户文件不变量缺失时，该命令返回 `BLOCKED` 是预期状态。该命令只读，不接收路径、
      不运行 `mdls`、不触发 iCloud 下载、不读取文件内容、不写用户文件、不写 DB、不写
      `.areamatrix/` 元数据，也不能关闭 `v1-rl-002`。
- [ ] 核对 `3-1/task-05` release evidence review 时运行
      `./dev release task05-release-review-audit --json`。当前 fresh formal release evidence review
      未完成时，该命令返回 `BLOCKED` 是预期状态。该命令只读，不读取 `.codex/task-loop-logs/**`、
      不回填 `progress.json`、task-loop logs、run summaries、checkpoint metadata、commit 或 tag，
      也不能关闭 `v1-ref-003-1-task-05`。
- [ ] 核对反馈路线决策时运行 `./dev release alpha-feedback-decision-audit --json`。
      当前缺可信测试者名单来源、正式 announcement / Discussion URL、备用反馈路线、triage owner
      和响应 SLO 时，该命令返回 `BLOCKED` 是预期状态。该命令只读，不创建 Discussion、不邀请
      tester、不发布公告、不分配 owner，也不能关闭 `v1-rl-006`。
- [ ] 采集 iCloud placeholder metadata draft 时使用
      `./dev release icloud-placeholder-evidence --path <path> --json`；默认输出会脱敏本机路径。
      只有私下排障才使用 `--include-sensitive-paths`，且敏感路径输出不得作为可共享 release evidence。
- [ ] 采集已有 app / DMG 产物的只读签名结构 probe 时使用
      `./dev release distribution-artifact-probe --app-path <APP_PATH> --dmg-path <DMG_PATH> --json`；
      默认输出会脱敏本机路径，默认会运行签名验证读取，默认不执行完整 DMG SHA-256 读取。只有需要记录 SHA-256 时才加
      `--hash-dmg`，只有需要本机 Gatekeeper 或 stapled ticket 检查时才加 `--spctl` /
      `--stapler-validate`。该命令不会 mount、staple、submit notarization、安装或写项目元数据；
      `probe.status: captured` 只表示采集成功，`distribution_requirements.status` 仍会在正式证据不足时
      保持 `blocked`，不能替代真实 Developer ID、公证、stapled DMG 或干净 Mac 首启证据。
- [ ] `./dev release preflight` 通过，确认本机存在 Developer ID Application
      signing identity，且 `AC_PASSWORD` notarytool keychain profile 可用；该预检
      只证明发布凭据可用，不能替代最终 codesign、notarytool submit、stapler、DMG
      和干净 Mac 首启证据。
      需要留存机器可读阻断或放行证据时使用 `./dev release preflight --json`；该 JSON
      仍只是凭据预检和补证模板，不是最终分发证据。
- [ ] 若当前未加入付费 Apple Developer Program，则不得继续执行 Developer ID 分发。
- [ ] `main` 分支所有 PR 已合并
- [ ] 全部 CI 绿
- [ ] CHANGELOG `[Unreleased]` 段落内容完整
- [ ] 所有 P0/P1 issues 已关闭或挪到下版
- [ ] 手工冒烟（[testing.md#手工冒烟清单](testing.md)）全过
- [ ] 性能基线无回退
- [ ] 已升级依赖（`cargo update --dry-run` 检查）
- [ ] 文档与代码一致（特别是 docs/api/）

---

## Developer ID / notarization 补证

未加入付费 Apple Developer Program 时，项目不能获取 Developer ID Application 证书，也不能完成
notarytool 公证；这种环境只能做本机工程验证，不能产生用户分发结论。

正式分发前先运行 `./dev release status --json --remote`。当
`residual_evidence_gate.status` 为 `BLOCKED` 时，不得继续创建正式 tag、GitHub Release 或
用户分发物；只能根据 `release_blockers` 和 `next_required_evidence` 补齐真实证据。
当 residual 证据门禁为 `PASS`、但 `formal_tag_gate` 仍因正式 tag 缺失而 `BLOCKED` 时，
表示进入 tag 补证步骤，不表示 residual 已由该命令关闭。输出中的 `closes_residual: false`
表示该命令本身不关闭 residual、不是 release evidence；关闭 residual 仍以真实外部分发证据
为准。正式 tag 推送后必须再次运行 `./dev release status --json --remote`，整体 `status: PASS`
后才允许继续 GitHub Release 或用户分发。

`./dev release evidence-audit --json` 可在每次补证文档更新后运行，用来确认结构化 evidence
record 的 `residual_id`、`mode`、`release_gate` 和 `closes_residual` 与 residual 索引对齐。
若某个 release residual 已被标为 `closed`，该命令还会检查对应关键关闭字段是否已从
`pending` / `blocked` / `null` / `false` 更新为真实通过值。它只证明记录没有自相矛盾，
不证明发布证据真实存在。

`./dev release final-tag-readiness-audit --json --remote` 是正式 tag 前的只读门禁审计。
它会读取 `final-tag-release-evidence.md`、residual 发布阻断、release evidence audit
和本地 / 远端 tag 查询结果；其中 `pre_tag_release_evidence_gate` 会排除 `v1-rl-004` 自身，
只检查其他发布证据是否已允许进入 tag 步骤。当前仍有 iCloud、分发、公证、反馈路线或 release
review 阻断时，`ready_to_create_formal_tag: false` 是正确结果。该命令不会创建 tag、不会推送 tag、
不会发布 GitHub Release，也不能替代正式 tag push 后的最终 `./dev release status --json --remote`。

`./dev release icloud-placeholder-smoke-audit --json` 是 `v1-rl-002` 的只读记录审计。
它会读取 `icloud-placeholder-smoke-evidence.md` 和 residual 索引，核对 M-02 是否已经具备
metadata probe、真实 UI retry、DB row、retry result 和用户文件不变量字段。当前这些真实补证仍缺失时，
`smoke_evidence_gate: BLOCKED` 和退出码 `1` 是正确结果。该命令不接收路径、不运行 `mdls`、
不触发 iCloud 下载、不读取文件内容、不写用户文件、不写 DB、不写项目文件、不写 `.areamatrix/`
元数据，也不能关闭 `v1-rl-002`。

`./dev release task05-release-review-audit --json` 是 `v1-ref-003-1-task-05` 的只读记录审计。
它会读取对应的 v1 release evidence record 和 residual 索引，核对 fresh formal release evidence
review 是否已经真实完成，并同时确认没有把 incomplete task-loop summary、local QA、自述、ad-hoc
signed app 或未公证预览 DMG 当作 task-loop `VERIFY_RESULT: PASS`。当前 review 仍缺
`review_completed: true`、`reviewer` 和 `reviewed_at` 时，`release_evidence_review_gate: BLOCKED`
和退出码 `1` 是正确结果。该命令不读取 `.codex/task-loop-logs/**`、不回填 `progress.json`、
task-loop logs、run summaries、checkpoint metadata、commit 或 tag，也不能关闭
`v1-ref-003-1-task-05`。

`./dev release alpha-feedback-decision-audit --json` 是 `v1-rl-006` 的只读决策审计。
它会读取 `.github/ISSUE_TEMPLATE/alpha_feedback.md`、`.github/ISSUE_TEMPLATE/config.yml`
和对应 evidence record，核对本地反馈入口是否存在，
以及 release owner 是否已记录可信测试者名单来源、正整数数量、tester invitation side effect、
GitHub HTTPS announcement / Discussion URL、主备反馈路线、triage owner 和响应 SLO。当前这些决策仍缺失时，JSON 中
`decision_gate.status: BLOCKED` 和退出码 `1` 是正确结果。该命令不会创建 GitHub Discussion、
邀请 tester、发布公告、分配 owner、写 evidence 或把正式分发标记 ready；`closes_residual: false`
表示它不能关闭 `v1-rl-006`。即使 `decision_gate.status: PASS`，也只表示本地记录字段具备
最低结构质量，不证明外部邀请、公告发布或 owner 接受责任已经真实发生。

`./dev release distribution-artifact-probe --app-path "$APP_PATH" --dmg-path "$DMG_PATH" --json`
是只读产物 probe，用于把已有 `.app` / `.dmg` 的 `lstat`、`codesign -dv` 和
`codesign --verify` 结果结构化。默认输出会脱敏路径和文件名，默认跳过 DMG SHA-256；
`--hash-dmg` 会读取 DMG 字节，`--spctl` 会运行本机 Gatekeeper assessment，
`--stapler-validate` 只运行 `xcrun stapler validate`，不会执行 `stapler staple`。该命令不能替代
`xcrun notarytool submit ... --wait` 的 accepted 记录、stapled app / DMG、正式 checksum、
`spctl` accepted 结果或干净 Mac 首启。JSON 中 `probe.status` 表示采集是否成功，
`distribution_requirements.status` 才表达正式分发要求是否仍被阻断。

本机 `./dev release readiness-build` 只能用于 Release 配置、静态链接和 ad-hoc 签名结构检查。
如果使用 `--install`，必须同时传入 `--install-confirm /Applications/AreaMatrix.app`
或与 `--applications-dir` 对应的完整目标路径；安装到 `/Applications` 仍不构成分发证据。

Developer ID / notarization 后续补证必须至少包含：

- `./dev release preflight` 通过；可同时保存 `./dev release preflight --json` 输出中的
  `checks`、`blocked_by`、`required_distribution_evidence` 和 `evidence_record_template`。
- 可保存 `./dev release distribution-artifact-probe --app-path "$APP_PATH" --dmg-path "$DMG_PATH"
  --json` 输出作为产物结构 probe，但不能用它关闭 `v1-rl-003`。
- `security find-identity -v -p codesigning` 中存在 valid Developer ID Application identity。
- `codesign -dv --verbose=4 "$APP_PATH"` 显示 Developer ID team，而不是 `Signature=adhoc`。
- `xcrun notarytool submit ... --wait` 返回 accepted，并保存 submission id / log URL。
- `xcrun stapler staple "$APP_PATH"` 和 `xcrun stapler validate "$APP_PATH"` 通过。
- DMG 也完成签名、公证、staple / assess，并记录 SHA-256。
- 干净 Mac 上首次打开通过 Gatekeeper，完成 repo 选择或已配置 repo 首屏加载。

v1 曾经保留过受控环境构建与测试者下载证据；这些内容只作为历史 release evidence 查阅，不在当前发布流程中复用命名或命令。

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

打正式 tag 前必须先运行 `./dev release status --json --remote`，并确认
`residual_evidence_gate.status` 为 `PASS`。此时整体 `status` 可能仍因正式 tag 缺失而
`BLOCKED`；这是 tag 步骤本身要关闭的门禁，不得和 residual 证据阻断混淆。

```bash
git tag -a v0.1.0 -m "Release 0.1.0

- v1 基础闭环端到端功能
- 拖拽导入、自动分类、改动追踪
- iCloud 兼容
- 详见 CHANGELOG.md
"

git push origin main v0.1.0
```

当前仓库尚未包含 `.github/workflows/release.yml`；tag push 只发布 Git tag，不会自动构建、签名、公证或上传 GitHub Release 产物。正式 `v0.1.0` 仍按下方手工 release 流程执行，release workflow 是未来自动化项。
tag 推送后必须重新运行 `./dev release status --json --remote`；只有整体 `status: PASS` 时才继续 GitHub Release。

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

> 注：当前默认不开 sandbox，因为 FSEvents + 整库读写在沙盒下很复杂。后续公开分发前重新评估沙盒化。

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

执行 GitHub Release 前必须重新运行 `./dev release status --json --remote`，确认整体
`status: PASS`，并保留 Developer ID、公证、stapled DMG、正式 checksum 和干净 Mac 首启证据。

```bash
gh release create v0.1.0 \
  --title "AreaMatrix 0.1.0" \
  --notes-file release-notes-0.1.0.md \
  AreaMatrix-0.1.0.dmg \
  AreaMatrix.zip
```

`release-notes-0.1.0.md` 来自 CHANGELOG 该版本段落 + 致谢 + 已知问题；历史发布说明从 [workflow versions](../../workflow/versions/README.md) 的归档入口查阅。

---

## 步骤 8：post-release

- [ ] 关闭对应 release checklist item
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

## CI 自动化（后续）

`.github/workflows/release.yml` 当前尚未启用。未来加入后，它可以在 tag push 时：

1. 构建 Rust + Swift
2. 自动签名（需配置 secrets：CERT_BASE64 / KEYCHAIN_PASS）
3. 自动公证（NOTARIZE_PROFILE）
4. 上传 .dmg / .zip 到 GitHub Release
5. 发邮件通知维护者

当前 release 流程全手工；后续按治理审查启用自动化。

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
