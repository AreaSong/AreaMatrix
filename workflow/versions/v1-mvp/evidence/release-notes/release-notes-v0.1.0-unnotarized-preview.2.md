# AreaMatrix 0.1.0 Unnotarized Preview 2

Prerelease date: 2026-06-16

This is a trusted tester preview. It is not the official Stage 1 alpha release.
The app is not Developer ID signed and has not been notarized by Apple.

`v0.1.0-unnotarized-preview.1` was not published. GitHub immutable release and
tag rules blocked reusing that preview number after an empty prerelease attempt,
so this recovery preview uses `v0.1.0-unnotarized-preview.2`.

## Artifact

- Tag: `v0.1.0-unnotarized-preview.2`
- Asset: `workflow/versions/v1-mvp/evidence/artifacts/AreaMatrix-v0.1.0-unnotarized-preview.2.dmg`
- SHA-256:
  `d01d44c82e2287c0f1cd12aea4e78ece46301fe2f4709b2598c5710ba89864b2`
- App version: `0.1.0`
- Build number: `202606161707`
- Executable SHA-256:
  `1a4881522acb93282cb6e0252810ea3849c7ab1095e74b8583a40e8018f28aea`

## Install Notes

Install only if you trust this repository and this prerelease asset.

macOS may block the app because it is not notarized. Use Control-click Open or
System Settings > Privacy & Security > Open Anyway. Do not disable Gatekeeper globally.

## Validation Snapshot

- `./dev release readiness-build --build-number 202606161707 --derived-data-path build/UnnotarizedPreview-0.1.0-preview.2-cli`
  completed successfully.
- DMG creation completed with `hdiutil create -format UDZO`.
- `hdiutil attach workflow/versions/v1-mvp/evidence/artifacts/AreaMatrix-v0.1.0-unnotarized-preview.2.dmg -nobrowse`
  completed CRC verification and mounted
  `/Volumes/AreaMatrix 0.1.0 Unnotarized Preview 2`.
- Mounted app version is `0.1.0`, build number is `202606161707`.
- `codesign --verify --deep --strict --verbose=2` passed for the mounted app.
- `codesign -dv --verbose=4` reports `Signature=adhoc`,
  `TeamIdentifier=not set`, and `Runtime Version=26.4.0`.
- `otool -L` does not reference `libarea_matrix_core.dylib` or repository
  absolute paths.

## Known Issues

- This build is not Developer ID signed, not notarized, and not stapled.
- Gatekeeper first launch on a clean Mac is not validated.
- M-02 iCloud placeholder real-environment smoke remains blocked until an
  iCloud placeholder test environment is available.
- This prerelease does not close P1-RL-003 and must not be described as the
  official `v0.1.0` release.
