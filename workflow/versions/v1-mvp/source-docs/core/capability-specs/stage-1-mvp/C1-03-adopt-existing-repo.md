# C1-03 adopt-existing-repo

## 服务的 UX 页面

- S1-03 validate-path
- S1-04 confirm-init
- S1-05 initializing
- S1-10 main-loading

## Core API

- `init_repo(repo_path, RepoInitOptions { mode: AdoptExisting, ... })`
- `get_latest_scan_session(repo_path)`
- `resume_scan_session(repo_path, scan_session_id)`

## 输入

- `repo_path`
- `RepoInitOptions`

## 输出

- 已接管资料库。
- `scan_sessions(kind=Adopt)` 记录和可恢复的扫描状态。
- `files.origin = Adopted` 的索引条目。

## DB 变化

- 初始化 schema。
- 写入 `scan_sessions`。
- 为已有用户文件插入或更新 `files`。

## 文件系统变化

- 只创建 `.areamatrix/**` 管理目录。
- 不移动、不重命名、不删除、不覆盖任何已有用户文件。
- 跳过 `.areamatrix/`、系统临时文件和 AreaMatrix generated overview。

## 错误码

- `PermissionDenied`
- `InvalidPath`
- `Io`
- `Db`
- `Config`

## 验收标准

- 非空目录接管不改变任何用户文件路径或内容。
- 中断后能通过 scan session 继续或给出恢复状态。
- `README.md` 作为普通用户文件索引，`AREAMATRIX.md` 与 generated overview 按文档规则跳过。

## 延后范围

- 后续外部变化监听由 C1-17 到 C1-19 处理。
- 视觉进度条由 UI 任务处理。
