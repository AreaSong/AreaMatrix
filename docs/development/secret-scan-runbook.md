# Secret Scan Runbook

维护者在合并路径脱敏与 gitleaks 门禁后，按可见性执行扫描并归档结果（不要提交含真实 secret 的报告到 Git）。

## 默认：只扫当前变更（diff 模式）

`./dev check secrets` 默认 **不扫全 Git 历史**，避免已公开仓库里旧 commit 的本机路径（`/Users/...`）误报。

扫描范围：

1. 未提交的 staged / unstaged 变更（`gitleaks protect`）
2. 相对 `origin/main` 尚未 push 的 commit（`gitleaks detect --log-opts=<merge-base>..HEAD`）

```bash
./dev check secrets
```

工作区干净且没有领先 `origin/main` 的 commit 时，会输出 `nothing to scan` 并 **PASS**。

## 维护者：归档路径专项扫描（可选）

需要复核归档材料是否包含本机绝对路径或凭据模式时，先从 [workflow versions](../../workflow/versions/README.md) 定位范围，再单独运行定向扫描。

不要把归档路径补扫加入提交前门禁；它只用于维护者专项审计。

## 维护者：全历史审计（可选）

公开仓库已接受历史 path-leak 时，全历史扫描 **预期大量 path-leak**，仅作档案/审计，不作为提交前门禁。

```bash
# 需要本地安装 gitleaks：brew install gitleaks
AREAMATRIX_GITLEAKS_MODE=history GITLEAKS_LOG_OPTS="--all" ./dev check secrets
```

报告写入 `.gitleaks-report.json`（已在 `.gitignore`）。

## 结果处置

| 发现 | 建议 |
|------|------|
| diff 模式 path-leak | 提交前修复；不要写入 `/Users/...` 绝对路径 |
| 全历史 path-leak、无 token/密钥 | 已公开仓库可保留历史；HEAD 与后续 commit 保持 repo-relative |
| 真实 secret | 轮换密钥 + 从历史移除（`git filter-repo`）需维护者确认 |
| `generic-api-key` 误报 | 测试 fixture / build log：在 `.gitleaks.toml` allowlist 或改占位符 |

历史审计结果属于一次性证据，应保存在对应审计记录中，不写入长期 runbook。重写公开 Git 历史会改变所有 commit，只有确认真实 secret 泄露且完成密钥轮换、协作者协调和回滚方案后才能执行。
