# AreaMatrix Validation Report Format

Use this structure when reporting validation choices or results.

## Format

```text
改动范围:
- <paths or task labels>

推荐验证:
- <commands and why they are sufficient>

已运行:
- <command>: <result>

未运行:
- <command>: <reason>

工程质量:
- <coding standards, comments, error handling, tests, and maintainability evidence>

结果:
- PASS / FAIL / BLOCKED

残余风险:
- <remaining risk or None>
```

## Rules

- `已运行` means the command actually ran in this workspace.
- `未运行` must include a concrete reason, not a vague note.
- `PASS` requires all required checks to pass or be explicitly out of scope.
- `PASS` also requires the implementation to satisfy `engineering-quality-rules.md` and `docs/development/coding-standards.md`.
- `BLOCKED` is correct when the environment cannot run a required check.
- Dry-run can validate runner wiring, but never validates product implementation.

## Common Phrases

Use:

- `未运行: 当前环境缺少 X，无法执行 Y。`
- `残余风险: 未覆盖 macOS 真机交互，仅完成 build/test。`
- `结果: BLOCKED，原因是必需验证命令无法在当前环境完成。`

Avoid:

- `应该没问题`
- `看起来通过`
- `dry-run 已证明 task 完成`
