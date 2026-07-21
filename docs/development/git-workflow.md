# Git 分支与 Commit 规范

> AreaMatrix 的 Git 协作流程：分支命名、commit 信息、PR 流程、Tag 与发布。
>
> 阅读时长：约 4 分钟。

---

## 分支模型

```mermaid
gitGraph
    commit id: "init"
    branch develop
    checkout develop
    commit
    branch feat/import
    checkout feat/import
    commit
    commit
    checkout develop
    merge feat/import
    branch feat/tree
    checkout feat/tree
    commit
    checkout develop
    merge feat/tree
    checkout main
    merge develop tag: "v0.1.0"
```

| 分支 | 用途 | 写权限 |
|---|---|---|
| `main` | 主干 / 发布候选分支；用户分发仍受 release evidence 与 `./dev release status --json --remote` 门禁约束 | 维护者 / merge 自 develop |
| `develop` | 集成分支（后续按协作规模启用，当前可省） | 维护者 / merge 自 feat |
| `feat/<topic>` | 功能开发 | 任何人 |
| `fix/<topic>` | bug 修复 | 任何人 |
| `docs/<topic>` | 仅文档改动 | 任何人 |
| `refactor/<topic>` | 重构 | 任何人 |
| `chore/<topic>` | 工程化 / 构建 | 任何人 |
| `release/<version>` | 发布准备 | 维护者 |

### 当前简化版

只用 `main` + 功能分支，跳过 `develop`：

```text
main
 ├── feat/classify-engine
 ├── feat/storage-ops
 ├── feat/sidebar-tree
 └── fix/staging-cleanup
```

---

## 分支命名

格式：`<类型>/<简短描述>`

| 类型 | 用途 | 示例 |
|---|---|---|
| `feat/` | 新功能 | `feat/drag-drop-import` |
| `fix/` | bug 修复 | `fix/staging-leak` |
| `docs/` | 文档 | `docs/adr-0010-search` |
| `refactor/` | 重构 | `refactor/extract-hash-module` |
| `test/` | 加测试 | `test/sync-edge-cases` |
| `chore/` | 工程化 | `chore/upgrade-uniffi` |
| `perf/` | 性能 | `perf/tree-scan-incremental` |
| `codex/` | 自动化 / Agent 会话分支（task-loop checkpoint、doc sync 等自动化流程创建） | `codex/areamatrix-doc-sync-checkpoint` |

### 描述部分

- 全小写、`-` 分隔
- 简短（≤ 5 个单词）
- 不带 issue 编号（commit 中带）

---

## Commit 信息

遵循 [Conventional Commits 1.0](https://www.conventionalcommits.org/)：

```text
<type>(<scope>): <subject>

<body>

<footer>
```

### type 全集

| type | 含义 |
|---|---|
| `feat` | 新功能 |
| `fix` | bug 修复 |
| `docs` | 仅文档 |
| `style` | 格式（不影响代码运行） |
| `refactor` | 重构 |
| `perf` | 性能优化 |
| `test` | 测试相关 |
| `chore` | 构建 / CI / 依赖等 |
| `revert` | 回滚 |

### scope 推荐值

`classify` / `storage` / `overview` / `tree` / `sync` / `db` / `ffi` / `ui` / `bridge` / `watcher` / `ci` / `deps` / `release`。

scope 可以省略：`docs: 修正 README 拼写`。

### subject

- ≤ 72 字符
- 中文 / 英文均可
- 不以句号结尾
- 用现在时（"add" 不是 "added"）

### body（可选）

- 与 subject 间隔一空行
- 解释**为什么**和**做了什么**
- 行宽 ≤ 100 字符

### footer（可选）

- `Closes #123`、`Fixes #456`
- `BREAKING CHANGE: ...`（如有破坏性变化）
- `Co-authored-by: Name <email>`（结对编程）

### 完整示例

```text
feat(classify): 关键词匹配支持大小写折叠

之前 "Invoice.pdf" 能命中 invoice 关键词，但 "INVOICE.pdf" 不能，
用户在 #42 反馈不一致。

- 在 normalize() 中加 .to_lowercase()
- 关键词匹配前对模式也做相同处理
- 加 4 个测试覆盖大小写组合

Closes #42
```

```text
fix(storage): 修复 staging 残留清理时的 race

启动 recover_on_startup 时若 watcher 已启动，可能在我们删除 staging 文件
的瞬间收到 FSEvent，导致后续处理把这个事件当作"外部删除"处理。

修复：把 recover_on_startup 提前到 watcher.start() 之前，并加单元测试。

Fixes #58
```

---

## PR 流程

### 1. 准备分支

```bash
git checkout main
git pull origin main
git checkout -b feat/classify-keyword-fold
# 编码 + 提交
git push -u origin feat/classify-keyword-fold
```

### 2. 提 PR

通过 `gh pr create` 或 GitHub 网页：

```bash
gh pr create --title "feat(classify): 关键词匹配支持大小写折叠" \
  --body "$(cat <<'EOF'
## 改动摘要
解决 #42。统一所有路径的大小写处理。

## 改动内容
- `normalize()` 中加 to_lowercase
- 关键词匹配前同样处理
- 4 个新测试

## 测试方式
\`\`\`bash
cd core && cargo test classify
\`\`\`

## 检查清单
- [x] cargo fmt
- [x] cargo clippy 零警告
- [x] 测试通过
- [x] CHANGELOG 已更新
EOF
)"
```

### 3. CI 通过 + 评审

- 至少 1 位维护者 approve
- 所有 CI 检查通过
- 评审 comment 已回复或解决

### 4. 合并

- 推荐 squash merge，保持 main 历史易读
- 当前 main 历史同时存在 GitHub PR 产生的 merge commits；用 merge 还是 squash 由维护者按
  PR 内容选择，不强制单一方式

合并后维护者：

```bash
git push origin main
git push origin --delete feat/classify-keyword-fold
```

---

## 发布 Tag

### Tag 命名

`v<MAJOR>.<MINOR>.<PATCH>`，例如 `v0.1.0`。

### 流程

```bash
# 1. 确认 main 已含所有要发的内容
git checkout main && git pull

# 2. 按发布流程确认所有 tag 前门禁和真实发布证据已经满足

# 3. 更新版本号
# - core/Cargo.toml
# - apps/macos/AreaMatrix.xcodeproj/project.pbxproj
#   MARKETING_VERSION / CURRENT_PROJECT_VERSION（Info.plist 由 Xcode 生成）
# - CHANGELOG.md（[Unreleased] → [X.Y.Z] - YYYY-MM-DD）

# 4. 提交版本 bump
git add -A
git commit -m "chore(release): 0.1.0"

# 5. 打 tag
git tag -a v0.1.0 -m "Release 0.1.0"
git push origin main v0.1.0
```

打正式 tag 前必须完成 [发布流程](release.md) 的 tag 前门禁。只读状态或审计命令不能替代签名、公证、产物验证和外部测试；存在未关闭发布条件时不得创建正式 tag。

tag push 是否触发发布构建、签名和上传，以受治理的 release workflow 配置为准；未配置自动发布时，按 [release.md](release.md) 的手工流程执行。

---

## Rebase vs Merge

### 在自己分支上同步 main

```bash
git checkout feat/xxx
git fetch origin
git rebase origin/main
# 解决冲突
git push --force-with-lease  # 已推过的分支用 force-with-lease
```

不要用 `git pull`（会产生 merge commit）。

### main 进 PR

推荐 squash merge；当前 main 历史中也存在 PR merge commits，合并方式以维护者在 GitHub 上的
实际选择为准。

---

## 不允许

- ❌ `git push --force` 到 main / develop
- ❌ commit 巨大改动一次（≥ 1000 行视情况拒绝评审）
- ❌ 把 secrets / tokens 提交进库
- ❌ 提交 `.DS_Store` / `node_modules/` / `target/`（已有 `.gitignore`）
- ❌ 跳过 CI 强制合并
- ❌ Commit message 写"WIP"、"fix"、"asdf"

---

## .gitignore 关键内容

摘自当前 `.gitignore` 的关键条目（完整清单以仓库根 `.gitignore` 为准）：

```gitignore
# Rust
target/
**/*.rs.bk

# Xcode
build/
DerivedData/
*.xcuserstate
xcuserdata/
*.xccheckout
*.xcresult

# Generated bindings (重新生成即可)
apps/macos/AreaMatrix/Bridge/Generated/

# macOS
.DS_Store

# IDE（.vscode 只保留共享的 settings.json）
.idea/
.vscode/*
!.vscode/
!.vscode/settings.json

# 测试产物
lcov.info
*.profraw

# 资料库测试目录
AreaMatrix-dev/
```

注：`Cargo.lock` 不在忽略清单中，`core/Cargo.lock` 已提交进仓库（应用需要可重现构建，
UniFFI bindgen 版本也从中锁定）。

---

## Related

- [coding-standards.md](coding-standards.md)
- [testing.md](testing.md)
- [release.md](release.md)
- [../../CONTRIBUTING.md](../../CONTRIBUTING.md)
