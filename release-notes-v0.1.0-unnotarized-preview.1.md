# AreaMatrix 0.1.0 Unnotarized Preview 1

Prerelease date: 2026-06-16

This is a trusted tester preview. It is not the official Stage 1 alpha release.
The app is not Developer ID signed and has not been notarized by Apple.

## Artifact

- Tag: `v0.1.0-unnotarized-preview.1`
- Asset: `AreaMatrix-v0.1.0-unnotarized-preview.1.dmg`
- SHA-256:
  `fcd432348e489e6be8194925f6d02b18dc222331569acce8bb175e0e7073d8d1`
- App version: `0.1.0`
- Build number: `202606161707`
- Executable SHA-256:
  `1482d7564352d461d439df4393f5ee26be8331ec1b2ba7b6656c2b34cda9786e`

## Install Notes

Install only if you trust this repository and this prerelease asset.

macOS may block the app because it is not notarized. Use Control-click Open or
System Settings > Privacy & Security > Open Anyway. Do not disable Gatekeeper globally.

## Validation Snapshot

- `./dev release local-qa --build-number 202606161707 --derived-data-path build/UnnotarizedPreview-0.1.0-preview.1-cli`
  completed successfully.
- DMG creation completed with `hdiutil create -format UDZO`.
- `hdiutil attach AreaMatrix-v0.1.0-unnotarized-preview.1.dmg -nobrowse`
  completed CRC verification and mounted
  `/Volumes/AreaMatrix 0.1.0 Unnotarized Preview 1`.
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
