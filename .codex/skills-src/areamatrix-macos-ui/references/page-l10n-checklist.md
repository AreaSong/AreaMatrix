# macOS Page And L10n Checklist

Use this checklist for new or changed SwiftUI pages and components.

## Classify Before Coding

| Text lifetime | API | Required display behavior |
|---|---|---|
| Immediate, computed, not retained | `L10n.string`, `format`, `plural` | Resolve using the current interface language now. |
| Model/error/toast/async/deferred state | `L10n.message`, `pluralMessage`, `display` | Store the descriptor and call `AppLocalizer.resolve` in the View. |
| Application-owned editable default | `L10n.editableDefault` | Materialize once when the draft is created; never refresh over user edits. |
| User content, path, filename, brand, glyph, technical identifier/detail | `L10n.verbatim` | Preserve the value with an accurate `VerbatimReason`. |

## Implementation

- Inventory titles, labels, buttons, menus, help, empty/loading/error states, confirmations, toast, recovery actions, and accessibility text.
- Use static catalog keys. Put variable values in placeholders and preserve placeholder parity across locales.
- Add exactly `en` and `zh-Hans`, both marked translated, to `Localizable.xcstrings`.
- Keep application-owned messages out of persisted session/recovery payloads; persist stable domain codes and remap after restore.
- Keep OS-owned panels and system UI under macOS localization ownership.
- Keep `accessibilityIdentifier` stable and untranslated; localize accessibility labels, values, hints, actions, and announcements.

## Acceptance

1. Run `./dev check localization`.
2. Run the relevant macOS build and tests selected by `areamatrix-validation-driver`.
3. For visible copy or language interactions, exercise both `en` and `zh-Hans` without recreating model state.
4. Confirm retained errors, toast, banners, sheets, and progress text reproject after language changes.
5. Confirm user content, paths, filenames, identifiers, and editable drafts remain unchanged.
6. Report any UI smoke not run and the residual risk; screenshots alone do not replace build/tests.
