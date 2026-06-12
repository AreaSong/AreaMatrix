# Secret Scan Runbook

维护者在合并路径脱敏与 gitleaks 门禁后，按可见性执行扫描并归档结果（不要提交含真实 secret 的报告到 Git）。

## 默认：只扫当前变更（diff 模式）

`./dev check secrets` 默认 **不扫全 Git 历史**，避免已公开仓库里旧 commit 的本机路径（`/Users/...`）误报。

扫描范围：

1. 未提交的 staged / unstaged 变更（`gitleaks protect`）
2. 相对 `origin/main` 尚未 push 的 commit（`gitleaks detect --log-opts=<merge-base>..HEAD`）

```bash
./dev check secrets
rg '/Users/[A-Za-z0-9._-]+/' tasks/prompts/_shared/progress.json .codex/task-loop-runs || true
```

工作区干净且没有领先 `origin/main` 的 commit 时，会输出 `nothing to scan` 并 **PASS**。

## 维护者：全历史审计（可选）

公开仓库已接受历史 path-leak 时，全历史扫描 **预期大量 path-leak**，仅作档案/审计，不作为提交前门禁。

```bash
# 需要本地安装 gitleaks：brew install gitleaks
AREAMATRIX_GITLEAKS_MODE=history GITLEAKS_LOG_OPTS="--all" ./dev check secrets
git log -p -- .codex/task-loop-progress-backups/ > /tmp/areamatrix-progress-backups-history.patch
```

报告写入 `.gitleaks-report.json`（已在 `.gitignore`）。

## 结果处置

| 发现 | 建议 |
|------|------|
| diff 模式 path-leak | 提交前修复；不要写入 `/Users/...` 绝对路径 |
| 全历史 path-leak、无 token/密钥 | 已公开仓库可保留历史；HEAD 与后续 commit 保持 repo-relative |
| 真实 secret | 轮换密钥 + 从历史移除（`git filter-repo`）需维护者确认 |
| `generic-api-key` 误报 | 测试 fixture / build log：在 `.gitleaks.toml` allowlist 或改占位符 |

## 当前结论（2026-06-11）

- 仓库 **已公开**；**不 rewrite Git history**（Low 级路径泄露，无真实 key）。
- 全历史约 79k path-leak、10 条疑似误报 `generic-api-key`。
- HEAD 的 progress / task-loop-runs 已无 `/Users/as`。
