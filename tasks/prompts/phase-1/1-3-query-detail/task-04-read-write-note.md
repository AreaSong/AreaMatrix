# 1-3/task-04: C1-14 read-write-note

> 共享规则：`tasks/prompts/_shared/audit-rules.md`  
> 任务切片规则：`tasks/prompts/_shared/task-slicing-rules.md`  
> Manifest：`tasks/prompts/_shared/manifests/phase-1.md`

## 范围

实现文件伴生笔记读写，DB 与同目录 `.md` 文件保持一致。

## 绑定

- Core 能力：C1-14 read-write-note
- UX 页面：S1-14

## 核对清单

1. `read_note` 无笔记时返回 `None`。
2. `write_note` upsert `notes` 并写伴生 Markdown 文件。
3. 写笔记时记录 `change_log.edited_note`。
4. 写失败不破坏旧笔记内容。

## 完成标准

- 读空、写入、覆盖、文件不存在错误都有测试。
- DB 内容与伴生 `.md` 文件一致。
- 与 watcher 回流边界在文档中明确由 app 层 InFlightTracker 处理。

## 验证

```bash
cd core
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --workspace note
```
