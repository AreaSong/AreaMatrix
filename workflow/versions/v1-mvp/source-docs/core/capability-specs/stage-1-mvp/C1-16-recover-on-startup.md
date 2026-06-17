# C1-16 recover-on-startup

## 服务的 UX 页面

- S1-05 initializing
- S1-10 main-loading
- S1-30 settings-advanced
- S1-32 error-recovery

## Core API

- `recover_on_startup(repo_path) -> RecoveryReport`

## 输入

- `repo_path`

## 输出

- `cleaned_staging_files`
- `reverted_staging_db_rows`
- `warnings`

## DB 变化

- 将未完成 staging rows 回滚或标记为可恢复状态。

## 文件系统变化

- 清理 `.areamatrix/staging/` 中可判定安全的临时文件。
- 不删除任何最终目录用户文件。

## 错误码

- `RepoNotInitialized`
- `Db`
- `Io`
- `PermissionDenied`

## 验收标准

- 崩溃残留 staging 文件能清理。
- active 文件和用户文件不得被误删。
- recovery report 可直接驱动 S1-32 展示。

## 延后范围

- 自动从备份恢复损坏 DB 属于后续高级恢复。
