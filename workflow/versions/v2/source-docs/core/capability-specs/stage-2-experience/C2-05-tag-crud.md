# C2-05 tag-crud

## 服务的 UX 页面

- S2-07 tags-add
- S2-08 tags-filter

## Core API

- 计划新增：`add_tag(repo_path, file_id, tag)`、`remove_tag`、`list_tags`

## 输入

- file_id、tag。

## 输出

- 更新后的 tag set。

## DB 变化

- 写入或删除 `tags` 表。
- 写入 change log。

## 文件系统变化

- 无。

## 错误码

- `FileNotFound`
- `Db`
- `InvalidPath`

## 验收标准

- 标签不替代分类，不移动文件。
- 重复标签幂等处理。
- 标签名称校验、大小写策略和排序稳定。

## 延后范围

- AI 自动标签建议属于 Stage 3。
