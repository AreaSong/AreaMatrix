# iCloud Placeholder Smoke Evidence

> v1 `M-02` 真实 iCloud placeholder 下载与重试手工冒烟证据记录。
>
> 阅读时长：约 5 分钟。

---

## 当前结论

当前结论：**不关闭 `v1-rl-002`**。

`./dev release icloud-placeholder-evidence --path <path> --json` 已经能生成只读 metadata draft，
但它只执行 `lstat` 和 `mdls` metadata 读取。它不触发 iCloud 下载，不读取文件内容，不写用户文件，
不写 DB，也不写 `.areamatrix/` 元数据。helper 默认脱敏 `target.input_path`、
`target.absolute_path`、`icloud_metadata.command` 和 `kMDItemFSName`；只有私下排障时才使用
`--include-sensitive-paths` 输出原始本机路径。

当前没有真实 iCloud placeholder 环境可用，`M-02` 仍为 `blocked`。任何合成 `.icloud` marker、
local QA 同机测试、metadata-only probe、非 iCloud Drive 路径或自动化测试，都不能替代真实
`Download & retry` 手工冒烟。

`./dev release icloud-placeholder-smoke-audit --json` 只审计本文的结构化记录是否已经具备真实
M-02 补证字段；当前 `smoke_evidence_gate: BLOCKED` 是预期发布阻断。它不接收文件路径、不运行
`mdls`、不触发 iCloud 下载、不读取文件内容、不写用户文件、不写 DB、不写 `.areamatrix/` 元数据，
也不关闭 `v1-rl-002`。

## 证据记录模板

真实补证时，release owner 必须先保存 helper 输出，再记录 UI 下载、retry、DB row 和用户文件
不变量。任一字段仍为 `pending`、`blocked` 或 `fail` 时，release gate 保持阻断。

```yaml
schema_version: 1
mode: icloud_placeholder_smoke_record
residual_id: v1-rl-002
manual_evidence_id: M-02
status: blocked
closes_residual: false
release_gate: blocked_until_real_icloud_download_retry_and_db_evidence_pass

smoke_audit:
  command: ./dev release icloud-placeholder-smoke-audit --json
  status: BLOCKED
  smoke_evidence_gate: BLOCKED
  closes_residual: false
  audit_side_effects:
    icloud_download_attempted: false
    file_content_read_attempted: false
    file_write_attempted: false
    db_write_attempted: false
    project_write_attempted: false
    areamatrix_metadata_write_attempted: false
    network_attempted: false

metadata_probe:
  command: ./dev release icloud-placeholder-evidence --path <path> --json
  status: pending
  mode: icloud_placeholder_metadata_probe
  closes_residual: false
  privacy:
    path_redaction: true
    raw_path_fields_present: false
  side_effects:
    download_attempted: false
    file_content_read_attempted: false
    file_write_attempted: false
    db_write_attempted: false
    project_write_attempted: false
    areamatrix_metadata_write_attempted: false

environment:
  macos_version: null
  icloud_drive: blocked
  icloud_account: pending
  app_build: null
  repo_path: null
  source_path: null

placeholder_before:
  path: null
  mdls_downloading_status: pending
  mdls_is_downloaded: pending
  finder_or_screenshot_ref: null

ui_retry:
  status: pending
  action: Download & retry
  app_surface: single_file_import | folder_import | conflict_list
  result: pending
  error_if_failed: null

placeholder_after:
  mdls_downloading_status: pending
  mdls_is_downloaded: pending
  downloaded_file_observed: pending

repo_and_db_evidence:
  repo_file_state: pending
  db_row_query: null
  db_row_result: pending
  retry_import_or_conflict_result: pending

user_file_invariants:
  placeholder_marker_not_silently_deleted: pending
  original_file_not_deleted: pending
  conflicted_copy_not_auto_merged: pending
  no_unrequested_overwrite: pending
  no_readme_or_areamatrix_overwrite: pending

evidence_paths:
  - <mdls output, screenshot, DB query output, checksum output, or diagnostics path>

does_not_prove:
  - Download & retry succeeded
  - DB rows match the retried import or conflict flow
  - user files, conflicted copies, or placeholder markers were preserved after retry
  - v1-rl-002 is closed
  - formal alpha release readiness
```

## 使用规则

1. 只读 helper 输出可以作为 `metadata_probe`，但不能独立关闭 `v1-rl-002`。
   默认 helper 输出应保持路径脱敏；敏感路径输出仅限本机私下排障，不进入可共享 evidence。
2. 真实补证必须发生在 iCloud Drive 中，且测试文件在执行前确认为未下载 placeholder。
3. 手工操作必须通过 App UI 的 `Download & retry` 触发；不得用 Finder 预先手动下载来替代 UI 路径。
4. 补证必须同时记录 retry 前后的 `mdls` 状态、UI 结果、repo 文件状态和 DB row。
5. 用户文件不变量必须为 `pass`：placeholder marker / 原文件 / conflicted copy 不被静默删除、
   自动合并或覆盖，`README.md` 和根目录 `AREAMATRIX.md` 不被写入。
6. 只有所有字段都是真实 `pass`，并且 `recovery-scenarios.md` 与 `release-checklist.md`
   同步更新后，才能把 `closes_residual` 改为 `true`。
7. `icloud-placeholder-smoke-audit` 只证明记录字段是否齐备；即使审计返回 `PASS`，仍不能独立关闭
   `v1-rl-002` 或替代真实 iCloud UI 冒烟。

## 当前待补证字段

| 字段 | 当前状态 | 关闭所需证据 |
|---|---|---|
| `smoke_audit.smoke_evidence_gate` | `BLOCKED` | 下列真实 M-02 字段全部补齐后审计才可通过。 |
| `metadata_probe.status` | `pending` | 在真实 iCloud placeholder path 上保存 helper JSON。 |
| `environment.icloud_drive` | `blocked` | 测试机已登录 iCloud，测试 repo 或源文件位于 iCloud Drive。 |
| `placeholder_before.mdls_downloading_status` | `pending` | `mdls` 显示未下载或 downloading 状态。 |
| `ui_retry.status` | `pending` | App UI 执行 `Download & retry`。 |
| `placeholder_after.downloaded_file_observed` | `pending` | 下载后真实文件可见，且不是只读 metadata 推断。 |
| `repo_and_db_evidence.db_row_result` | `pending` | DB row 与 retry 后 import/conflict flow 一致。 |
| `user_file_invariants.*` | `pending` | 用户文件、conflicted copy、README 和根 `AREAMATRIX.md` 不被静默改写。 |

## Related

- [recovery-scenarios.md](recovery-scenarios.md)
- [release-checklist.md](release-checklist.md)
- [v1 release residuals](../residuals/release-evidence.md)
