# C4-07 mobile-detail

## 服务的 UX 页面

- S4-IOS-05 mobile-file-detail

## Core API

- `get_file`
- `list_changes`
- `read_note`

## 输入

- file_id。

## 输出

- 移动端详情所需 metadata、日志、笔记。

## DB 变化

- 只读。

## 文件系统变化

- 无写入。

## 错误码

- `FileNotFound`
- `Db`

## 验收标准

- 详情页不从文件系统反推 metadata。
- Missing 状态能进入 S4-X-06。
- 日志和笔记可按需懒加载。

## 延后范围

- 移动端编辑笔记可后续扩展。
