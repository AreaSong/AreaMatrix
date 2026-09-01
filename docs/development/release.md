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
- [ ] 精确发布制品已生成 artifact-specific SBOM、THIRD_PARTY_NOTICES、source offer 和 release manifest。
- [ ] 合格外部 reviewer 已对许可证、归属和 source offer 完成与该制品及 `release-manifest.json` SHA-256 绑定的复核。
- [ ] 安装产物 checksum、发布说明、已知问题和回滚负责人明确。

仓库内的发布状态工具可以聚合或审计证据，但只读检查不能替代真实签名、公证、iCloud 环境、干净 Mac 或外部测试。历史发布记录和未关闭外部条件从 [workflow versions](../../workflow/versions/README.md) 与 [residual ledger](../../workflow/residuals/README.md) 查阅。

仓库还提供手动触发的 `Release Evidence Preflight` workflow。它只运行
`./dev release preflight`、`./dev release evidence-audit` 和 `./dev release status`，上传脱敏后的机器可读快照，
并在任一门禁未通过时保持 workflow 失败。该 workflow 不创建 tag、GitHub Release、签名产物或公告；它的作用是
让签名、公证、iCloud、clean Mac 和发布决策的缺口在远端持续可见，不能把预检快照当成正式分发证据。

`Release Supply-Chain Gate` workflow 接收精确的 release ID、HTTPS artifact URL、文件名和预期 SHA-256，随后
生成 CycloneDX 1.5 `sbom.cdx.json`、artifact-specific `THIRD_PARTY_NOTICES.md`、`source-offer.json` 和
`release-manifest.json`。manifest 绑定制品 hash、当前 checkout 的 `cargo metadata --locked --filter-platform`
结果、材料 hash、`Cargo.lock` 及品牌 provenance。Windows target 还必须从仓库内
`packages.lock.json` 纳入完整 NuGet 组件、直接/传递关系、TFM/RID 和 `contentHash` 对应的 SHA-512；锁文件
不包含许可证表达式的包写为 `NOASSERTION`，必须由远端 package metadata 与合格许可证 reviewer 补齐，不能把
hash 锁定误当成许可证批准。生成步骤始终记录 `legalReviewComplete: false`，不能自行批准分发。

当 `--cargo-target` 包含受支持的 Windows 或 Linux target 时，生成器会在创建输出目录前检查对应
`native-core.manifest.json`。manifest 必须为 `approved`，绑定当前 checkout commit、非占位构建命令、仓库
`LICENSE`、实际存在的 SBOM，以及目标 RID 下真实 DLL / `.so` 的 SHA-256；缺少制品、hash 漂移或仍为
`blocked-external-artifact` / `fixture-only` 时直接失败。该门禁防止占位客户端进入发布材料，但不替代平台代码
签名、最终 package inspection、独立许可证复核或真实 Windows/Linux runner 证据。

该 workflow 使用受保护的 `release-legal-review` environment，并从其中读取外部复核记录。复核记录必须是
`approved`，scope 精确等于 `licenses`、`notices`、`source-offer`，匹配 release、制品 SHA-256 与
`release-manifest.json` SHA-256，并包含 reviewer、不早于 manifest `generatedAt` 的 `reviewedAt` 和 HTTPS
evidence URL。缺少复核、仍为 pending、hash/scope 不匹配、材料或品牌 provenance 漂移时必须失败。

manifest 的 `generatedAt` 在该 workflow 中固定为 checkout commit 时间，使同一 commit、制品和输入可以确定性
重建。第一次运行可生成并上传待复核材料但保持失败；外部 reviewer 完成复核并更新 environment secret 后，应
重跑原 workflow run，避免主分支推进后产生另一份 manifest。review record 的最小结构如下：

```json
{
  "status": "approved",
  "release": "vX.Y.Z",
  "artifactSha256": "<64 lowercase hex>",
  "manifestSha256": "<release-manifest.json SHA-256>",
  "scope": ["licenses", "notices", "source-offer"],
  "reviewer": "<qualified reviewer identity>",
  "reviewedAt": "2026-08-21T00:00:00Z",
  "evidenceUrl": "https://example.invalid/reviews/<record>"
}
```

下载使用 1 GiB 暂定操作上限并在下载后重新检查实际文件大小；该数值不是产品制品大小规范。仓库内只能证明
workflow 引用了 `release-legal-review` 且仅允许 `main` ref，不能证明远端 environment reviewer、branch/tag
protection 或 secret 配置真实存在；缺少远端 settings readback 时该项保持 BLOCKED。

生成材料不是实际 package inspection。Cargo 清单来自当前 checkout，而不是制品内容扫描，因此不能证明制品由
记录 commit 构建、没有额外组件、未打包 `assets/brand/archive/`、已经签名/公证，或 source offer 与许可证判断
充分。environment 批准、最终 package inspection、artifact-to-commit provenance、法律判断、签名和公证仍由
对应负责人完成；workflow 成功只证明仓库定义的材料 hash 与外部 review record 技术绑定成立。

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
