# 模块：README 生成（readme）

> 每个分类目录自动维护一份 README.md，资料库根目录有一份总 README.md。本模块负责重新生成、保留用户手动添加的内容。
>
> 阅读时长：约 5 分钟。

---

## 设计目标

1. 用户在 Finder 看每个分类目录就能一眼了解内容（不依赖应用）
2. 推到 GitHub / 给别人传时，README 是导览
3. 用户手动加的备注在自动重生成时保留
4. 性能足够：单分类 README 重生成 < 50ms

---

## 何时重生成

| 触发 | 重生成范围 |
|---|---|
| import_file | 该分类 + 根 |
| rename_file | 该分类 + 根 |
| move_to_category | 旧分类 + 新分类 + 根 |
| delete_file | 该分类 + 根 |
| 笔记编辑 | 不重生成（不影响文件清单） |
| sync external 检测到变化 | 受影响分类 + 根 |

---

## 分类 README 结构

```markdown
# 文档 (docs)

> 这个分类目录存放标准文档（PDF / DOCX / Markdown）。

<!-- AREAMATRIX:BEGIN auto-generated content; do NOT edit between markers -->

**统计**：12 个文件，总 24.5 MB · 最近导入：2026-04-25

## 文件列表

| 文件 | 大小 | 导入时间 |
|---|---|---|
| [Q1_报告.pdf](Q1_报告.pdf) | 2.1 MB | 2026-04-25 |
| [契约.docx](契约.docx) | 0.8 MB | 2026-04-23 |
...

## 近 30 天改动

- 2026-04-25 imported `Q1_报告.pdf`
- 2026-04-23 renamed `合同.pdf` → `契约.docx`
- 2026-04-20 deleted `旧版.pdf`

<!-- AREAMATRIX:END -->

## 用户备注（手动添加）

这个区域不会被自动生成覆盖。
```

### 关键点

- BEGIN/END 标记之间是托管区域，每次重生成完全替换
- 标记之外是用户区域，永远保留
- 如果用户删了 BEGIN/END 标记 → 重生成时把内容追加到文件末尾，并补回标记

---

## 根 README 结构

```markdown
# AreaMatrix 资料库

> 自动维护，请勿删除 .areamatrix/ 目录。

<!-- AREAMATRIX:BEGIN auto-generated content -->

**总览**：156 个文件 · 1.2 GB · 6 个分类

| 分类 | 文件数 | 大小 | 最近导入 |
|---|---|---|---|
| [文档 (docs)](docs/) | 12 | 24.5 MB | 2026-04-25 |
| [代码 (code)](code/) | 89 | 320 MB | 2026-04-26 |
...

## 近 7 天跨分类改动

- 2026-04-26 imported `code/main.rs`
- 2026-04-25 imported `docs/Q1_报告.pdf`
...

<!-- AREAMATRIX:END -->
```

---

## 实现

文件：`core/src/readme/mod.rs`

```rust
pub mod category;
pub mod root;

const BEGIN_MARKER: &str = "<!-- AREAMATRIX:BEGIN auto-generated content";
const END_MARKER: &str = "<!-- AREAMATRIX:END -->";

pub fn regenerate_for_category(repo: &Path, category: &str) -> CoreResult<()> {
    category::regenerate(repo, category)
}

pub fn regenerate_root(repo: &Path) -> CoreResult<()> {
    root::regenerate(repo)
}
```

### category::regenerate

```rust
pub fn regenerate(repo: &Path, category: &str) -> CoreResult<()> {
    let category_dir = repo.join(category);
    if !category_dir.exists() {
        return Ok(());  // 分类目录已删
    }
    let readme_path = category_dir.join("README.md");

    let new_managed = build_managed_section(repo, category)?;

    let final_content = match std::fs::read_to_string(&readme_path) {
        Ok(existing) => merge_with_existing(&existing, &new_managed, category),
        Err(_) => default_template_with_managed(category, &new_managed),
    };

    write_atomic(&readme_path, &final_content)?;
    Ok(())
}

fn merge_with_existing(existing: &str, new_managed: &str, category: &str) -> String {
    if let (Some(begin), Some(end)) = (existing.find(BEGIN_MARKER), existing.find(END_MARKER)) {
        let before = &existing[..begin];
        let end_close = end + END_MARKER.len();
        let after = &existing[end_close..];
        format!("{}{}{}", before, new_managed, after)
    } else {
        // 标记缺失：在文件末尾追加 managed 段
        format!("{}\n\n{}", existing.trim_end(), new_managed)
    }
}

fn write_atomic(path: &Path, content: &str) -> std::io::Result<()> {
    let tmp = path.with_extension("md.tmp");
    std::fs::write(&tmp, content)?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}
```

### build_managed_section

```rust
fn build_managed_section(repo: &Path, category: &str) -> CoreResult<String> {
    let files = db::list_active_in_category(repo, category)?;
    let recent_changes = db::recent_changes_for_category(repo, category, 30)?;

    let total_bytes: i64 = files.iter().map(|f| f.size_bytes).sum();
    let latest_import = files.iter().map(|f| f.imported_at).max().unwrap_or(0);

    let mut s = String::new();
    s.push_str(BEGIN_MARKER);
    s.push_str(" -->\n\n");
    s.push_str(&format!(
        "**统计**：{} 个文件，总 {} · 最近导入：{}\n\n",
        files.len(),
        format_bytes(total_bytes),
        format_date(latest_import),
    ));
    s.push_str("## 文件列表\n\n");
    s.push_str("| 文件 | 大小 | 导入时间 |\n|---|---|---|\n");
    for f in &files {
        s.push_str(&format!("| [{}]({}) | {} | {} |\n",
            f.current_name,
            url_encode(&f.current_name),
            format_bytes(f.size_bytes),
            format_date(f.imported_at)));
    }
    s.push_str("\n## 近 30 天改动\n\n");
    for c in &recent_changes {
        s.push_str(&format!("- {} {} `{}`\n",
            format_date(c.occurred_at),
            describe_action(&c.action, &c.detail_json),
            c.filename));
    }
    s.push_str("\n");
    s.push_str(END_MARKER);
    Ok(s)
}
```

### root::regenerate 类似

只是数据来自 db::list_categories_summary 和 db::recent_changes(限制天数=7)。

---

## 性能

- 每次重生成 = 1 次 SQL 查询（list）+ 1 次 SQL 查询（changes）+ 1 次文件写
- 单分类 1000 文件下 < 30ms
- 批量导入 50 个文件，重生成最多 50 次 → 用 debounce 合并

### Debounce（Stage 2）

后续可加：连续 import 期间延迟 README 重生成，最后统一刷新。MVP 不做。

---

## 边界情况

| 情况 | 行为 |
|---|---|
| 分类目录被用户手动删除 | regenerate 时检测到目录不存在 → 跳过 |
| README 文件被用户改写到无标记 | 在末尾追加 managed 段 + 标记 |
| 用户编辑 managed 段（标记内） | 下次重生成被覆盖（已在标记上方有警告） |
| 用户重命名 README.md | regenerate 重建 README.md（用户改名的不再被托管） |
| Windows 行尾 (`\r\n`) | 标记匹配用 contains，对换行不敏感 |

---

## i18n

README 文案根据 `RepoConfig.locale` 渲染：

- `zh-CN`：「统计」「文件列表」「近 30 天改动」「**用户备注**」
- `en`：`Stats` / `Files` / `Recent changes (30d)` / `User notes`

实现：

```rust
fn t(key: &str, locale: &str) -> &'static str {
    match (locale, key) {
        ("zh-CN", "stats") => "统计",
        ("en", "stats") => "Stats",
        ...
    }
}
```

详见 [../adr/0008-naming-and-i18n.md](../adr/0008-naming-and-i18n.md)。

---

## 测试

```rust
#[test]
fn preserves_user_section() {
    let repo = setup_test_repo_with_files();
    regenerate_for_category(&repo, "docs").unwrap();
    let readme = repo.join("docs/README.md");
    let content = std::fs::read_to_string(&readme).unwrap();
    let user_marker = "## 用户备注";
    std::fs::write(&readme, content.replace(
        user_marker,
        &format!("{}\n\n手动加的内容", user_marker)
    )).unwrap();

    regenerate_for_category(&repo, "docs").unwrap();

    let new_content = std::fs::read_to_string(&readme).unwrap();
    assert!(new_content.contains("手动加的内容"));
}

#[test]
fn rebuilds_markers_when_missing() {
    let repo = setup_test_repo_with_files();
    let readme = repo.join("docs/README.md");
    std::fs::write(&readme, "全是用户写的内容").unwrap();

    regenerate_for_category(&repo, "docs").unwrap();

    let content = std::fs::read_to_string(&readme).unwrap();
    assert!(content.contains("全是用户写的内容"));
    assert!(content.contains(BEGIN_MARKER));
    assert!(content.contains(END_MARKER));
}
```

---

## Related

- [../architecture/overview.md](../architecture/overview.md)
- [../adr/0007-readme-granularity.md](../adr/0007-readme-granularity.md)
- [storage.md](storage.md)
- [tree-scan.md](tree-scan.md)
