# 恢复证据与手工冒烟规则

> 定义 AreaMatrix 恢复类质量证据的长期规则；版本执行记录从 workflow versions 归档入口查阅。
>
> 阅读时长：约 5 分钟。

---

## 定位

本文是长期源事实，规定恢复场景、手工冒烟和发布证据的记录方式。具体版本的执行结果、截图、日志、阻断原因和发布清单不放在 `docs/`，而是归档到对应版本目录。

历史恢复证据通过 [workflow versions](../../workflow/versions/README.md) 和 residual ledger 定位。常见证据类型包括：

- recovery scenarios
- 发布清单
- performance baseline
- 收口决策

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

## 发布处理

发布时，所有适用的自动化与手工恢复检查都必须通过。本机工程验证、ad-hoc signing、同机 smoke 或未公证 DMG 不能替代 Developer ID signing、notarization、stapler、正式 DMG 或干净 Mac Gatekeeper 验证。无法完成的检查必须在对应发布记录中注明所缺条件、产品影响和恢复路径。

## Related

- [testing.md](testing.md)
- [release.md](release.md)
- [troubleshooting.md](troubleshooting.md)
- [error-recovery-matrix.md](error-recovery-matrix.md)
- [../architecture/transactional-import.md](../architecture/transactional-import.md)
