# C2-19 tag-suggestions

## 服务的 UX 页面

- S2-23 tag-suggestions

## Core API

- 计划新增：`suggest_tags_for_file`、`apply_tag_suggestions`

## 输入

- file_id、可选来源上下文、建议数量上限。

## 输出

- 建议标签、来源理由、是否已存在、是否需新建。

## DB 变化

- 采纳建议后写 tags、file_tags、change log 和 undo action。

## 文件系统变化

- 无。标签建议不得移动、重命名或删除文件。

## 错误码

- `FileNotFound`
- `Validation`
- `Conflict`
- `Db`

## 验收标准

- Stage 2 标签建议只基于文件名、相对路径和来源目录关键词。
- 不读取文件正文，不调用 AI，不发生网络访问。
- 采纳建议后能被搜索、筛选、详情页和 undo 读取。

## 延后范围

- AI 标签建议属于 Stage 3 的 C3-07。

