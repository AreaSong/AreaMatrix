# C4-18 missing-file-recovery

## 服务的 UX 页面

- S4-X-06 missing-file-recovery

## Core API

- 计划新增：`get_missing_file_state`、`remove_missing_file_record`、`relink_missing_file`

## 输入

- file_id、新路径或 remove record action。

## 输出

- recovery report。

## DB 变化

- 更新 file path 或移除索引记录。
- 写 change log。

## 文件系统变化

- Relink 只引用用户选择的新路径。
- Remove record 不删除文件。

## 错误码

- `FileNotFound`
- `PermissionDenied`
- `Db`

## 验收标准

- 缺失文件不导致静默删除记录。
- Remove record 必须确认，且不删除用户原文件。
- Relink 路径需校验 hash 或明确风险。

## 延后范围

- 自动全盘搜索缺失文件不在当前 Stage 4。
