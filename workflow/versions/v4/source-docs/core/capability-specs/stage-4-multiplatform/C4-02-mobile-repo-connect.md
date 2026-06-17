# C4-02 mobile-repo-connect

## 服务的 UX 页面

- S4-IOS-01 connect-repo
- S4-X-04 repository-init-confirm
- S4-X-05 repository-adopt-confirm

## Core API

- `validate_repo_path`
- `init_repo`
- `load_config`

## 输入

- iOS security-scoped URL / provider path。

## 输出

- repo connection status 和推荐初始化/接管模式。

## DB 变化

- 初始化或接管时同 Stage 1 repo 能力。

## 文件系统变化

- 由平台层申请权限；Core 只处理授权后的路径。

## 错误码

- `PermissionDenied`
- `InvalidPath`
- `ICloudPlaceholder`

## 验收标准

- iOS 未授权不能静默失败。
- 空目录初始化和非空目录接管仍走确认页。
- 不绕过 Stage 1 用户文件安全不变量。

## 延后范围

- iCloud Drive 高级同步控制不在 Core。
