---
name: areamatrix-macos-ui
description: "Use when implementing, changing, or reviewing AreaMatrix macOS SwiftUI pages, views, components, interactions, accessibility copy, or application-owned user-visible text. Trigger phrases include 新增页面 / 修改页面 / SwiftUI / UI 交互 / 硬编码文案 / 本地化 / L10n / String Catalog / xcstrings / 语言切换."
---

# AreaMatrix macOS UI

Use this skill for macOS UI implementation and review. Keep feature ownership, runtime localization, accessibility, and validation evidence in one page-delivery loop.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [apps/macos/AGENTS.md](../../../apps/macos/AGENTS.md)
3. [docs/adr/0008-naming-and-i18n.md](../../../docs/adr/0008-naming-and-i18n.md)
4. The authority docs registered for the affected feature.
5. The affected views/models and relevant catalog keys; do not load the entire String Catalog when targeted lookup is sufficient.

## References

- [references/page-l10n-checklist.md](references/page-l10n-checklist.md): text classification, implementation sequence, and acceptance evidence.
- [../areamatrix-validation-driver/SKILL.md](../areamatrix-validation-driver/SKILL.md): choose build, test, and UI evidence after the localization gate.
- [../areamatrix-doc-sync/SKILL.md](../areamatrix-doc-sync/SKILL.md): align UX or product docs when behavior changes.
- [../areamatrix-file-safety/SKILL.md](../areamatrix-file-safety/SKILL.md): use when the page can mutate user files, metadata, DB, staging, sync, or iCloud state.

## Workflow

1. Read the nearest rules and identify the existing feature owner before editing.
2. Inventory every application-owned visible string, including accessibility and error/recovery paths.
3. Classify each value before coding: immediate `String`, deferred `LocalizedMessage` / `AppDisplayText`, editable default, or reasoned verbatim data.
4. Implement with static L10n keys and add complete `en` / `zh-Hans` catalog entries in the same change.
5. Resolve deferred messages at the View boundary so existing state reprojects after an interface-language change.
6. Run `./dev check localization` before build/test; fix missing keys, locale parity, placeholders, bypasses, and raw display-state findings.
7. Run the smallest sufficient macOS build/tests and verify both supported interface languages when visible copy or language interaction changed.

## Guardrails

- Do not add application-owned user-visible text that bypasses the String Catalog.
- Do not use `L10n.string` for text retained in model, error, toast, asynchronous, or deferred display state; preserve a message descriptor instead.
- Do not use `L10n.message` as a queue or eagerly resolve it before storage; resolve at the display boundary.
- Do not interpolate or concatenate L10n keys. Use catalog placeholders and typed arguments.
- Do not use `verbatim` to silence localization work; require a real `VerbatimReason` for user content, paths, filenames, brand, glyph, or technical identifiers/details.
- Do not overwrite user-editable state after a language change; materialize application-owned draft defaults once with `L10n.editableDefault`.
- Do not force a view rebuild with `.id(locale)` to obtain fresh text; keep state identity stable and let `AppLocalizer` reproject display text.
- Do not report a page complete from build success alone; localization, relevant tests, and required UI evidence must also pass.
