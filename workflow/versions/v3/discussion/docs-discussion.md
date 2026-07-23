# v3 Docs Discussion

## Feature Intent

v3 完成 AreaMatrix 的最终双语言架构：应用界面语言、资料库内容语言、地区格式和用户原文四个域
严格分离；Core、UniFFI、macOS UI、生成物、恢复流程和治理检查使用同一份长期合同。

## User Paths

- Welcome 或 General 修改设备级应用界面语言。
- 创建或接管资料库时选择内容语言，默认“跟随界面”；之后只在 Repository 设置中修改。
- 在 English 界面中浏览中文资料库内容，或在中文界面中生成 English 内容。
- 运行中的界面切换语言而不丢失当前 route、focus、scroll、sheet、draft 或业务状态。
- 显式执行全库 overview regeneration；既有生成物不因设置变化自动重写。
- 在 classifier 编辑器中分段编辑简体中文和 English 文案；无效配置进入可恢复的只读状态。
- 在 legacy external-sync receipt 缺少 locale 时，通过明确的 recovery UI 选择语言后继续重放。

## Language Domains

1. `AppLanguagePreference`：设备级 `system` / `zh-Hans` / `en`，保存在 UserDefaults。
2. `RepositoryLocalePolicy`：资料库级 `system` / `zh-Hans` / `en`，保留 exact raw 兼容值和 unknown 值。
3. `ContentLocale`：操作级 concrete `zh-Hans` 或 `en`，在 operation identity 的线性化点冻结。
4. `RegionalFormatLocale`：瞬时 UI 的日期、数字、大小和货币格式，来自 macOS region。
5. `VerbatimValue`：文件名、路径、正文、用户标签、provider/model、endpoint、slug、原始技术细节，原样保留。

## Exact Docs

- `docs/adr/0008-naming-and-i18n.md`
- `docs/architecture/macos-frontend-architecture.md`
- `docs/architecture/data-model.md`
- `docs/architecture/migration.md`
- `docs/architecture/source-of-truth.md`
- `docs/architecture/transactional-import.md`
- `docs/architecture/fs-watcher.md`
- `docs/architecture/ffi-design.md`
- `docs/product/overview.md`
- `docs/product/product-surfaces.md`
- `docs/ux/first-launch.md`
- `docs/ux/settings-panel.md`
- `docs/ux/classifier-calibration.md`
- `docs/user-guide/settings.md`
- `docs/user-guide/ai-features-and-privacy.md`
- `docs/modules/repo-init.md`
- `docs/modules/classify.md`
- `docs/modules/tree-scan.md`
- `docs/modules/overview-gen.md`
- `docs/modules/repo-scan.md`
- `docs/modules/repair.md`
- `docs/api/classifier-yaml.md`
- `docs/api/core-api.md`
- `docs/development/coding-standards.md`
- `docs/development/testing.md`
- `docs/development/ci-governance.md`

## Contention Points Resolved

- System resolution checks only the first preferred language. Simplified Chinese aliases resolve to `zh-Hans`,
  English aliases resolve to `en`, and every other first item falls back to `en`.
- The app supports multiple windows. Interface changes propagate to every window; repository drafts remain local,
  and stale saves fail with CAS conflict instead of overwriting another window.
- App language selection commits immediately. Repository and classifier edits use Save/Discard/Cancel gates.
- New repositories expose a content-language choice before the first generated overview; the default is follow-interface.
- App-owned scaffold for a new `AREAMATRIX.md` lives inside the managed block. Existing text outside the block is
  user-owned and is never translated or replaced.
- Missing, unreadable, or invalid classifier YAML never silently falls back to embedded rules. Browsing degrades to
  stable slugs with a persistent error; only explicit validate/restore actions may repair it.
- Known locale aliases are readable without write-back. Classifier mutation first requires an explicit canonicalize
  action. Unknown policy is strict read-only except for the explicit canonical policy save and dedicated recovery.
- Overview regeneration is an explicit Core-owned, recoverable all-old-or-all-new operation. It writes only generated
  outputs and managed blocks and records locale/operation provenance.
- Persistable AI natural language uses the frozen content locale. User edits transition ownership to user-owned; a later
  replacement requires explicit confirmation. UI status and error messages use the current interface locale.
- OS chrome follows macOS. App-supplied text passed into a system panel is resolved when the panel opens and frozen
  for that presentation. Raw provider/system diagnostics remain verbatim behind a technical-details boundary.
- Every recoverable operation persists context before its first side effect or remote call. New attempts recapture;
  continuation, resume, replay, same external-sync window, and an existing automatic provider fallback reuse context.
  v3 does not introduce a new provider-failover feature.
- `external_sync_receipts` legacy NULL locale rows require a repository/cursor/exact-receipt-set recovery token and
  an explicit user-selected concrete locale. No current setting is guessed.
- Schema v3 migration uses a fresh non-overwriting numbered backup, an immediate transaction, locale CHECK/triggers,
  integrity checks, and rollback that leaves v2 intact on failure.
- Repair metadata, reindex, and overview regeneration are separate APIs and confirmation paths.
- Core/UDL/bindings use binding contract v2 with a hard cutover; mutable process-global Core locale setters are removed.

## Non-goals

- Do not add a third per-generation language selector.
- Do not add Traditional Chinese resources in this version.
- Do not translate, rename, move, delete, or overwrite user files or user-authored content.
- Do not automatically regenerate existing overviews or AI results when either language setting changes.
- Do not add automatic provider failover as a new capability.
- Do not rewrite historical v1 execution artifacts or create v3 execution files during discussion/planning.

## Acceptance Boundary

Completion requires synchronized docs/API/UDL/Rust/Swift and evidence for all four UI/content combinations, system and
alias resolution, live switching with state preservation, classifier degraded mode and recovery, config CAS conflicts,
legacy receipt recovery, schema migration rollback, operation provenance, generated-output file safety, catalog parity,
binding verification, Core tests, macOS tests/build, and a real Debug macOS UI smoke run using fixture repositories only.
