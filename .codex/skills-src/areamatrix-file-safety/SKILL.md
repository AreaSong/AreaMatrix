---
name: areamatrix-file-safety
description: "Use when Codex touches AreaMatrix file safety boundaries such as adopting existing folders, staging recovery, DB metadata, migrations, reindex, FSEvents/iCloud sync, generated overviews, or user-file deletion/overwrite risks."
---

# AreaMatrix File Safety

Use this skill for any task that can affect user files, repository metadata, or filesystem recovery behavior.

Trigger it for non-empty folder adoption, import, staging recovery, DB metadata, migrations, rollback, reindex, FSEvents, iCloud placeholders, duplicate hash conflict handling, generated overview output, privacy-sensitive local data handling, remote AI calls involving user content, `.areamatrix/` deletion / repair, or any command that may delete, move, rename, overwrite, or download user-controlled files.

## Read first

1. [AGENTS.md](../../../AGENTS.md)
2. [.ai-governance/project/areamatrix-rules.md](../../../.ai-governance/project/areamatrix-rules.md)
3. [docs/architecture/source-of-truth.md](../../../docs/architecture/source-of-truth.md)
4. [docs/architecture/transactional-import.md](../../../docs/architecture/transactional-import.md) for import or staging work.
5. [docs/architecture/fs-watcher.md](../../../docs/architecture/fs-watcher.md) for external change sync.

## Non-negotiables

- 接管已有目录时不移动、不重命名、不删除、不覆盖任何已有用户文件。
- 自动生成内容默认只写入 `.areamatrix/generated/`。
- 应用不得覆盖用户已有 `README.md`。
- 成功导入必须同时在文件系统和 DB 可见；失败导入不得留下最终目录半成品。
- 删除 `.areamatrix/` 不得导致用户文件本身丢失。

## References

- [references/risk-scenarios.md](references/risk-scenarios.md): Mission-Critical scenarios and required preflight.
- [references/acceptance-checklist.md](references/acceptance-checklist.md): filesystem, DB, rollback, and forbidden-touch evidence.
- [../areamatrix-doc-sync/SKILL.md](../areamatrix-doc-sync/SKILL.md): source docs and Core API / UDL alignment for safety behavior.
- [../areamatrix-validation-driver/SKILL.md](../areamatrix-validation-driver/SKILL.md): validation selection for safety-sensitive changes.

## Workflow

1. Classify the task as Mission-Critical if it touches user files, DB schema, staging recovery, reindex, FSEvents/iCloud, or destructive repair.
2. Before implementation, state impact, risk, validation, and rollback.
3. Load risk scenarios before changing behavior near user files or `.areamatrix/`.
4. If the task explicitly asks for threat modeling, or the file-safety change exposes a new high-risk boundary, include assets, trust boundaries, entry points, attacker capabilities, abuse paths, mitigations, and residual risk.
5. Use the acceptance checklist before declaring the task done.

## Guardrails

- Do not use broad deletes or rewrites under user-controlled paths.
- Do not make iCloud placeholder downloads or FSEvents backflow implicit side effects.
- Do not write root `AREAMATRIX.md` or any user-visible file unless the task and docs explicitly require it.
- Do not let automation, Computer Use, hooks, or task-loop risk bypass approve destructive actions against real user files.
- Do not treat file-safety review as full enterprise security approval; merge readiness still belongs to `areamatrix-enterprise-governance`.
- Do not run broad threat modeling for ordinary low-risk changes unless explicitly requested.
