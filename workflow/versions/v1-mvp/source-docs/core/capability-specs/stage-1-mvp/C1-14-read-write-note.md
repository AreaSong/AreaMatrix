# C1-14 read-write-note

## 服务的 UX 页面

- S1-14 detail-note

## Core API

- `read_note(repo_path, file_id) -> string?`
- `write_note(repo_path, file_id, content_md)`

## 输入

- `file_id`
- Markdown 文本。

## 输出

- 当前笔记内容或 `nil`。
- 写入成功无返回值。

## DB 变化

- `notes` upsert。
- `change_log.action = edited_note`。

## 文件系统变化

- 写入同目录伴生 `.md` 文件。
- 写入应由 app 层 InFlightTracker 标记，避免 watcher 回流。

## 失败与恢复

- 写入失败时不得破坏旧笔记内容。
- DB `notes`、`change_log` 与伴生 `.md` 文件必须保持一致；无法一致时返回错误而不是伪成功。
- `change_log.action = edited_note` 只在 DB 和伴生文件均写入成功后成立。
- 不删除、移动或覆盖未确认的用户原文件。

## 错误码

- `FileNotFound`
- `PermissionDenied`
- `Io`
- `Db`

## 验收标准

- 无笔记返回 `nil`。
- 写入后 DB 和伴生文件一致。
- 笔记写失败不应破坏旧内容。

## 延后范围

- 富文本编辑、双向链接、Markdown 预览增强属于 Stage 2+。
