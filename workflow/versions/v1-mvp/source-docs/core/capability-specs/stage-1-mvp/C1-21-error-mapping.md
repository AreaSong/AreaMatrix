# C1-21 error-mapping

## 服务的 UX 页面

- S1-03 validate-path
- S1-06 init-failed
- S1-11 main-repo-error
- S1-25 icloud-conflict-min
- S1-32 error-recovery

## Core API

- 所有 `[Throws=CoreError]` API。
- Swift AppError 包装层。

## 输入

- `CoreError` variant。
- 原始 path、reason 或 message。

## 输出

- 可供 UI 展示的错误类型、用户文案、严重程度和建议动作。

## DB 变化

- 无。

## 文件系统变化

- 无。

## 错误码

- `Io`
- `Db`
- `Config`
- `Classify`
- `Conflict`
- `DuplicateFile`
- `FileNotFound`
- `RepoNotInitialized`
- `InvalidPath`
- `ICloudPlaceholder`
- `StagingRecoveryRequired`
- `PermissionDenied`
- `Internal`

## 验收标准

- 每个 `CoreError` 都能被 Swift 层映射为用户可理解消息。
- 高严重错误进入 S1-32 或 repo error 状态，不被吞掉。
- 错误映射不依赖字符串 contains 做主分支判断。

## 延后范围

- 错误上报、日志打包和诊断上传属于后续发布完善。
