# Distribution Signing And Notarization Evidence

> v1 formal distribution 的 Developer ID signing、notarization、stapling、formal DMG 和 clean Mac
> first-launch 证据记录。
>
> 阅读时长：约 5 分钟。

---

## 当前结论

当前结论：**不关闭 `v1-rl-003`**。

`./dev release preflight --json` 已经提供可复现的凭据预检和补证模板；`./dev release
distribution-artifact-probe --app-path <APP_PATH> --dmg-path <DMG_PATH> --json` 已经提供只读产物
probe 入口。前者只证明本机是否具备 Developer ID Application identity 和 notarytool keychain
profile；后者只读取产物元数据和签名验证输出，默认脱敏路径，默认不执行完整 DMG SHA-256 读取。当前已知状态仍是
`BLOCKED`：本机没有 valid Developer ID Application signing identity，`AC_PASSWORD`
notarytool keychain profile 不可用；当前项目也未加入付费 Apple Developer Program。

任何 ad-hoc signed `.app`、local QA DMG、unnotarized preview DMG、同机 AppleScript smoke、
同机 scroll probe 或 release readiness build，都不能替代本文件要求的真实分发证据。

## 证据记录模板

真实补证时，release owner 必须保留 `./dev release preflight --json` 输出，并用下列字段记录
实际命令、产物、日志和干净 Mac 结果。任一字段仍为 `pending` 或 `blocked` 时，release gate
保持阻断。

```yaml
schema_version: 1
mode: distribution_signing_notarization_record
residual_id: v1-rl-003
release: v0.1.0
status: blocked
closes_residual: false
release_gate: block_if_any_pending_or_blocked

preflight_json:
  command: ./dev release preflight --json
  status: BLOCKED
  blocked_by:
    - Developer ID Application identity
    - notarytool keychain profile
  captured_at: "2026-07-06"

artifact_probe:
  status: pending
  probe_status: pending
  distribution_requirements_status: blocked
  mode: distribution_artifact_probe
  command: ./dev release distribution-artifact-probe --app-path "$APP_PATH" --dmg-path "$DMG_PATH" --json
  path_redaction: true
  hash_dmg_default: skipped
  status_semantics: probe.status captured is not a distribution pass
  closes_residual: false
  does_not_prove:
    - Developer ID signed app
    - accepted notarization
    - stapled app or stapled DMG
    - formal v0.1.0 release readiness

developer_id_identity:
  status: blocked
  command: security find-identity -v -p codesigning
  identity: null
  team_id: null

notarytool_profile:
  status: blocked
  profile: AC_PASSWORD
  command: xcrun notarytool history --keychain-profile AC_PASSWORD

codesign_developer_id_team:
  status: pending
  app_path: null
  command: codesign -dv --verbose=4 "$APP_PATH"
  required_signature: Developer ID Application
  team_identifier: null
  rejects:
    - Signature=adhoc
    - TeamIdentifier=not set

notarytool_submission:
  status: pending
  artifact: null
  command: xcrun notarytool submit ... --wait
  submission_id: null
  log_url: null

stapler_app:
  status: pending
  command:
    - xcrun stapler staple "$APP_PATH"
    - xcrun stapler validate "$APP_PATH"

formal_dmg:
  status: pending
  path: null
  sha256: null
  codesign_status: pending
  notarization_status: pending
  notarization_submission_id: null
  notarization_log_url: null

stapler_dmg:
  status: pending
  command:
    - xcrun stapler staple "$DMG_PATH"
    - xcrun stapler validate "$DMG_PATH"

spctl_assess:
  status: pending
  app_command: spctl -a -t exec -vv "$APP_PATH"
  dmg_command: spctl --assess -vvv --type install "$DMG_PATH"
  required_source: Notarized Developer ID

clean_mac_first_launch:
  status: pending
  machine: null
  macos_version: null
  gatekeeper_result: pending
  first_launch_result: pending
  repo_selection_or_configured_repo_result: pending
  evidence_path: null

does_not_prove:
  - Developer ID signed app
  - notarytool accepted submission
  - stapled app or stapled DMG
  - formal notarized DMG checksum
  - clean Mac Gatekeeper first launch
  - formal v0.1.0 release readiness
```

## 使用规则

1. 先运行 `./dev release preflight --json`。如果输出 `status: BLOCKED`，只把结果记录为阻断证据，
   不继续声称分发可用。
2. 有 app / DMG 产物时，可运行 `./dev release distribution-artifact-probe --app-path "$APP_PATH"
   --dmg-path "$DMG_PATH" --json` 采集只读产物 probe。该命令默认只做 `lstat`、`codesign -dv`
   和 `codesign --verify`，默认脱敏路径；`--hash-dmg` 才读取 DMG 字节计算 SHA-256，`--spctl`
   和 `--stapler-validate` 才运行对应系统检查。它不会 mount、staple、submit notarization、安装、
   写 DB 或写 `.areamatrix/`。JSON 中 `probe.status: captured` 只表示采集成功；
   `distribution_requirements.status` 在正式证据不足时仍为 `blocked`，不能关闭本项。
3. 只有付费 Apple Developer Program、Developer ID Application identity 和 notarytool profile
   都可用后，才继续 codesign、notarytool submit、stapler 和 DMG 公证。
4. `codesign -dv --verbose=4 "$APP_PATH"` 必须显示 Developer ID team；`Signature=adhoc` 或
   `TeamIdentifier=not set` 只能证明非正式本机包，不能关闭本项。
5. 公证必须记录 notarytool submission id 和 log URL；只记录命令计划或本机成功构建不算通过。
6. app 和 DMG 都必须 staple / validate；DMG 必须记录正式 SHA-256。
7. 干净 Mac 首启必须记录 Gatekeeper 结果，以及 repo 选择或已配置 repo 首屏加载结果。
8. 只有上述字段全部为真实 `pass` / `accepted`，并且 release checklist 同步更新后，才能把
   `closes_residual` 改为 `true`。

## 当前待补证字段

| 字段 | 当前状态 | 关闭所需证据 |
|---|---|---|
| `preflight_json.status` | `BLOCKED` | `./dev release preflight --json` 返回 `PASS`，且输出随 release evidence 留存。 |
| `artifact_probe.status` | `pending` | 对正式 app / DMG 运行只读 probe；即使 `probe.status: captured`，`distribution_requirements.status` 也必须保持阻断，直到下面的关闭字段真实通过。 |
| `developer_id_identity.status` | `blocked` | `security find-identity -v -p codesigning` 存在 valid Developer ID Application identity。 |
| `notarytool_profile.status` | `blocked` | `xcrun notarytool history --keychain-profile AC_PASSWORD` 可用。 |
| `codesign_developer_id_team.status` | `pending` | `codesign -dv --verbose=4 "$APP_PATH"` 显示 Developer ID team。 |
| `notarytool_submission.status` | `pending` | `xcrun notarytool submit ... --wait` 返回 accepted，并记录 submission id / log URL。 |
| `stapler_app.status` | `pending` | app 的 `staple` 和 `validate` 均通过。 |
| `formal_dmg.sha256` | `pending` | 正式 DMG SHA-256 记录在 release evidence。 |
| `stapler_dmg.status` | `pending` | DMG 的 `staple` 和 `validate` 均通过。 |
| `spctl_assess.status` | `pending` | app / DMG assess 输出 accepted，source 为 Notarized Developer ID。 |
| `clean_mac_first_launch.status` | `pending` | 干净 Mac Gatekeeper 首启和 repo 首屏加载证据齐全。 |

## Related

- [release-checklist.md](release-checklist.md)
- [release.md](../../../../docs/development/release.md)
- [build.md](../../../../docs/development/build.md)
- [v1 release residuals](../residuals/release-evidence.md)
