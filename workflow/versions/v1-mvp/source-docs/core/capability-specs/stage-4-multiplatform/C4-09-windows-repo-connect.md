# C4-09 windows-repo-connect

## 服务的 UX 页面

- S4-WIN-01 choose-repo
- S4-X-04 repository-init-confirm
- S4-X-05 repository-adopt-confirm

## Core API

- `validate_repo_path`
- `init_repo`
- `load_config`

## 输入

- Windows path。

## 输出

- repo path validation 和 init/adopt result。

## DB 变化

- 同 Stage 1 repo 能力。

## 文件系统变化

- 使用 Windows 路径规则和权限探测。

## 错误码

- `InvalidPath`
- `PermissionDenied`
- `Config`

## 验收标准

- Windows 路径分隔符、保留名、大小写规则有测试。
- OneDrive 路径能提示风险，不自动控制同步。
- 接管非空目录仍不改用户文件。

## 延后范围

- Windows shell extension 不在当前任务。
