# C4-21 replace-confirm-cross-platform

## 服务的 UX 页面

- S4-X-09 replace-confirm

## Core API

- `import_file` with overwrite strategy
- `delete_file`
- `resolve_sync_conflict`

## 输入

- target file、incoming file、confirmed overwrite action。

## 输出

- replace report。

## DB 变化

- 软删除/替换旧记录。
- 写 change log。

## 文件系统变化

- 丢弃版本必须进入平台 Trash 或保留备份。
- 不直接永久删除。

## 错误码

- `PermissionDenied`
- `Conflict`
- `Io`
- `Db`

## 验收标准

- Replace 必须二次确认。
- 平台 Trash 不可用时禁用 replace。
- 失败后旧版本和新版本状态可解释。

## 延后范围

- 内容级 merge 不在当前 Stage 4。
