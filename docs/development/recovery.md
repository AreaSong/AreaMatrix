# 恢复证据与手工冒烟规则

> 定义 AreaMatrix 恢复类质量证据的长期规则；阶段性执行记录归档到对应 `workflow/versions/v*/`。
>
> 阅读时长：约 5 分钟。

---

## 定位

本文是长期源事实，规定恢复场景、手工冒烟和 release evidence 的记录方式。具体阶段的执行结果、截图、日志、blocked 原因和 release checklist 不放在 `docs/`，而是归档到对应版本目录。

当前 Stage 1 历史证据位于：

- [v1 recovery scenarios](../../workflow/versions/v1-mvp/evidence/recovery-scenarios.md)
- [v1 release checklist](../../workflow/versions/v1-mvp/evidence/release-checklist.md)
- [v1 performance baseline](../../workflow/versions/v1-mvp/evidence/performance-baseline.md)
- [v1 closeout decision](../../workflow/versions/v1-mvp/closeout/closeout-decision.md)

## 不变量

恢复、reindex、repair、import interruption、iCloud placeholder 和权限恢复都必须守住以下规则：

- 不删除、移动、重命名或覆盖用户原文件，除非用户明确执行对应高风险操作。
- 失败导入不得留下最终目录半成品，也不得把失败操作标记为成功。
- `.areamatrix/staging/` 中间产物不得进入用户可见列表。
- DB repair、reindex、iCloud placeholder retry 和权限恢复不得静默改写用户文件。
- 应用不得覆盖用户已有 `README.md`；自动生成内容默认只写入 `.areamatrix/generated/`。

## 手工证据格式

手工冒烟必须记录为结构化证据，不能只写“已看过”。缺失、失败或环境 blocked 都必须明确写出，不得降级为 PASS。

```yaml
manual_evidence_id: M-xx
manual_evidence_status: "pending | pass | fail | blocked"
environment:
  macos_version: "<sw_vers -productVersion>"
  app_build: "<AreaMatrix build or test bundle>"
  repo_path: "<test repo path, redacted if needed>"
operator: "<name or release role>"
executed_at: "<ISO-8601 timestamp>"
result: "pending | pass | fail | blocked"
evidence_paths:
  - "<screenshot, log, sqlite output, checksum output, or diagnostics path>"
user_file_invariants:
  source_files_preserved: "pass | fail | not_applicable"
  no_final_half_files: "pass | fail | not_applicable"
  no_wrong_active_rows: "pass | fail | not_applicable"
  no_readme_or_areamatrix_overwrite: "pass | fail | not_applicable"
release_gate: "block_if_missing_or_fail"
```

## Release 处理

- 自动化测试失败时，release 不通过。
- 手工项为 `pending`、`fail` 或 `blocked` 时，release checklist 必须保留阻断结论。
- local QA、ad-hoc signing、同机 smoke、未公证 preview DMG 都不能替代 Developer ID signing、notarization、stapler、正式 DMG 或干净 Mac Gatekeeper 验证。
- 因外部条件无法完成的项目应记录为 deferred / blocked，并写清恢复条件。例如没有付费 Apple Developer Program 时，Developer ID 与 notarization 天然 blocked。

## Related

- [testing.md](testing.md)
- [release.md](release.md)
- [troubleshooting.md](troubleshooting.md)
- [error-recovery-matrix.md](error-recovery-matrix.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
