# Secret Scan Runbook

维护者在合并路径脱敏与 gitleaks 门禁后，按可见性执行一次历史扫描并归档结果（不要提交含真实 secret 的报告到 Git）。

## 当前 HEAD 扫描

```bash
./dev check secrets
rg '/Users/[A-Za-z0-9._-]+/' tasks/prompts/_shared/progress.json .codex/task-loop-runs || true
```

## 全历史扫描（公开仓库必做）

```bash
# 需要本地安装 gitleaks：brew install gitleaks
GITLEAKS_LOG_OPTS="--all" ./dev check secrets
git log -p -- .codex/task-loop-progress-backups/ > /tmp/areamatrix-progress-backups-history.patch
```

## 结果处置

| 发现 | 建议 |
|------|------|
| 仅 `/Users/...` 路径泄露、无 token/密钥 | 保留历史亦可；当前 HEAD 已脱敏并 gitignore backups |
| 真实 secret 或必须消除用户名 | 维护者确认后使用 `git filter-repo` 清理相关路径并重写 remote（高风险，需协调 fork） |
| 私有仓库 | 归档扫描输出即可，history rewrite 通常不必 |

2026-06-11：快速 grep 未发现 `sk-` / `ghp_` / 私钥模式；主要历史风险为本机绝对路径（Low，见 SECURITY.md）。
