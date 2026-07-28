# v3 Docs Discussion

## Feature Intent

v3 完成 AreaMatrix 的最终双语言架构：应用界面语言、资料库内容语言、地区格式和用户原文四个域
严格分离；Core、UniFFI、macOS UI、生成物、恢复流程和治理检查使用同一份长期合同。

## User Paths

- Welcome 快捷切换或独立 Language 设置页修改设备级应用界面语言。
- 创建或接管资料库时选择内容语言，默认“跟随界面”；之后在 Language 设置页显式保存修改。
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
- `docs/api/error-codes.md`
- `docs/ux/error-messages.md`
- `docs/development/coding-standards.md`
- `docs/development/testing.md`
- `docs/development/ci-governance.md`

## Contention Points Resolved

- System resolution checks only the first preferred language. Simplified Chinese aliases resolve to `zh-Hans`,
  English aliases resolve to `en`, and every other first item falls back to `en`.
- While the stored interface preference is `system`, launch, application activation, and the system locale-change
  notification re-resolve that first preferred language and broadcast the result to every window. Explicit `zh-Hans`
  or `en` ignores later system-language changes. Unknown stored app preferences run as `system` without implicit
  write-back; the next explicit selection writes a canonical value.
- Welcome displays the stored interface preference rather than only its resolved locale and cycles
  `system -> zh-Hans -> en -> system` without a menu. In system mode its tooltip and accessibility value also expose
  the current concrete resolution. Its compact visual states are globe plus an automatic marker for system, `中` for
  Simplified Chinese and `EN` for English. Repository follow-interface summaries use the same distinction.
- The app supports multiple windows. Interface changes propagate to every window; repository drafts remain local,
  and stale saves fail with CAS conflict instead of overwriting another window.
- App language selection commits immediately. Repository content language on the Language page and classifier edits use
  Save/Discard/Cancel gates.
- New repositories expose a content-language choice before the first generated overview; the default is follow-interface.
- Saving repository content language confirms the stored policy and current concrete result, states that existing
  generated content was not rewritten, and offers explicit regeneration only when provenance is not synchronized.
- App-owned scaffold for a new `AREAMATRIX.md` lives inside the managed block. Existing text outside the block is
  user-owned and is never translated or replaced.
- Missing, unreadable, or invalid classifier YAML never silently falls back to embedded rules. Browsing degrades to
  stable slugs with a persistent error; only explicit validate/restore actions may repair it.
- Known locale aliases are readable without write-back. Classifier mutation first requires an explicit canonicalize
  action. Unknown policy is strict read-only except for the explicit canonical policy save and dedicated recovery. Once
  canonical, either Simplified Chinese or English classifier entries may be edited regardless of the active content
  policy; `editing_locale` selects the patched map entry and does not constrain presentation or generation. One draft
  freezes one editing locale; switching a dirty draft requires Save, Discard, or Cancel. Restoring last-valid classifier
  state first creates a numbered non-overwriting backup and never substitutes defaults when no valid backup exists. A
  missing locale entry renders as an empty field with a separate read-only fallback preview; fallback text is never
  inserted into the field or persisted as a translation without explicit user input.
- Overview regeneration is an explicit Core-owned recoverable transaction. It freezes repository revision, target set,
  concrete locale and format version, stages a complete write plan, and journals commit/rollback. Cancellation before
  commit leaves all old output; repository revision drift aborts before commit; commit is not cancellable. A crash may
  leave physical files mid-commit, but the repository cannot resume normal writes until recovery converges to an all-old
  or all-new settled state. It writes only generated overview outputs and the optional legal `AREAMATRIX.md` managed
  block, never AI results or user-owned text, and records locale/operation/format provenance.
  Provenance drives five overview-language states without inspecting generated prose: not-generated, synchronized,
  needs-regeneration, mixed, and unknown. Needs-regeneration carries stable reasons for locale mismatch, format mismatch,
  missing targets, and obsolete targets; mixed means multiple known locale/format values; unknown means any existing
  output lacks trusted provenance. Legacy output without provenance stays unknown. The complete target set includes
  current categories and removes obsolete regular
  node outputs only inside the AreaMatrix-owned generated directory; removals use the same journal and rollback path.
  Preflight shows target locale plus create/replace/delete counts and managed-root participation. After commit starts,
  recovery rolls forward when the staged plan verifies, otherwise rolls back from a verified backup; unverifiable state
  keeps ordinary writes blocked.
- Persistable AI natural language uses the frozen content locale. An accepted unedited summary remains generated;
  editing a summary or accepting a generated tag transitions it to user-owned. Every save uses content-revision CAS,
  no saved result is silently replaced, and replacing user-owned content requires an explicit old/new confirmation.
  Search queries/results, slugs and provider identifiers remain verbatim. UI status and errors use interface locale.
  The frozen locale records what AreaMatrix requested; it is not treated as infallible language detection. Text reported
  by provider metadata or a high-confidence advisory detector as another language stays an unmodified review draft with
  a warning and is not auto-translated or silently retried. No reliable signal means no mismatch claim.
- OS chrome follows macOS. App-supplied text passed into a system panel is resolved when the panel opens and frozen
  for that presentation. Raw provider/system diagnostics remain verbatim behind a technical-details boundary.
- Every recoverable operation persists a data-minimized context before its first side effect or remote call: stable
  identity, operation type, concrete locale, revisions, canonical options, target identifiers or hashes, format version
  and recovery state. It never duplicates reconstructable user content, full prompts or secrets solely for recovery.
- Each user-triggered attempt owns one `operation_id`. A terminal failure followed by explicit Retry creates a new ID
  linked by `retry_of_operation_id`; crash recovery, continuation, replay, rollback, the same external-sync cursor window
  and in-operation provider fallback retain the original ID. Internal restarts use `run_sequence`, remote calls use
  `call_id`, and no overlapping public `attempt_id` exists. Undo/Redo restores original bytes and provenance.
- Persisted generated formats use the frozen content locale, UTC, and a versioned deterministic format contract. UI
  dates, numbers, sizes and currency continue to use the live macOS region independently of interface language.
- RepoConfig CAS conflicts retain the local draft and never auto-retry or silently merge. The user may discard and
  reload, or review dirty fields against the latest revision and explicitly save again. Core returns the stable
  `repo_config_revision_conflict` code plus expected/current revisions; the latest snapshot is loaded explicitly rather
  than embedded in an exception. Clean windows refresh; dirty windows retain their draft and become stale.
- Core errors cross the binding as stable structured codes, fields, arguments, recovery action identifiers and optional
  verbatim technical details. Swift resolves user-facing copy in the current interface language; logs and recovery
  state never persist translated display sentences.
- `external_sync_receipts` legacy NULL locale rows require a repository/cursor/exact-receipt-set recovery token and
  an explicit user-selected concrete locale. No current setting is guessed.
- Schema v3 migration uses a fresh non-overwriting numbered backup, an immediate transaction, locale CHECK/triggers,
  integrity checks, and rollback that leaves v2 intact on failure. The application does not automatically delete those
  migration backups. Recognized legacy values and aliases remain readable without write-back; when no language policy
  can be proven the repository stays unknown and blocks generation until the user explicitly selects a canonical policy.
  Existing prose is never inspected to infer that policy.
- Missing app-owned catalog copy falls back to English plus the stable code. Raw technical details remain collapsible
  and copyable, while logs and recovery records retain only stable structured values and necessary verbatim details.
- A legacy repository with no provable language policy remains browsable and shows persistent non-blocking guidance.
  Its Language-page chooser starts with no selected option rather than implying consent, offers follow-interface,
  Simplified Chinese and English, and shows the current concrete result beside follow-interface. Only explicit Save
  unlocks generation and classifier mutation, and that save never regenerates existing output.
- Repository CAS review shows the previously observed value, the latest persisted value and the local dirty value for
  affected fields. Reload discards the draft; Review updates only the visible baseline and always requires a second
  explicit Save. There is no force-overwrite action or silent rebase even when changes appear non-overlapping.
- Classifier conflict review retains the complete draft and frozen editing locale, compares only that locale and the
  affected rule fields against the latest snapshot, and keeps the other locale map read-only. Reload or explicit review
  followed by a new Save are the only mutation paths.
- Overview regeneration is entered and summarized in Language. Pre-commit work may be cancelled; commit disables
  cancellation and non-initiating windows remain read-only observers. Crash recovery derives roll-forward or rollback
  from verified Core evidence and never asks the user to choose an unsafe recovery direction.
- Generating a replacement for a user-owned summary preserves the current saved value and presents it beside the new
  draft. Replace, keep and continue editing are explicit choices; clear also requires confirmation. A content-revision
  conflict retains the draft, and Retry creates a linked new operation rather than mutating the failed identity.
- Recovery stays in its owning Repository, Classifier or AI surface. Only startup file-transaction recovery may block
  application entry. Verbatim technical details remain collapsible and copyable, unknown recovery actions are omitted,
  and interface-language changes re-resolve display copy without changing the underlying operation or draft.
- A missing classifier never activates embedded rules silently. It enters degraded read-only and exposes a separate,
  confirmed Create Default action. Readable invalid content may use Restore Default or Restore Last Valid only after a
  numbered non-overwriting backup; unreadable content must first regain readable permissions. Display fallback is exact
  raw -> resolved concrete -> English -> slug for known explicit/alias policies, current concrete -> English -> slug for
  follow-interface, and exact raw -> English -> slug for unknown policies.
- Follow-interface stores only the policy and resolves independently on each device. A live interface resolution change
  reprojects clean content presentation without incrementing repository revision; running operations and dirty classifier
  drafts retain their frozen locale. Language changes do not alter stable category ordering, file sort mode, selection,
  expansion, scrolling, focus, routes, sheets, or draft identity.
- Generated bytes that no longer match trusted provenance are unknown. Normal incremental generation fails closed rather
  than overwriting them; explicit full regeneration may replace them only through preflight, journal, verified backup and
  strict regular-file/path checks. Missing English catalog copy falls back to a built-in generic English sentence plus
  stable code, and unknown recovery action IDs are not rendered as unusable controls.
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
deterministic UTC formatting, structured-error fallback, AI ownership transitions, binding verification, Core tests,
macOS tests/build, and a real Debug macOS UI smoke run using fixture repositories only.
