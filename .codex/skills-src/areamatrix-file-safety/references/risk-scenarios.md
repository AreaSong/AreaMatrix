# AreaMatrix File Safety Risk Scenarios

Treat these scenarios as Mission-Critical unless the task explicitly proves it is read-only.

| Scenario | Risk | Required preflight |
|---|---|---|
| Adopt existing folder | Moving, deleting, renaming, or overwriting user files | State that only `.areamatrix/` internal metadata may be created; verify original files remain untouched. |
| Init empty repo | Incorrect cleanup can remove user-selected path contents | Confirm cleanup only targets incomplete `.areamatrix/` state. |
| Import copy/move/index | Source loss, final directory half-products, DB/filesystem mismatch | Define transaction, staging, rollback, duplicate handling, and post-failure state. |
| Staging recovery | Deleting recoverable user data or leaving leaked temporary files | Identify safe-to-delete criteria and evidence for retained files. |
| DB migration or repair | Metadata corruption or irreversible schema changes | Require backup, migration path, rollback path, and integrity checks. |
| Reindex | Metadata overwrite, stale deletes, external file misclassification | Define external-origin handling and no user-file mutation guarantee. |
| FSEvents or external sync | Feedback loops, hidden writes, iCloud placeholder side effects | Define in-flight filtering, placeholder policy, and event ordering. |
| Generated overview | Overwriting README or user-authored files | Confirm default output stays under `.areamatrix/generated/`; root `AREAMATRIX.md` requires explicit docs and consent. |
| Delete `.areamatrix/` recovery | Confusing metadata deletion with user-file deletion | Verify user files remain intact and recovery/reindex path is documented. |
| Remote AI or privacy boundary | User content, paths, metadata, or generated summaries leave the local machine | Require explicit user intent, data minimization, redaction / logging policy, opt-out path, and residual-risk note. |

## Threat Modeling Add-on

Use this add-on only when the user explicitly asks for a threat model or the file-safety change introduces a new high-risk boundary.

- Assets: original user files, `.areamatrix/` metadata, DB, staging, index, logs, config, AI request / response content.
- Trust boundaries: user-selected folder vs app state, filesystem vs DB, staging vs final directory, Core vs Swift platform layer, FSEvents / iCloud vs in-flight app operations, local machine vs remote AI / network service.
- Entry points: folder adoption, import, recovery, reindex, watcher events, placeholder downloads, generated overview writes, Core API / UDL calls, logs, remote AI requests.
- Attacker capabilities: controlled filenames, paths, content, symlinks, event timing, placeholder state, network responses, dependency inputs; also list non-capabilities.
- Abuse paths: data loss, overwrite, unauthorized read/write, path traversal, DB / filesystem mismatch, DoS, log leakage, remote data exposure.
- Mitigations: no-overwrite invariant, path normalization, temporary-dir isolation, transaction / rollback, DB integrity checks, in-flight event filtering, placeholder policy, explicit consent, data minimization, log redaction.
- Residual risk: assumptions, unverified paths, operational follow-up, and remaining user-action requirements.

## Preflight Statement

Before implementation, state:

- files or metadata that may be written
- files that must not be touched
- rollback or recovery path
- validation commands and manual evidence

## Stop Conditions

Stop and ask for confirmation when:

- a command may delete, move, rename, or overwrite user files
- schema migration is irreversible
- task requires downloading iCloud placeholders
- implementation needs to write outside `Expected New Paths`
- verification cannot prove filesystem and DB consistency
