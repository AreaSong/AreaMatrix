# C2-06 batch-add-tags

## 服务的 UX 页面

- S2-09 batch-add-tags
- S2-10 undo-toast

## Core API

- 计划新增：`batch_add_tags(repo_path, file_ids, tags) -> BatchMutationReport`

## 输入

- file_ids、tags。

## 输出

- 成功、跳过、失败明细和 undo token。

## DB 变化

- 批量写 `tags`。
- 写入 change log 和 undo action。

## 文件系统变化

- 无。

## 错误码

- `Db`
- `FileNotFound`

## 验收标准

- 部分失败可追踪，不把失败项显示为成功。
- 可撤销项进入 Undo toast/history。
- 不修改文件内容或路径。

## 延后范围

- 批量 AI 标签建议属于 Stage 3。
