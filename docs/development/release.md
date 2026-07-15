# 发布流程

> 定义 AreaMatrix macOS 产品从版本准备、构建、签名、公证到发布后验证的长期流程。
>
> 阅读时长：约 8 分钟。

## 发布类型

| 类型 | 适用范围 | 版本变化 |
|---|---|---|
| 功能发布 | 向后兼容的新能力和体验改进 | MINOR |
| 修复发布 | Bug、性能和兼容性修复 | PATCH |
| 安全发布 | 需要快速分发的安全修复 | PATCH，必要时 MINOR |
| 破坏性发布 | DB、配置或公开 Core API 不兼容变化 | MAJOR，并提供迁移说明 |

发布节奏由产品质量和证据决定，不以固定批次名称或日期替代发布门禁。

## 版本规则

AreaMatrix 使用 SemVer：`MAJOR.MINOR.PATCH`。

- **MAJOR**：DB schema、配置或公开 Core API 存在不兼容变化。
- **MINOR**：向后兼容地增加正式能力。
- **PATCH**：向后兼容的 Bug、性能或安全修复。

版本号需要同步：

- `core/Cargo.toml` 的 `version`。
- macOS target 的 `CFBundleShortVersionString` 和 `CFBundleVersion`。
- [CHANGELOG](../../CHANGELOG.md) 的对应版本段落。

## 发布门禁

发布负责人必须确认：

- [ ] 发布 commit 已固定，工作树没有未审阅改动。
- [ ] Core、macOS、文档、治理、依赖和 secret scan 检查通过。
- [ ] tracked Swift bindings 与 UDL 一致。
- [ ] CHANGELOG、README 和用户指南反映实际产品能力。
- [ ] 数据迁移、文件安全、iCloud、恢复和远程 AI 变更已经完成对应风险验证。
- [ ] 手工冒烟覆盖首次启动、资料库、导入、搜索、整理、设置、恢复和退出重启。
- [ ] 性能基线没有不可接受回退。
- [ ] Developer ID 签名、公证、staple、Gatekeeper 和干净 Mac 首启证据齐全。
- [ ] 安装产物 checksum、发布说明、已知问题和回滚负责人明确。

仓库内的发布状态工具可以聚合或审计证据，但只读检查不能替代真实签名、公证、iCloud 环境、干净 Mac 或外部测试。历史发布记录和未关闭外部条件从 [workflow versions](../../workflow/versions/README.md) 与 [residual ledger](../../workflow/residuals/README.md) 查阅。

发布负责人可以使用以下只读入口检查仓库记录：

```bash
./dev release status --json --remote
./dev release evidence-audit --json
```

`./dev release status` 聚合当前发布条件，`./dev release evidence-audit` 检查记录与索引是否一致。两者都不创建 tag、发布产物、关闭 residual 或完成外部验证；输出为 PASS 也必须继续满足本节的真实发布门禁。

## 1. 准备版本

1. 从受保护的主分支创建发布分支或固定 release commit。
2. 更新版本号和 CHANGELOG。
3. 运行完整验证并保存机器可读结果。
4. 评审用户可见文案、隐私说明、已知问题和迁移说明。
5. 只有所有 tag 前门禁通过后才创建 annotated tag。

示例：

```bash
git tag -a vX.Y.Z -m "Release X.Y.Z"
git push origin vX.Y.Z
```

创建或推送 tag 是外部状态变更，必须由发布负责人明确执行。tag 本身不代表产物已经签名、公证或可分发。

## 2. 构建 Release 应用

```bash
./dev build core --profile release

xcodebuild \
  -project apps/macos/AreaMatrix.xcodeproj \
  -scheme AreaMatrix \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/ \
  build

APP_PATH="build/Build/Products/Release/AreaMatrix.app"
test -d "$APP_PATH"
```

发布构建必须来自已验证 commit。不要使用会删除未提交文件的清理命令准备发布目录；需要隔离时使用新的 worktree 或 CI workspace。

## 3. Developer ID 签名

签名要求 Apple Developer Program、有效的 Developer ID Application identity 和正确 entitlements。

```bash
codesign --deep --force \
  --options runtime \
  --timestamp \
  --sign "Developer ID Application: <NAME> (<TEAM_ID>)" \
  --entitlements apps/macos/AreaMatrix/AreaMatrix.entitlements \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH"
```

验证输出必须显示 Developer ID identity，不能把 ad-hoc signature 当作用户分发证据。

## 4. 公证与 Staple

首次使用时将凭据保存到 Keychain：

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "<APPLE_ID>" \
  --team-id "<TEAM_ID>" \
  --password "<APP_SPECIFIC_PASSWORD>"
```

提交应用：

```bash
ditto -c -k --keepParent "$APP_PATH" AreaMatrix.zip

xcrun notarytool submit AreaMatrix.zip \
  --keychain-profile "AC_PASSWORD" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute -vv "$APP_PATH"
```

保存 notary submission id、accepted 结果和日志位置。失败时读取对应 notary log，修复后重新构建、签名和提交，不能沿用失效证据。

## 5. 制作和验证 DMG

```bash
DMG_PATH="AreaMatrix-X.Y.Z.dmg"

hdiutil create \
  -volname "AreaMatrix" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --sign "Developer ID Application: <NAME> (<TEAM_ID>)" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "AC_PASSWORD" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open -vv "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
```

DMG 必须单独完成签名、公证、staple、Gatekeeper 检查和 checksum，不能复用 `.app` 的结论。

## 6. 干净环境验证

在未安装开发证书、未使用当前构建目录的干净 Mac 上验证：

1. 从计划发布的下载地址获取 DMG，并核对 SHA-256。
2. 挂载 DMG，将 AreaMatrix 拖入 Applications。
3. 首次启动通过 Gatekeeper，无未知开发者或损坏提示。
4. 完成空目录初始化和已有目录接管。
5. 执行代表性导入、搜索、标签、批量操作、Undo/Redo 和重启恢复。
6. 检查用户文件不变量、数据库一致性和诊断脱敏。

同机启动、XCTest、ad-hoc app 或未公证 DMG 不能替代这一步。

## 7. 发布产物

发布说明至少包含：

- 版本与发布日期。
- 面向用户的功能和修复。
- 系统要求与源码或安装方式。
- 数据迁移与兼容性说明。
- 隐私和远程 AI 行为变化。
- 已知问题、恢复建议和 checksum。

使用 GitHub Release 时，上传已经验证的 DMG 和必要的 checksum 文件。创建 Release、公告或测试者邀请属于外部状态变更，由发布负责人执行并留存 URL。

## 8. 发布后观察

- 验证下载、checksum、安装和首次启动路径。
- 监控崩溃、导入失败、数据一致性、iCloud 和 AI provider 错误。
- 对高优先级问题指定 owner、响应时限和用户沟通渠道。
- 将本次发布证据归档到对应版本目录，不复制回长期文档。

## 回滚

发现严重问题时：

1. 停止推广并将有问题的 Release 标记为不可继续下载。
2. 记录受影响版本、症状、数据风险和临时规避方式。
3. 从受保护分支创建修复，运行完整验证。
4. 以新的 patch 版本重新签名、公证和分发。

不要复写已经分发的 tag 或二进制；用户可能已经下载，新的修复必须使用新版本和新 checksum。涉及数据迁移时，必须提供向前修复或明确恢复方案。

## 紧急安全发布

1. 通过 [SECURITY](../../SECURITY.md) 的私密渠道处理漏洞。
2. 限制知情范围并评估受影响版本。
3. 修复、测试并完成正常签名与公证流程。
4. 与报告者协调披露时间。
5. 发布后更新 Security Advisory 和 CHANGELOG。

## Related

- [构建与运行](build.md)
- [Git 工作流](git-workflow.md)
- [测试策略](testing.md)
- [恢复证据](recovery.md)
- [CHANGELOG](../../CHANGELOG.md)
- [安全政策](../../SECURITY.md)
