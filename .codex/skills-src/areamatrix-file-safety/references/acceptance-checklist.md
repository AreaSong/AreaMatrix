# AreaMatrix File Safety Acceptance Checklist

Use this checklist before declaring a file-safety task complete.

## Filesystem Evidence

- Existing user files before the operation are still present.
- No user file was moved, renamed, overwritten, or deleted unless the task explicitly required and confirmed it.
- Generated output is under `.areamatrix/generated/` unless docs explicitly permit another target.
- Existing `README.md` remains untouched.
- Temporary or staging files are either committed to final state or safely recoverable.

## DB Evidence

- DB rows match filesystem state for imported, indexed, moved, deleted, or recovered files.
- Migration changed schema version as expected.
- Foreign keys and integrity checks pass when DB behavior changed.
- Failed operations do not leave final directory half-products.

## Rollback Evidence

- Backup exists before destructive metadata changes.
- Recovery path is documented or tested.
- Re-running startup recovery is idempotent where applicable.
- Deleting `.areamatrix/` does not delete user files.

## Forbidden Touches

Check task manifest:

- `Forbidden Touches` were not modified.
- Any needed out-of-scope touch was stopped and reauthorized.
- `Expected New Paths` contains every product path modified by the task.

## Validation Evidence

Prefer automated tests with temporary directories. If manual evidence is required, include:

- setup path
- command or action
- observed filesystem result
- observed DB result
- cleanup performed

Missing evidence means the task is not accepted.

## Threat Model Evidence

Required only for explicit threat-model tasks or new high-risk boundaries:

- Assets, trust boundaries, entry points, attacker capabilities, abuse paths, mitigations, and residual risk are present.
- User files, DB, staging, FSEvents / iCloud, privacy, and remote AI calls were considered when in scope.
- Existing controls are separated from proposed controls.
- Ordinary code review, tests, CI, and file-safety validation still have their own evidence.
