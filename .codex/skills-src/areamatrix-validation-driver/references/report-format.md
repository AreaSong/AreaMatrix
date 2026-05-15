# AreaMatrix Validation Report Format

Use this structure when reporting validation choices or results.

## Format

```text
改动范围:
- <paths or task labels>

改了什么:
- <core behavior, docs, rules, or generated materials changed>

为什么这样改:
- <task/docs/governance/risk boundary that required the change>

推荐验证:
- <commands and why they are sufficient>

已运行:
- <command>: <fresh result, exit status, key evidence>

未运行:
- <command>: <reason>

证据新鲜度:
- <which results were rerun after the final relevant change>

工程质量:
- <coding standards, comments, error handling, tests, and maintainability evidence>

Blocker:
- Review: clear / blocked / not-applicable
- Security: clear / blocked / not-applicable
- Dependency: clear / blocked / not-applicable
- CI: clear / blocked / not-applicable
- Git evidence: clear / blocked / not-applicable

结果:
- PASS / FAIL / BLOCKED / NOT-READY

残余风险:
- <remaining risk or None>
```

## Rules

- `已运行` means the command actually ran in this workspace.
- `证据新鲜度` must say whether the command ran after the final relevant file change; stale output cannot support a completion claim.
- `未运行` must include a concrete reason, not a vague note.
- `PASS` requires all required checks to pass or be explicitly out of scope.
- `PASS` also requires the implementation to satisfy `engineering-quality-rules.md` and `docs/development/coding-standards.md`.
- `PASS` is invalid when review, security, dependency, CI, or Git evidence blockers remain; use `BLOCKED` or `NOT-READY`.
- `BLOCKED` is correct when the environment cannot run a required check.
- `NOT-READY` is correct when work remains even though some validation commands passed.
- Dry-run can validate runner wiring, but never validates product implementation.
- Old logs, prior memories, screenshots, mock-only paths, fixture-only paths, hardcoded success, and agent self-reports are not completion evidence.

## Common Phrases

Use:

- `未运行: 当前环境缺少 X，无法执行 Y。`
- `残余风险: 未覆盖 macOS 真机交互，仅完成 build/test。`
- `结果: BLOCKED，原因是必需验证命令无法在当前环境完成。`

Avoid:

- `应该没问题`
- `看起来通过`
- `dry-run 已证明 task 完成`
